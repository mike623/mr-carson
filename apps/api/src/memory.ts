import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { Memory } from '@mastra/memory';
import { LibSQLStore } from '@mastra/libsql';

let singleton: Memory | null = null;

function memoryDbUrl(): string {
  const raw = process.env.MEMORY_DB_PATH ?? './data/memory.db';
  const abs = resolve(raw);
  mkdirSync(dirname(abs), { recursive: true });
  return `file:${abs}`;
}

/**
 * One Memory instance per process. Threads are namespaced by Telegram user id;
 * /new rotates the thread id so the agent forgets prior turns without losing
 * the historical record in LibSQL.
 */
export function getMemory(): Memory {
  if (singleton) return singleton;
  singleton = new Memory({
    storage: new LibSQLStore({ id: 'mr-carson-memory', url: memoryDbUrl() }),
    options: {
      lastMessages: 20,
    },
  });
  return singleton;
}
