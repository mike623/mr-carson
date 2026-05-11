import { v4 as uuid } from 'uuid';
import { query, run } from '../client.js';

interface ChatSessionRow {
  user_id: string;
  active_thread_id: string;
  started_at: string;
}

/**
 * Returns the active thread id for a user, creating one lazily if missing.
 * Threads are opaque UUIDs handed to Mastra Memory.
 */
export async function getOrCreateActiveThread(userId: string): Promise<string> {
  const rows = await query<ChatSessionRow>(
    `SELECT user_id, active_thread_id, started_at
     FROM chat_sessions WHERE user_id = ?`,
    [userId],
  );
  const existing = rows[0]?.active_thread_id;
  if (existing) return existing;
  const threadId = uuid();
  await run(
    `INSERT INTO chat_sessions (user_id, active_thread_id) VALUES (?, ?)`,
    [userId, threadId],
  );
  return threadId;
}

/**
 * Mints a new thread id and makes it active. Historical threads remain in
 * Mastra Memory storage — only the pointer here changes.
 */
export async function rotateActiveThread(userId: string): Promise<string> {
  const threadId = uuid();
  await run(
    `INSERT INTO chat_sessions (user_id, active_thread_id, started_at)
     VALUES (?, ?, now())
     ON CONFLICT (user_id) DO UPDATE SET
       active_thread_id = excluded.active_thread_id,
       started_at = excluded.started_at`,
    [userId, threadId],
  );
  return threadId;
}
