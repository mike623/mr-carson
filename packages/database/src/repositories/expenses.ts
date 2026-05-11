import { v4 as uuid } from 'uuid';
import type { Expense, QueryExpensesArgs, QueryExpensesResult } from '@mr-carson/shared-types';
import { query, run } from '../client.js';
import { resolveDateRange } from '../util/dateRange.js';

export interface InsertExpenseInput {
  userId: string;
  expense: Expense;
  sourceFile?: string | null;
}

export async function insertExpense(input: InsertExpenseInput): Promise<{ id: string }> {
  const id = uuid();
  await run(
    `INSERT INTO expenses (id, user_id, merchant, date, currency, total, source_file)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      input.userId,
      input.expense.merchant,
      input.expense.date,
      input.expense.currency,
      input.expense.total,
      input.sourceFile ?? null,
    ],
  );

  for (const item of input.expense.items) {
    await run(
      `INSERT INTO expense_items (id, expense_id, name, category, amount)
       VALUES (?, ?, ?, ?, ?)`,
      [uuid(), id, item.name, item.category, item.amount],
    );
  }

  await run(
    `INSERT INTO merchants (name, normalized) VALUES (?, ?)
     ON CONFLICT (name) DO NOTHING`,
    [input.expense.merchant, input.expense.merchant.trim().toLowerCase()],
  );

  return { id };
}

interface ItemRow {
  date: string;
  merchant: string;
  name: string;
  category: string;
  amount: number;
  currency: string;
}

export async function queryExpenses(
  userId: string,
  args: QueryExpensesArgs,
): Promise<QueryExpensesResult> {
  const where: string[] = ['e.user_id = ?'];
  const params: unknown[] = [userId];

  if (args.category) {
    where.push('LOWER(i.category) = LOWER(?)');
    params.push(args.category);
  }
  if (args.merchant) {
    where.push('LOWER(e.merchant) LIKE LOWER(?)');
    params.push(`%${args.merchant}%`);
  }

  const range = resolveDateRange(args);
  if (range) {
    where.push('e.date >= ? AND e.date <= ?');
    params.push(range.start, range.end);
  }

  const limit = args.limit ?? 200;

  const sql = `
    SELECT
      CAST(e.date AS VARCHAR) AS date,
      e.merchant AS merchant,
      i.name AS name,
      i.category AS category,
      CAST(i.amount AS DOUBLE) AS amount,
      e.currency AS currency
    FROM expenses e
    JOIN expense_items i ON i.expense_id = e.id
    WHERE ${where.join(' AND ')}
    ORDER BY e.date DESC, e.merchant ASC
    LIMIT ?
  `;
  params.push(limit);

  const rows = await query<ItemRow>(sql, params);
  const total = rows.reduce((acc, r) => acc + Number(r.amount), 0);
  const currency = rows[0]?.currency ?? (process.env.DEFAULT_CURRENCY ?? 'GBP');

  return {
    total: Math.round(total * 100) / 100,
    currency,
    count: rows.length,
    rows: rows.map((r) => ({ ...r, amount: Number(r.amount) })),
  };
}

export type Granularity = 'day' | 'week' | 'month';

export interface ByCategoryOverTimeArgs {
  dateRange?: import('@mr-carson/shared-types').DateRange;
  startDate?: string;
  endDate?: string;
  category?: string;
  granularity?: Granularity;
}

export interface CategoryBucketRow {
  bucket: string;
  category: string;
  total: number;
}

export async function byCategoryOverTime(
  userId: string,
  args: ByCategoryOverTimeArgs,
): Promise<{ rows: CategoryBucketRow[]; granularity: Granularity; currency: string }> {
  const granularity: Granularity = args.granularity ?? 'week';
  const where: string[] = ['e.user_id = ?'];
  const params: unknown[] = [userId];

  if (args.category) {
    where.push('LOWER(i.category) = LOWER(?)');
    params.push(args.category);
  }
  const range = resolveDateRange({
    dateRange: args.dateRange ?? 'last_month',
    startDate: args.startDate,
    endDate: args.endDate,
  });
  if (range) {
    where.push('e.date >= ? AND e.date <= ?');
    params.push(range.start, range.end);
  }

  const sql = `
    SELECT
      CAST(DATE_TRUNC('${granularity}', e.date) AS VARCHAR) AS bucket,
      i.category AS category,
      CAST(SUM(i.amount) AS DOUBLE) AS total,
      ANY_VALUE(e.currency) AS currency
    FROM expenses e
    JOIN expense_items i ON i.expense_id = e.id
    WHERE ${where.join(' AND ')}
    GROUP BY bucket, i.category
    ORDER BY bucket ASC, total DESC
  `;
  const raw = await query<{ bucket: string; category: string; total: number; currency: string }>(
    sql,
    params,
  );
  const rows: CategoryBucketRow[] = raw.map((r) => ({
    bucket: r.bucket.slice(0, 10),
    category: r.category,
    total: Math.round(Number(r.total) * 100) / 100,
  }));
  const currency = raw[0]?.currency ?? (process.env.DEFAULT_CURRENCY ?? 'GBP');
  return { rows, granularity, currency };
}

export async function topMerchants(
  userId: string,
  args: QueryExpensesArgs,
  topN = 5,
): Promise<Array<{ merchant: string; total: number; currency: string }>> {
  const where: string[] = ['user_id = ?'];
  const params: unknown[] = [userId];
  const range = resolveDateRange(args);
  if (range) {
    where.push('date >= ? AND date <= ?');
    params.push(range.start, range.end);
  }
  const sql = `
    SELECT merchant,
           CAST(SUM(total) AS DOUBLE) AS total,
           ANY_VALUE(currency) AS currency
    FROM expenses
    WHERE ${where.join(' AND ')}
    GROUP BY merchant
    ORDER BY total DESC
    LIMIT ?
  `;
  params.push(topN);
  const rows = await query<{ merchant: string; total: number; currency: string }>(sql, params);
  return rows.map((r) => ({ ...r, total: Number(r.total) }));
}
