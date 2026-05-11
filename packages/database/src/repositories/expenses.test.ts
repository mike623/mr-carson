import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { closeConnection, run } from '../client.js';
import { migrate } from '../migrate.js';
import { seedCategories } from '../seed.js';
import { insertExpense, queryExpenses, topMerchants } from './expenses.js';

let tmp: string;

beforeAll(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'mr-carson-db-'));
  process.env.DUCKDB_PATH = join(tmp, 'test.duckdb');
  await migrate();
  await seedCategories();
});

afterAll(async () => {
  await closeConnection();
  rmSync(tmp, { recursive: true, force: true });
});

beforeEach(async () => {
  // Each test starts from a clean slate. Foreign-key order matters.
  await run('DELETE FROM expense_items');
  await run('DELETE FROM expenses');
  await run('DELETE FROM merchants');
});

const USER = 'u-1';

async function seedSample() {
  await insertExpense({
    userId: USER,
    expense: {
      merchant: 'Tesco',
      date: '2026-05-10',
      currency: 'GBP',
      total: 4.5,
      items: [
        { name: 'Milk', amount: 1.5, category: 'Groceries' },
        { name: 'Bread', amount: 3.0, category: 'Groceries' },
      ],
    },
  });
  await insertExpense({
    userId: USER,
    expense: {
      merchant: 'Pets at Home',
      date: '2026-05-09',
      currency: 'GBP',
      total: 22.0,
      items: [{ name: 'Cat food', amount: 22.0, category: 'Pets' }],
    },
  });
  await insertExpense({
    userId: 'other-user',
    expense: {
      merchant: 'Tesco',
      date: '2026-05-10',
      currency: 'GBP',
      total: 999,
      items: [{ name: 'Should not leak', amount: 999, category: 'Groceries' }],
    },
  });
}

describe('insertExpense', () => {
  it('returns a uuid and persists header + items', async () => {
    const { id } = await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 1.5, category: 'Groceries' }],
      },
    });
    expect(id).toMatch(/^[0-9a-f-]{36}$/);
    const result = await queryExpenses(USER, {});
    expect(result.count).toBe(1);
    expect(result.total).toBe(1.5);
  });

  it('idempotently upserts the merchant row', async () => {
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 1,
        items: [{ name: 'a', amount: 1, category: 'Groceries' }],
      },
    });
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-11',
        currency: 'GBP',
        total: 2,
        items: [{ name: 'b', amount: 2, category: 'Groceries' }],
      },
    });
    // No PK conflict thrown → success.
    const result = await queryExpenses(USER, { merchant: 'Tesco' });
    expect(result.count).toBe(2);
  });
});

describe('queryExpenses', () => {
  beforeEach(seedSample);

  it('isolates rows by userId', async () => {
    const result = await queryExpenses(USER, {});
    expect(result.count).toBe(3);
    expect(result.rows.every((r) => r.merchant !== 'Tesco' || r.amount < 999)).toBe(true);
  });

  it('filters by category case-insensitively', async () => {
    const result = await queryExpenses(USER, { category: 'pets' });
    expect(result.count).toBe(1);
    expect(result.total).toBe(22);
    expect(result.rows[0].category).toBe('Pets');
  });

  it('filters by partial merchant match (case-insensitive)', async () => {
    const result = await queryExpenses(USER, { merchant: 'pets' });
    expect(result.count).toBe(1);
    expect(result.rows[0].merchant).toBe('Pets at Home');
  });

  it('filters by date range', async () => {
    const result = await queryExpenses(USER, {
      startDate: '2026-05-10',
      endDate: '2026-05-10',
    });
    expect(result.count).toBe(2);
    expect(result.total).toBe(4.5);
  });

  it('honours limit', async () => {
    const result = await queryExpenses(USER, { limit: 1 });
    expect(result.rows).toHaveLength(1);
  });

  it('rounds total to 2 dp', async () => {
    await run('DELETE FROM expense_items');
    await run('DELETE FROM expenses');
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'X',
        date: '2026-05-10',
        currency: 'GBP',
        total: 0.3,
        items: [
          { name: 'a', amount: 0.1, category: 'Other' },
          { name: 'b', amount: 0.2, category: 'Other' },
        ],
      },
    });
    const result = await queryExpenses(USER, {});
    expect(result.total).toBe(0.3);
  });
});

describe('topMerchants', () => {
  beforeEach(seedSample);

  it('ranks merchants by total spend', async () => {
    const top = await topMerchants(USER, {}, 5);
    expect(top[0].merchant).toBe('Pets at Home');
    expect(top[0].total).toBe(22);
    expect(top[1].merchant).toBe('Tesco');
    expect(top[1].total).toBe(4.5);
  });
});
