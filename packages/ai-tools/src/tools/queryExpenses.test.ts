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
import { makeQueryExpensesTool } from './queryExpenses.js';

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

describe('makeQueryExpensesTool', () => {
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
    const tool = makeQueryExpensesTool(USER, {
      add: (p) => collected.push(p),
    });

    const result = await tool.execute!({ context: {} } as never);
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
    const tool = makeQueryExpensesTool(USER, {
      add: (p) => collected.push(p),
    });
    await tool.execute!({ context: {} } as never);
    expect(collected).toEqual(['/uploads/tesco.jpg']);
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
    const tool = makeQueryExpensesTool(USER);
    const result = await tool.execute!({ context: {} } as never);
    expect(result.count).toBe(1);
  });
});
