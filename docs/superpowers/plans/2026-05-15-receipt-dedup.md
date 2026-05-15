# Receipt Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject duplicate receipt uploads before OCR runs, and warn the user when a different image produces structurally identical fields.

**Architecture:** SHA-256 hash of the uploaded file is checked against `expenses.image_hash` before any pending row is created — returning HTTP 409 immediately. After extraction, a soft-dedup SQL query checks for field-level matches and surfaces a warning in the ingest response. The hash is re-computed from `filePath` at confirm time and stored on the `expenses` row.

**Tech Stack:** Node.js built-in `node:crypto` (no new deps), DuckDB via `@mr-carson/database`, TypeScript.

---

## File Map

| File | Change |
|------|--------|
| `packages/database/src/schema.sql` | Add `image_hash TEXT` column + index to `expenses` |
| `packages/database/src/schema.ts` | Sync `SCHEMA_SQL` constant |
| `packages/database/src/repositories/expenses.ts` | Add `findByImageHash()`, add `findSoftDuplicate()`, add `imageHash` to `insertExpense` |
| `packages/database/src/repositories/expenses.test.ts` | Tests for the three new repository behaviours |
| `apps/api/src/pipeline.ts` | Add `imageHash?: string` to `commitConfirmed` opts |
| `apps/api/src/mastra.ts` | Hash file in `/receipts/ingest`, check 409, add soft-dedup; re-hash at `/receipts/:id/confirm` |

---

## Task 1: Add `image_hash` column to schema

**Files:**
- Modify: `packages/database/src/schema.sql`
- Modify: `packages/database/src/schema.ts`

- [ ] **Step 1: Add column + index to schema.sql**

In `packages/database/src/schema.sql`, after the existing `vat` backfill block and before `CREATE TABLE expense_items`, add:

```sql
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS image_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_expenses_image_hash ON expenses (image_hash);
```

- [ ] **Step 2: Sync SCHEMA_SQL constant in schema.ts**

In `packages/database/src/schema.ts`, the `SCHEMA_SQL` string is a duplicate of `schema.sql`. Add the same two lines at the same position inside the template literal (after the `UPDATE expenses SET vat = 0 WHERE vat IS NULL;` line and before the `CREATE TABLE IF NOT EXISTS expense_items` block):

```ts
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS image_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_expenses_image_hash ON expenses (image_hash);
```

- [ ] **Step 3: Verify migration is idempotent**

```bash
pnpm --filter @mr-carson/database test
```

Expected: all existing tests pass (the `ALTER TABLE IF NOT EXISTS` form is safe to re-run).

- [ ] **Step 4: Commit**

```bash
git add packages/database/src/schema.sql packages/database/src/schema.ts
git commit -m "feat(db): add image_hash column to expenses"
```

---

## Task 2: Repository — `findByImageHash`, `findSoftDuplicate`, `insertExpense` with hash

**Files:**
- Modify: `packages/database/src/repositories/expenses.ts`
- Modify: `packages/database/src/repositories/expenses.test.ts`

- [ ] **Step 1: Write failing tests**

Open `packages/database/src/repositories/expenses.test.ts`. Add a new `describe` block at the bottom:

```ts
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

  it('does not match another user\'s hash', async () => {
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
```

Also update the import line at the top of the test file to include the new functions:

```ts
import { byCategoryOverTime, findByImageHash, findSoftDuplicate, insertExpense, queryExpenses, topMerchants } from './expenses.js';
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
pnpm --filter @mr-carson/database test -- src/repositories/expenses.test.ts
```

Expected: `findByImageHash` and `findSoftDuplicate` — `TypeError: ... is not a function`.

- [ ] **Step 3: Implement in expenses.ts**

Update `InsertExpenseInput` to accept an optional `imageHash`:

```ts
export interface InsertExpenseInput {
  userId: string;
  expense: Expense;
  sourceFile?: string | null;
  imageHash?: string | null;
}
```

Update the `INSERT INTO expenses` statement in `insertExpense` to include `image_hash`:

```ts
await run(
  `INSERT INTO expenses (id, user_id, merchant, date, currency, total, vat, source_file, image_hash)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  [
    id,
    input.userId,
    input.expense.merchant,
    input.expense.date,
    input.expense.currency,
    input.expense.total,
    input.expense.vat ?? 0,
    input.sourceFile ?? null,
    input.imageHash ?? null,
  ],
);
```

Add `findByImageHash` after `insertExpense`:

```ts
export async function findByImageHash(
  userId: string,
  hash: string,
): Promise<string | null> {
  const rows = await query<{ id: string }>(
    `SELECT CAST(id AS VARCHAR) AS id FROM expenses WHERE user_id = ? AND image_hash = ? LIMIT 1`,
    [userId, hash],
  );
  return rows[0]?.id ?? null;
}
```

Add `findSoftDuplicate` after `findByImageHash`:

```ts
export interface SoftDuplicateMatch {
  id: string;
  merchant: string;
  date: string;
  total: number;
}

export async function findSoftDuplicate(
  userId: string,
  fields: { merchant: string; date: string; total: number; currency: string },
): Promise<SoftDuplicateMatch | null> {
  const rows = await query<{ id: string; merchant: string; date: string; total: number }>(
    `SELECT CAST(id AS VARCHAR) AS id, merchant, CAST(date AS VARCHAR) AS date, CAST(total AS DOUBLE) AS total
     FROM expenses
     WHERE user_id = ?
       AND LOWER(merchant) = LOWER(?)
       AND date = ?
       AND CAST(total AS DOUBLE) = ?
       AND currency = ?
     LIMIT 1`,
    [userId, fields.merchant, fields.date, fields.total, fields.currency],
  );
  if (!rows[0]) return null;
  return {
    id: rows[0].id,
    merchant: rows[0].merchant,
    date: rows[0].date.slice(0, 10),
    total: Number(rows[0].total),
  };
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
pnpm --filter @mr-carson/database test -- src/repositories/expenses.test.ts
```

Expected: all tests pass including the new `findByImageHash` and `findSoftDuplicate` suites.

- [ ] **Step 5: Commit**

```bash
git add packages/database/src/repositories/expenses.ts packages/database/src/repositories/expenses.test.ts
git commit -m "feat(db): add findByImageHash and findSoftDuplicate to expenses repo"
```

---

## Task 3: Pipeline — `commitConfirmed` accepts `imageHash`

**Files:**
- Modify: `apps/api/src/pipeline.ts`

- [ ] **Step 1: Update `commitConfirmed` opts and pass hash to `insertExpense`**

Replace the existing `commitConfirmed` function in `apps/api/src/pipeline.ts`:

```ts
export async function commitConfirmed(opts: {
  pendingId: string;
  userId: string;
  expense: Expense;
  sourceFile?: string | null;
  imageHash?: string | null;
}): Promise<{ id: string }> {
  const result = await expensesRepo.insertExpense({
    userId: opts.userId,
    expense: opts.expense,
    sourceFile: opts.sourceFile ?? null,
    imageHash: opts.imageHash ?? null,
  });
  await pendingRepo.setPendingStatus(opts.pendingId, 'INSERTED');
  return result;
}
```

- [ ] **Step 2: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add apps/api/src/pipeline.ts
git commit -m "feat(api): commitConfirmed accepts imageHash"
```

---

## Task 4: Route — hash on ingest, 409 on duplicate, soft-dedup warning

**Files:**
- Modify: `apps/api/src/mastra.ts`

- [ ] **Step 1: Add hash utility at top of mastra.ts**

Add these imports at the top of `apps/api/src/mastra.ts` (after the existing Node imports):

```ts
import { createHash } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
```

Add a helper function just before the `mastraDbUrl` function:

```ts
function hashFile(filePath: string): string {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function hashFileIfExists(filePath: string | null | undefined): string | undefined {
  if (!filePath || !existsSync(filePath)) return undefined;
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}
```

- [ ] **Step 2: Update the `/receipts/ingest` handler**

Also add `expensesRepo` to the import from `@mr-carson/database`:

```ts
import { migrate, seedCategories, pendingRepo, expensesRepo, chatSessionsRepo } from '@mr-carson/database';
```

Replace the existing `/receipts/ingest` handler body with:

```ts
handler: async (c) => {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    throw new HTTPException(400, { message: 'invalid JSON' });
  }
  const input = IngestBody.parse(body);

  // Hard dedup: reject identical file before OCR runs.
  const imageHash = hashFile(input.filePath);
  const existingId = await expensesRepo.findByImageHash(input.userId, imageHash);
  if (existingId) {
    return c.json({ error: 'duplicate', existingId }, 409);
  }

  const pendingId = await pendingRepo.createPending(input);
  try {
    const expense = await processReceipt({ pendingId, filePath: input.filePath });

    // Soft dedup: warn if fields match a previous expense (different image).
    const softDuplicate = await expensesRepo.findSoftDuplicate(input.userId, {
      merchant: expense.merchant,
      date: expense.date,
      total: expense.total,
      currency: expense.currency,
    });

    return c.json({
      pendingId,
      expense,
      ...(softDuplicate ? { softDuplicate } : {}),
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await pendingRepo.setPendingStatus(pendingId, 'FAILED', msg);
    throw err;
  }
},
```

- [ ] **Step 3: Update the `/receipts/:id/confirm` handler to pass imageHash**

Replace the existing `/receipts/:id/confirm` handler body:

```ts
handler: async (c) => {
  const id = c.req.param('id');
  const pending = await pendingRepo.getPending(id);
  if (!pending || !pending.extracted) throw new HTTPException(404);
  if (pending.status === 'INSERTED') return c.json({ id });
  const imageHash = hashFileIfExists(pending.filePath);
  return c.json(
    await commitConfirmed({
      pendingId: id,
      userId: pending.userId,
      expense: pending.extracted,
      sourceFile: pending.filePath,
      imageHash,
    }),
  );
},
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/mastra.ts
git commit -m "feat(api): dedup receipt uploads via SHA-256 hash check"
```

---

## Task 5: Full test run

- [ ] **Step 1: Run all tests**

```bash
pnpm test
```

Expected: all suites pass.

- [ ] **Step 2: Run typecheck across workspace**

```bash
pnpm typecheck
```

Expected: no errors.
