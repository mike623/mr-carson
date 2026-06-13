# Mr. Carson Flutter — Realistic Implementation Design

**Date:** 2026-06-13
**Status:** Approved (design); pending spec review
**Scope:** Wire the Flutter app's UI to its real backend so the full
capture → confirm → persist → ledger → detail → ask/chart loop works for real.

## Problem

The backend is real and solid, but the UI/view-model layer is still the
prototype: hardcoded data, in-memory state, mock ramps, and canned replies.
Nothing the user does in the UI reaches the database.

### What is already real (do not rebuild)

- `lib/data/db/app_database.dart` — drift DB. Genuine queries: `queryExpenses`,
  `topMerchants`, `byCategoryOverTime`, `insertExpense`, `findByImageHash`,
  `findSoftDuplicate`, `seedCategories`. Tables: Expenses, ExpenseItems,
  Categories, Merchants, PendingExpenses.
- `lib/ai/gemma_service.dart` — flutter_gemma lifecycle (download/load/vision/chat).
- `lib/ai/receipt_pipeline.dart` — `processReceipt`, `commitConfirmed`, `reject`.
- `lib/ai/chat_service.dart` — manual single-step tool loop (`queryExpenses`,
  `topMerchants`).
- `lib/data/repositories/pending_repository.dart` — pending lifecycle CRUD.
- `fl_chart` and `flutter_riverpod` already in `pubspec.yaml`.

### What is fake (the work)

| # | Location | Problem |
|---|----------|---------|
| 1 | `shell_view_model.dart:202` `saveConfirm` | Drops card from in-memory list; never calls `commitConfirmed`. Nothing persists. |
| 2 | `confirm_screen.dart:30` | Hardcoded `'Caffè Nero'`/`'Dining'`; ignores the real `ExpenseDraft`; no edit→save path. |
| 3 | `ledger_screen.dart:44` | "No providers, no services" — donut + recent expenses hardcoded. |
| 4 | `detail_screen.dart` | Same self-contained mock pattern; not loading a real expense. |
| 5 | `ask_view_model.dart:88` `_replies` | Canned butler replies; `hasChart` is a bool with no real chart. |
| 6 | `chat_service.dart:302` | `chartSpending` tool missing from the loop (DB `byCategoryOverTime` exists). |
| 7 | `shell_view_model.dart` pending list | In-memory; lost on restart. PendingRepository unused by UI. |
| 8 | `onboarding_view_model.dart:138` `_startMockRamp` | Mock download ramp + stale `example.com` check. |

## Decisions (locked)

- **Scope:** full end-to-end loop.
- **Fallbacks:** removed. Real, honest error states (model loading / extraction
  failed + retry / AI unavailable). No fake data ever enters the DB.
- **Empty state:** real empty states; no seeded sample data.
- **Architecture:** Approach A — `ExpenseRepository` + reactive Riverpod
  providers over drift `.watch()` streams.

## Architecture

### 1. Data layer

Add `lib/data/repositories/expense_repository.dart` wrapping `AppDatabase`:

- `Stream<List<ExpenseSummary>> watchRecentExpenses({int limit})`
- `Stream<MonthlySummary> watchMonthlySummary(DateTime month)` — total + by-category
  breakdown for the donut.
- `Stream<ExpenseDetail?> watchExpenseById(String id)` — expense + its line items.
- `Future<ChartData> categorySpending(QueryExpensesArgs args, {Granularity})` —
  thin pass-through to `byCategoryOverTime` for the chart tool.

Add drift `.watch()` variants in `AppDatabase` where needed (e.g.
`customSelect(...).watch()`), since current reads are one-shot `.get()`.

New providers in `lib/data/providers.dart`:

- `expenseRepositoryProvider`
- `recentExpensesProvider` — `StreamProvider`
- `monthlySummaryProvider` — `StreamProvider`
- `expenseDetailProvider` — `StreamProvider.family(String id)`
- `pendingReceiptsProvider` — `StreamProvider` watching `pending_expenses`
  (status in processing / awaitingConfirmation)

Domain models as needed: `ExpenseSummary`, `MonthlySummary`, `ExpenseDetail`
(in `lib/domain/models/`).

### 2. Capture → confirm → persist

- `ConfirmScreen` → `ConsumerWidget` taking a `pendingId`. Loads the real
  `ExpenseDraft` (from the pending row's `extractedJson` or the in-memory
  pipeline result), pre-fills **editable** merchant, category, line items, total.
- Save → `receiptPipeline.commitConfirmed(pendingId, editedDraft)` → `expenses`.
- Discard → `receiptPipeline.reject(pendingId)`.
- `shell_view_model`: `startUpload`/`capturePhoto` run `processReceipt` for real;
  the pending list is driven by `pendingReceiptsProvider`; the mock
  `_mockProcess` and `saveConfirm` mock removal are deleted.

### 3. Ledger + detail

- `LedgerScreen` → `ConsumerWidget`: donut from `monthlySummaryProvider`,
  recent list from `recentExpensesProvider`, pending cards from
  `pendingReceiptsProvider`. Real empty state when no expenses.
- `DetailScreen` → loads via `expenseDetailProvider(id)`; renders real merchant,
  date, line items, totals, source image if present.

### 4. Ask + charts

- Add `chartSpending` case to `chat_service.dart` `_runTool`, returning the
  `byCategoryOverTime` buckets as JSON; teach the tool protocol preamble about it.
- Replace `ask_view_model` `hasChart` bool with structured chart data attached to
  the message; render a real `fl_chart` widget (bar/line over category buckets)
  in `ask_screen.dart`.
- Remove `_replies`/`_mockReply`. When model not ready, surface an honest
  "AI unavailable" message (no fabricated answer).

### 5. Onboarding

- Remove `_startMockRamp` and the stale `example.com` check. Drive progress only
  from `GemmaService.downloadModel`. On error → real error UI with retry.

### 6. Error / empty states

- Shared widgets in `lib/ui/core/widgets/`: `LoadingState`, `ErrorRetryState`,
  `EmptyState`. Used by ledger, detail, ask.

## Data flow

```
Camera/library → ShellViewModel.startUpload(path)
  → ReceiptPipelineService.processReceipt → pending_expenses(awaitingConfirmation)
  → pendingReceiptsProvider (stream) → ledger pending card "Review"
  → ConfirmScreen(pendingId) edits draft → commitConfirmed → expenses table
  → recentExpensesProvider / monthlySummaryProvider streams update
  → LedgerScreen + DetailScreen reflect it live
Ask: user msg → ChatService.send → (tool: queryExpenses/topMerchants/chartSpending)
  → DB → streamed butler answer (+ fl_chart when chartSpending used)
```

## Error handling

- Pipeline failures already captured as `ReceiptResult.failure` + pending row
  `failed`. UI shows the failed card with a retry/dismiss action.
- Model-not-ready: confirm/ask/ledger show honest states; no mock substitution.
- DB/stream errors surface via `AsyncValue.error` → `ErrorRetryState`.

## Testing

- Update existing widget tests (`confirm_screen_test`, `ledger_screen_test`,
  `onboarding_screen_test`) to pump under `ProviderScope` with overrides backed
  by an in-memory drift DB (`NativeDatabase.memory()`).
- Add `ExpenseRepository` tests for the watch queries (insert → stream emits).
- Add one integration test: process (stub draft) → commitConfirmed → ledger
  stream shows the expense; monthly summary updates.
- `flutter analyze` clean; `flutter test` green.

## Build / codegen

- `dart run build_runner build --delete-conflicting-outputs` after new drift
  `.watch()` methods and any new freezed/json models.

## Out of scope (YAGNI)

- Multi-device sync, cloud backup, auth.
- New visual redesign — reuse existing screen widgets and theme.
- Android-specific work beyond what already compiles.

## File touch list (estimate)

- New: `lib/data/repositories/expense_repository.dart`,
  `lib/ui/core/widgets/{loading,error_retry,empty}_state.dart`,
  chart widget under `lib/features/ask/`.
- Edit: `app_database.dart` (watch methods), `providers.dart`,
  `confirm_screen.dart`, `ledger_screen.dart`, `detail_screen.dart`,
  `shell_view_model.dart`, `ask_view_model.dart`, `ask_screen.dart`,
  `chat_service.dart`, `prompts.dart`, `onboarding_view_model.dart`,
  domain models, tests.
