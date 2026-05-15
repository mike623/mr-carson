import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { closeConnection, run } from '../client.js';
import { migrate } from '../migrate.js';
import { seedCategories } from '../seed.js';
import { byCategoryOverTime, findByImageHash, findSoftDuplicate, insertExpense, queryExpenses, topMerchants } from './expenses.js';

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

  it('exposes expenseId and sourceFile on each row', async () => {
    await run('DELETE FROM expense_items');
    await run('DELETE FROM expenses');
    const { id: tescoId } = await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 1.5,
        items: [
          { name: 'Milk', amount: 1.0, category: 'Groceries' },
          { name: 'Bread', amount: 0.5, category: 'Groceries' },
        ],
      },
      sourceFile: '/uploads/2026-05-10-tesco.jpg',
    });
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Sainsburys',
        date: '2026-05-11',
        currency: 'GBP',
        total: 2.0,
        items: [{ name: 'Eggs', amount: 2.0, category: 'Groceries' }],
      },
      // sourceFile omitted — should surface as null
    });
    const result = await queryExpenses(USER, {});
    const tesco = result.rows.filter((r) => r.merchant === 'Tesco');
    expect(tesco).toHaveLength(2);
    for (const r of tesco) {
      expect(r.expenseId).toBe(tescoId);
      expect(r.sourceFile).toBe('/uploads/2026-05-10-tesco.jpg');
    }
    const sains = result.rows.find((r) => r.merchant === 'Sainsburys');
    expect(sains?.sourceFile).toBeNull();
    expect(sains?.expenseId).toMatch(/^[0-9a-f-]{36}$/);
  });

  describe('queryExpenses – item name search', () => {
    beforeEach(async () => {
      await run('DELETE FROM expense_items');
      await run('DELETE FROM expenses');
      await insertExpense({
        userId: USER,
        expense: {
          merchant: 'Wagamama',
          date: '2026-05-10',
          currency: 'GBP',
          total: 12.0,
          items: [{ name: 'Chicken Udon', amount: 12.0, category: 'Dining' }],
        },
      });
      await insertExpense({
        userId: USER,
        expense: {
          merchant: 'Pho Restaurant',
          date: '2026-05-11',
          currency: 'GBP',
          total: 10.0,
          items: [{ name: 'Beef Pho', amount: 10.0, category: 'Dining' }],
        },
      });
      await insertExpense({
        userId: USER,
        expense: {
          merchant: 'Tesco',
          date: '2026-05-12',
          currency: 'GBP',
          total: 3.0,
          items: [{ name: 'Milk', amount: 3.0, category: 'Groceries' }],
        },
      });
    });

    it('filters by single itemName (case-insensitive ILIKE)', async () => {
      const result = await queryExpenses(USER, { itemName: 'udon' });
      expect(result.count).toBe(1);
      expect(result.rows[0].name).toBe('Chicken Udon');
    });

    it('filters by itemNames array (OR logic)', async () => {
      const result = await queryExpenses(USER, {
        itemNames: ['udon', 'pho'],
      });
      expect(result.count).toBe(2);
      const names = result.rows.map((r) => r.name).sort();
      expect(names).toEqual(['Beef Pho', 'Chicken Udon']);
    });

    it('itemNames with no matches returns empty rows', async () => {
      const result = await queryExpenses(USER, {
        itemNames: ['ramen', 'soba'],
      });
      expect(result.count).toBe(0);
      expect(result.rows).toEqual([]);
    });
  });
});

describe('byCategoryOverTime', () => {
  beforeEach(async () => {
    // Three weeks of mixed categories for USER + one cross-user row.
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-04-06', // Mon, ISO week 15
        currency: 'GBP',
        total: 5,
        items: [{ name: 'Milk', amount: 5, category: 'Groceries' }],
      },
    });
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-04-08',
        currency: 'GBP',
        total: 3,
        items: [{ name: 'Bread', amount: 3, category: 'Groceries' }],
      },
    });
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Pets at Home',
        date: '2026-04-13', // ISO week 16
        currency: 'GBP',
        total: 10,
        items: [{ name: 'Cat food', amount: 10, category: 'Pets' }],
      },
    });
    await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-04-20', // ISO week 17
        currency: 'GBP',
        total: 7,
        items: [{ name: 'Eggs', amount: 7, category: 'Groceries' }],
      },
    });
    await insertExpense({
      userId: 'other-user',
      expense: {
        merchant: 'Tesco',
        date: '2026-04-06',
        currency: 'GBP',
        total: 999,
        items: [{ name: 'Leak', amount: 999, category: 'Groceries' }],
      },
    });
  });

  it('groups by week and category, isolated per user', async () => {
    const result = await byCategoryOverTime(USER, {
      startDate: '2026-04-01',
      endDate: '2026-04-30',
      granularity: 'week',
    });
    // 2 weeks × Groceries (wk15, wk17) + 1 week × Pets (wk16) = 3 rows.
    expect(result.rows).toHaveLength(3);
    expect(result.granularity).toBe('week');
    // No 999 leak.
    expect(result.rows.every((r) => r.total < 100)).toBe(true);

    const groceriesWk15 = result.rows.find(
      (r) => r.bucket === '2026-04-06' && r.category === 'Groceries',
    );
    expect(groceriesWk15?.total).toBe(8); // 5 + 3
    const petsWk16 = result.rows.find(
      (r) => r.bucket === '2026-04-13' && r.category === 'Pets',
    );
    expect(petsWk16?.total).toBe(10);
  });

  it('honours month granularity', async () => {
    const result = await byCategoryOverTime(USER, {
      startDate: '2026-04-01',
      endDate: '2026-04-30',
      granularity: 'month',
    });
    // One bucket (April) × 2 categories.
    const buckets = new Set(result.rows.map((r) => r.bucket));
    expect(buckets.size).toBe(1);
    expect([...buckets][0]).toBe('2026-04-01');
    expect(result.rows.length).toBe(2);
  });

  it('filters by category', async () => {
    const result = await byCategoryOverTime(USER, {
      startDate: '2026-04-01',
      endDate: '2026-04-30',
      granularity: 'week',
      category: 'Pets',
    });
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0].category).toBe('Pets');
    expect(result.rows[0].total).toBe(10);
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

describe('findByImageHash', () => {
  it('returns null when no match', async () => {
    const result = await findByImageHash(USER, 'abc123');
    expect(result).toBeNull();
  });

  it('returns the expense id when hash matches', async () => {
    const { id } = await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 4.5, category: 'Groceries' }],
      },
      imageHash: 'deadbeef',
    });
    const result = await findByImageHash(USER, 'deadbeef');
    expect(result).toBe(id);
  });

  it("does not match another user's hash", async () => {
    await insertExpense({
      userId: 'other-user',
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 4.5, category: 'Groceries' }],
      },
      imageHash: 'sharedHash',
    });
    const result = await findByImageHash(USER, 'sharedHash');
    expect(result).toBeNull();
  });
});

describe('findSoftDuplicate', () => {
  it('returns null when no match', async () => {
    const result = await findSoftDuplicate(USER, {
      merchant: 'Tesco',
      date: '2026-05-10',
      total: 4.5,
      currency: 'GBP',
    });
    expect(result).toBeNull();
  });

  it('returns matching expense when fields align', async () => {
    const { id } = await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 4.5, category: 'Groceries' }],
      },
    });
    const result = await findSoftDuplicate(USER, {
      merchant: 'Tesco',
      date: '2026-05-10',
      total: 4.5,
      currency: 'GBP',
    });
    expect(result?.id).toBe(id);
    expect(result?.merchant).toBe('Tesco');
    expect(result?.date).toBe('2026-05-10');
    expect(result?.total).toBeCloseTo(4.5);
  });

  it('is case-insensitive on merchant', async () => {
    const { id } = await insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 4.5, category: 'Groceries' }],
      },
    });
    const result = await findSoftDuplicate(USER, {
      merchant: 'TESCO',
      date: '2026-05-10',
      total: 4.5,
      currency: 'GBP',
    });
    expect(result?.id).toBe(id);
  });

  it('does not match a different user', async () => {
    await insertExpense({
      userId: 'other-user',
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 4.5,
        items: [{ name: 'Milk', amount: 4.5, category: 'Groceries' }],
      },
    });
    const result = await findSoftDuplicate(USER, {
      merchant: 'Tesco',
      date: '2026-05-10',
      total: 4.5,
      currency: 'GBP',
    });
    expect(result).toBeNull();
  });
});
