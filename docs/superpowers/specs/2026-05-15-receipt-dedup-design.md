# Receipt Deduplication via SHA-256

**Date:** 2026-05-15  
**Status:** Approved

## Problem

Users occasionally upload the same receipt photo twice (fat-finger re-upload). The current pipeline runs OCR and extraction on every upload with no duplicate check, wasting Ollama compute and potentially inserting duplicate expense rows.

## Solution

Hash the image file on upload (SHA-256) and reject before OCR if an identical file has already been committed. A secondary soft-dedup check warns after extraction if structured fields match an existing expense.

## Architecture

Two checks in sequence, both scoped to the uploading user:

1. **Hard block** — SHA-256 match in `expenses.image_hash` → return 409 with the existing expense ID, no pending row created, no OCR
2. **Soft warn** — Same (merchant, date, total, currency) but different hash → after extraction, bot asks "Looks like a duplicate from [merchant] on [date]. Add anyway?"

## Schema Changes

```sql
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS image_hash TEXT;
CREATE INDEX IF NOT EXISTS idx_expenses_image_hash ON expenses (image_hash);
```

Added to `schema.sql` and the inlined `SCHEMA_SQL` constant in `schema.ts`.

No change to `pending_expenses` — hash check fires before a pending row exists.

## Data Flow

```
Telegram uploads file
  → API: hash file (SHA-256, ~1ms, Node crypto — no deps)
  → expensesRepo.findByImageHash(userId, hash)
      hit  → HTTP 409, return existing expense id (no OCR)
      miss → create pending row
  → processReceipt() unchanged
  → user confirms
  → commitConfirmed({ ..., imageHash }) → stores on expenses row
```

## Code Changes

| Location | Change |
|----------|--------|
| `packages/database/src/schema.sql` | Add `image_hash TEXT` column + index |
| `packages/database/src/schema.ts` | Sync inlined `SCHEMA_SQL` constant |
| `packages/database/src/repositories/expenses.ts` | Add `findByImageHash(userId, hash)`, add `image_hash` to `insertExpense` |
| `apps/api/src/pipeline.ts` | `commitConfirmed` opts gains `imageHash?: string` |
| `apps/api/src/main.ts` | Hash file in upload route before `pendingRepo.create`; pass hash through to `commitConfirmed` |
| `apps/api/src/tools/queryExpenses.ts` | Soft-dedup query: same user + fuzzy merchant + date + total |

## Hashing

Use Node's built-in `crypto.createHash('sha256')` on the file buffer — zero new dependencies.

```ts
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

function hashFile(filePath: string): string {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}
```

## Soft Dedup Query

After `processReceipt()` returns, before showing confirmation to user:

```sql
SELECT id, merchant, date, total
FROM expenses
WHERE user_id = ?
  AND date = ?
  AND total = ?
  AND currency = ?
  AND lower(merchant) = lower(?)
LIMIT 1;
```

If hit, bot prepends warning to confirmation message. User can still confirm.

## Out of Scope

- Perceptual hashing (pHash) — not needed for exact re-upload detection
- Cross-user dedup — expenses are user-scoped, no shared dedup
- Retroactive hashing of existing expenses — `image_hash` nullable, old rows simply won't match
