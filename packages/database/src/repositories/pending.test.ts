import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { closeConnection, run } from '../client.js';
import { migrate } from '../migrate.js';
import {
  createPending,
  getLatestPendingForUser,
  getPending,
  setPendingExtraction,
  setPendingOcr,
  setPendingStatus,
} from './pending.js';

let tmp: string;

beforeAll(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'mr-carson-pending-'));
  process.env.DUCKDB_PATH = join(tmp, 'test.duckdb');
  await migrate();
});

afterAll(async () => {
  await closeConnection();
  rmSync(tmp, { recursive: true, force: true });
});

beforeEach(async () => {
  await run('DELETE FROM pending_expenses');
});

const sampleExpense = {
  merchant: 'Tesco',
  date: '2026-05-10',
  currency: 'GBP',
  total: 1.5,
  items: [{ name: 'Milk', amount: 1.5, category: 'Groceries' }],
};

describe('pending repo lifecycle', () => {
  it('creates → ocr → extraction → confirmed', async () => {
    const id = await createPending({ userId: 'u', chatId: 'c', filePath: '/tmp/r.jpg' });

    let p = await getPending(id);
    expect(p?.status).toBe('RECEIVED');
    expect(p?.filePath).toBe('/tmp/r.jpg');

    await setPendingOcr(id, 'raw ocr text');
    p = await getPending(id);
    expect(p?.status).toBe('OCR_COMPLETE');
    expect(p?.rawOcr).toBe('raw ocr text');

    await setPendingExtraction(id, sampleExpense);
    p = await getPending(id);
    expect(p?.status).toBe('AWAITING_CONFIRMATION');
    expect(p?.extracted?.merchant).toBe('Tesco');
    expect(p?.extracted?.total).toBe(1.5);

    await setPendingStatus(id, 'CONFIRMED');
    p = await getPending(id);
    expect(p?.status).toBe('CONFIRMED');
    expect(p?.errorMessage).toBeNull();
  });

  it('records error message on FAILED', async () => {
    const id = await createPending({ userId: 'u', chatId: 'c', filePath: null });
    await setPendingStatus(id, 'FAILED', 'OCR returned empty text');
    const p = await getPending(id);
    expect(p?.status).toBe('FAILED');
    expect(p?.errorMessage).toBe('OCR returned empty text');
  });

  it('getLatestPendingForUser returns only AWAITING_CONFIRMATION rows', async () => {
    const a = await createPending({ userId: 'u', chatId: 'c', filePath: null });
    const b = await createPending({ userId: 'u', chatId: 'c', filePath: null });
    await setPendingExtraction(a, sampleExpense);
    await setPendingExtraction(b, sampleExpense);
    await setPendingStatus(a, 'CONFIRMED');

    const latest = await getLatestPendingForUser('u');
    expect(latest?.id).toBe(b);
  });

  it('returns null for unknown id', async () => {
    expect(await getPending('00000000-0000-0000-0000-000000000000')).toBeNull();
  });

  it('isolates pending rows by userId', async () => {
    const a = await createPending({ userId: 'alice', chatId: 'c', filePath: null });
    await setPendingExtraction(a, sampleExpense);
    expect((await getLatestPendingForUser('bob'))).toBeNull();
    expect((await getLatestPendingForUser('alice'))?.id).toBe(a);
  });
});
