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
- **Image input/storage:** add `image_picker` (camera + library). Copy the
  picked file into `<app documents>/receipts/<uuid>.jpg`, store that stable path
  in `pending_expenses.file_path` → `expenses.source_file`, plus a sha256
  `image_hash` for dedup. Picker temp paths are not persistent, so the copy is
  required. No image bytes in the DB.
- **Tool calling:** upgrade `flutter_gemma` `^0.9.0` → `^0.16.x` and replace the
  manual `TOOL:` text-protocol loop with **native function calling**
  (`Tool` defs + `FunctionCallResponse` + `Message.toolResponse`). Gemma3n (our
  model) is on the supported-for-function-calling list. Mastra has no Dart SDK
  and would require a server, so it is rejected for the on-device app.

## Data store (reference)

- **DB engine:** drift over SQLite (`sqlite3_flutter_libs`). Single file
  `mr_carson.sqlite` in `getApplicationDocumentsDirectory()`
  (`app_database.dart:364`). On-device, per-app, restart-safe.
- **Tables:** expenses, expense_items, categories, merchants, pending_expenses.
- **Images:** filesystem (`<docs>/receipts/`), referenced by path columns
  (`source_file`, `file_path`) + `image_hash`. No bytes in DB.

## Architecture

### 0. flutter_gemma upgrade + native function calling

- Bump `flutter_gemma` `^0.9.0` → `^0.16.x`. The modern API replaces the legacy
  `FlutterGemmaPlugin.instance` singleton (exact current API — model creation,
  vision session, install/download — to be confirmed against 0.16.x docs during
  implementation).
- Migrate the three AI files:
  - `gemma_service.dart` — model load + `createVisionSession` + `createChat` to
    the modern API; keep the `GemmaState` lifecycle.
  - `receipt_pipeline.dart` — vision session call sites.
  - `chat_service.dart` — **rewrite**: delete the manual `TOOL:` parser/loop and
    the outdated v0.9.0 header comment; define `Tool`s for `queryExpenses`,
    `topMerchants`, `chartSpending`; handle `FunctionCallResponse` by running the
    drift query and replying with `Message.toolResponse`. LLM still never writes
    SQL — it emits tool name + args; drift compiles the query.
- **Risk:** the build just shipped to TestFlight is on 0.9.0. This upgrade
  requires a full on-device re-test (vision OCR + chat + function calling on a
  real device, not just the simulator). Treat as its own implementation phase
  with a device smoke test before the UI wiring lands.

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

- **Image input:** add `image_picker`. `capturePhoto` (camera) and `startUpload`
  (gallery) obtain an `XFile`, then a new `ReceiptImageStore` copies it to
  `<app documents>/receipts/<uuid>.<ext>` and returns the stable path. That path
  (never the picker temp path) is what flows into `processReceipt`. The store
  also exposes the receipts dir for cleanup of rejected receipts.
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

- Native function calling (see §0): register `Tool`s for `queryExpenses`,
  `topMerchants`, and `chartSpending` on the chat; handle `FunctionCallResponse`
  → run the drift query → `Message.toolResponse` → model narrates the answer.
- `chartSpending` returns `byCategoryOverTime` buckets; attach structured chart
  data to the message and render a real `fl_chart` widget (bar/line over category
  buckets) in `ask_screen.dart` (replaces the fake `hasChart` bool).
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

- Bump `flutter_gemma` to `^0.16.x`; `flutter pub add image_picker crypto`
  (crypto for sha256 `image_hash`).
- iOS `Info.plist`: add `NSCameraUsageDescription` +
  `NSPhotoLibraryUsageDescription`. Android: image_picker needs no manifest
  perms for gallery; camera capture adds `<uses-feature camera>` as needed.
- `dart run build_runner build --delete-conflicting-outputs` after new drift
  `.watch()` methods and any new freezed/json models.

## Out of scope (YAGNI)

- Multi-device sync, cloud backup, auth.
- New visual redesign — reuse existing screen widgets and theme.
- Android-specific work beyond what already compiles.

## File touch list (estimate)

- New: `lib/data/repositories/expense_repository.dart`,
  `lib/data/receipt_image_store.dart` (copy picked image into `<docs>/receipts/`),
  `lib/ui/core/widgets/{loading,error_retry,empty}_state.dart`,
  chart widget under `lib/features/ask/`.
- Edit: `app_database.dart` (watch methods), `providers.dart`,
  `confirm_screen.dart`, `ledger_screen.dart`, `detail_screen.dart`,
  `shell_view_model.dart`, `ask_view_model.dart`, `ask_screen.dart`,
  `chat_service.dart`, `prompts.dart`, `onboarding_view_model.dart`,
  domain models, tests.
