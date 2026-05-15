import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  closeConnection,
  expensesRepo,
  migrate,
  run,
  seedCategories,
} from '@mr-carson/database';
import { queryExpensesTool } from './queryExpenses.js';

let tmp: string;

beforeAll(async () => {
  tmp = mkdtempSync(join(tmpdir(), 'mr-carson-aitools-'));
  process.env.DUCKDB_PATH = join(tmp, 'test.duckdb');
  await migrate();
  await seedCategories();
});

afterAll(async () => {
  await closeConnection();
  rmSync(tmp, { recursive: true, force: true });
});

beforeEach(async () => {
  await run('DELETE FROM expense_items');
  await run('DELETE FROM expenses');
});

const USER = 'u-1';

describe('queryExpensesTool', () => {
  it('collects distinct non-null sourceFiles from result rows', async () => {
    await expensesRepo.insertExpense({
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
      sourceFile: '/uploads/tesco.jpg',
    });
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Pets at Home',
        date: '2026-05-09',
        currency: 'GBP',
        total: 22.0,
        items: [{ name: 'Cat food', amount: 22.0, category: 'Pets' }],
      },
      sourceFile: '/uploads/pets.jpg',
    });
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'CashOnly',
        date: '2026-05-08',
        currency: 'GBP',
        total: 5,
        items: [{ name: 'X', amount: 5, category: 'Other' }],
      },
      // no sourceFile
    });

    const collected: string[] = [];
    const mockRequestContext = new Map([
      ['userId', USER],
      ['attachments', { add: (p: string) => collected.push(p) }],
    ]);

    const result = await queryExpensesTool.execute!({ includeImages: true }, { requestContext: mockRequestContext } as never);
    expect(result.count).toBe(4);
    expect(collected.sort()).toEqual(['/uploads/pets.jpg', '/uploads/tesco.jpg']);
  });

  it('deduplicates sourceFile when many items share one receipt', async () => {
    await expensesRepo.insertExpense({
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
      sourceFile: '/uploads/tesco.jpg',
    });
    const collected: string[] = [];
    const mockRequestContext = new Map([
      ['userId', USER],
      ['attachments', { add: (p: string) => collected.push(p) }],
    ]);
    await queryExpensesTool.execute!({ includeImages: true }, { requestContext: mockRequestContext } as never);
    expect(collected).toEqual(['/uploads/tesco.jpg']);
  });

  it('returns vatTotal summed from expenses', async () => {
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 10.0,
        vat: 1.67,
        items: [{ name: 'Milk', amount: 10.0, category: 'Groceries' }],
      },
    });
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Shell',
        date: '2026-05-11',
        currency: 'GBP',
        total: 50.0,
        vat: 8.33,
        items: [{ name: 'Fuel', amount: 50.0, category: 'Transport' }],
      },
    });
    const mockRequestContext = new Map([['userId', USER]]);
    const result = await queryExpensesTool.execute!({}, { requestContext: mockRequestContext } as never);
    expect(result.vatTotal).toBeCloseTo(10.0, 1);
  });

  it('works without a collector (backward compatible)', async () => {
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 1,
        items: [{ name: 'a', amount: 1, category: 'Groceries' }],
      },
      sourceFile: '/uploads/tesco.jpg',
    });
    const mockRequestContext = new Map([['userId', USER]]);
    const result = await queryExpensesTool.execute!({}, { requestContext: mockRequestContext } as never);
    expect(result.count).toBe(1);
  });

  it('filters by itemName through tool', async () => {
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Wagamama',
        date: '2026-05-10',
        currency: 'GBP',
        total: 12.0,
        items: [{ name: 'Chicken Udon', amount: 12.0, category: 'Dining' }],
      },
    });
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Tesco',
        date: '2026-05-10',
        currency: 'GBP',
        total: 3.0,
        items: [{ name: 'Milk', amount: 3.0, category: 'Groceries' }],
      },
    });
    const mockRequestContext = new Map([['userId', USER]]);
    const result = await queryExpensesTool.execute!(
      { itemName: 'udon' },
      { requestContext: mockRequestContext } as never,
    );
    expect(result.count).toBe(1);
    expect(result.rows[0].name).toBe('Chicken Udon');
  });

  it('filters by itemNames array through tool', async () => {
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Wagamama',
        date: '2026-05-10',
        currency: 'GBP',
        total: 12.0,
        items: [{ name: 'Chicken Udon', amount: 12.0, category: 'Dining' }],
      },
    });
    await expensesRepo.insertExpense({
      userId: USER,
      expense: {
        merchant: 'Ramen House',
        date: '2026-05-11',
        currency: 'GBP',
        total: 11.0,
        items: [{ name: 'Tonkotsu Ramen', amount: 11.0, category: 'Dining' }],
      },
    });
    const mockRequestContext = new Map([['userId', USER]]);
    const result = await queryExpensesTool.execute!(
      { itemNames: ['udon', 'ramen'] },
      { requestContext: mockRequestContext } as never,
    );
    expect(result.count).toBe(2);
  });
});
