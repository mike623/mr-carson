import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { closeConnection, run } from '../client.js';
import { migrate } from '../migrate.js';
import { getOrCreateActiveThread, rotateActiveThread } from './chatSessions.js';

let tmp: string;

beforeAll(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'mr-carson-chat-'));
  process.env.DUCKDB_PATH = join(tmp, 'test.duckdb');
  await migrate();
});

afterAll(async () => {
  await closeConnection();
  rmSync(tmp, { recursive: true, force: true });
});

beforeEach(async () => {
  await run('DELETE FROM chat_sessions');
});

describe('chatSessions repo', () => {
  it('creates a thread lazily and reuses it', async () => {
    const first = await getOrCreateActiveThread('u');
    const second = await getOrCreateActiveThread('u');
    expect(first).toMatch(/^[0-9a-f-]{36}$/);
    expect(second).toBe(first);
  });

  it('rotateActiveThread replaces the active thread id', async () => {
    const first = await getOrCreateActiveThread('u');
    const rotated = await rotateActiveThread('u');
    expect(rotated).not.toBe(first);
    expect(await getOrCreateActiveThread('u')).toBe(rotated);
  });

  it('isolates threads by user id', async () => {
    const alice = await getOrCreateActiveThread('alice');
    const bob = await getOrCreateActiveThread('bob');
    expect(alice).not.toBe(bob);
    await rotateActiveThread('alice');
    expect(await getOrCreateActiveThread('bob')).toBe(bob);
  });
});
