# Cross-Device Expense Sync — Design

**Date:** 2026-06-22
**Status:** Approved (design), Phase 1 ready for planning
**App:** `apps/mobile` (Flutter, drift/SQLite, local-first, on-device Gemma)

## Problem

Two people share one expense ledger across iOS **and** Android. Both add
receipts and occasionally edit/delete the same expense. Data must stay private.
The app today is fully standalone: drift/SQLite on one device, no backend, no
auth.

## Constraints (from brainstorming)

- **Two different people**, one shared ledger → concurrent edits possible.
- **iOS + Android** → rules out CloudKit / iCloud-only sync.
- **Privacy preferred**, but the backend decision is **deferred**: sync is
  expected to become a **paid service**, so running a managed backend later is
  acceptable. "No-server / E2E" becomes a possible premium tier, not a Phase-1
  constraint.

## Core principle

Sync = **deterministic merge engine** + **pluggable transport**.

The merge engine is identical no matter which backend wins (Turso / PowerSync /
blind relay / shared folder). Build the engine now; hide the backend behind one
interface and choose it when productizing.

## Why not an off-the-shelf auto-sync DB

Every drop-in auto-sync DB (Turso, PowerSync, Firebase, Supabase, Ditto,
CouchDB) assumes a server/managed service. None delivers
*two-user + cross-platform + no-server + E2E* simultaneously. Since the backend
is deferred to a paid-service phase, we do **not** pick one now — we build
behind a transport interface so the choice stays open and testable.

The schema is already 90% sync-ready: **UUID primary keys** mean two devices
creating receipts concurrently never collide. Real conflict only occurs when
both edit/delete the *same* row — rare for an expense ledger — so **row-level
last-writer-wins is sufficient**; a full CRDT is overkill (YAGNI).

## Design

### 1. Sync columns (schema v3 migration)

Add to `expenses`, `expense_items`, `merchants`:

| Column | Type | Purpose |
|---|---|---|
| `updated_at` | TEXT | Hybrid Logical Clock stamp (sortable string) |
| `device_id` | TEXT | Origin device |
| `deleted_at` | TEXT NULL | Tombstone (soft delete) |
| `ledger_id` | TEXT | Which shared ledger (enables solo + shared ledgers; paid-tier ready) |

Migration backfills existing rows: `updated_at = hlc.now()`,
`device_id = this device`, `deleted_at = NULL`, `ledger_id = <default local ledger>`.

### 2. Hybrid Logical Clock (~40 lines)

`(wallMillis, counter, deviceId)` packed into a monotonic, sortable string.
Last stamp persisted in `shared_preferences`. Provides causal ordering and a
deterministic LWW tiebreak (`deviceId`) across two clocks that drift. Pure Dart,
unit-testable in isolation.

### 3. Soft delete (refactor existing `deleteExpense`)

`deleteExpense` stops doing a hard `DELETE` → sets `deleted_at = hlc.now()` on
the expense and its items. **Every read query gains `WHERE deleted_at IS NULL`.**
Required: a hard delete cannot propagate to the other device.

Affected reads (all in `app_database.dart`): `queryExpenses`,
`byCategoryOverTime`, `watchRecentExpenses`, `watchMonthlySummary`,
`watchExpenseById`, `topMerchants`, `findByImageHash`, `findSoftDuplicate`.

### 4. Change tracking — no op-log

Every write sets `updated_at = hlc.now()`. "Changed since last sync" =
`WHERE updated_at > :watermark`. Watermark stored per device. Simpler than an
op-log and sufficient for row-level sync.

### 5. Merge: `applyRemoteRows(rows)`

For each incoming row: upsert **iff** `remote.updated_at > local.updated_at`
(tombstones included — a remote delete wins the same way). Deterministic LWW, no
merge UI, no user-facing conflicts. Concurrent *new* receipts never conflict
(UUID PKs).

### 6. Receipt images (blobs)

Content-addressed by the existing `image_hash`. Row sync carries hashes; image
bytes fetched lazily and separately via `getBlob(hash)` so a multi-MB photo
never blocks ledger sync. Missing blobs render as a placeholder until fetched.

### 7. `SyncTransport` interface — the deferred seam

```dart
abstract class SyncTransport {
  Future<List<SyncRow>> pull(String ledgerId, String sinceWatermark);
  Future<void> push(String ledgerId, List<SyncRow> changes);
  Future<Uint8List?> getBlob(String hash);
  Future<void> putBlob(String hash, Uint8List bytes);
}
```

Concrete implementations (Turso / PowerSync / blind relay / shared folder) are
**deferred to Phase 2**. A `FakeTransport` (two in-process databases) ships in
Phase 1 so the full engine is testable with no network and no backend decision.

### 8. `SyncService` orchestration

On app foreground / pull-to-refresh / periodic timer:
`pull → applyRemoteRows → push(changed-since) → advance watermark`.
Exposed as a Riverpod provider; surfaces last-synced time and error state to the
UI.

## Phasing

### Phase 1 — backend-free, shippable now

1. HLC utility + tests.
2. Schema v3 migration (sync columns + backfill).
3. Soft-delete refactor across all reads + `deleteExpense`.
4. `updated_at` bump on every write; changed-since query.
5. `applyRemoteRows` LWW merge.
6. `SyncTransport` interface + `FakeTransport`.
7. Integration test: two `AppDatabase` instances sync over `FakeTransport`
   (concurrent insert, concurrent edit LWW, delete propagation, blob fetch).

Commits no money and no vendor. Fully testable.

### Phase 2 — paid-service decision

1. Pick concrete transport (Turso / PowerSync / blind relay).
2. Accounts + pairing (share a `ledger_id` + key).
3. Entitlement gate (sync = paid feature).
4. Real blob sync over the chosen backend.
5. UI sync status (last-synced, error, manual sync).
6. Optional E2E encryption as a premium tier.

## Deliberately skipped (YAGNI)

Field-level CRDT, op-log, real-time push, conflict-resolution UI, multi-ledger
UI. Add only if row-level LWW proves too coarse in practice.

## Testing strategy

Phase 1 is fully exercised by `FakeTransport` + two in-process `AppDatabase`
instances — no network, no backend. Key cases: concurrent inserts (no
collision), concurrent edit of one row (HLC LWW winner is deterministic), delete
propagation via tombstone, watermark advancement, lazy blob fetch.
