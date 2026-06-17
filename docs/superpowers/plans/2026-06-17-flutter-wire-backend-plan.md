# Plan: Wire Mr. Carson Flutter UI to its real backend

Executes the remaining phases of
`docs/superpowers/specs/2026-06-13-flutter-realistic-impl-design.md`.
Phase 0 (flutter_gemma 0.16.5 + native function calling + Gemma 4 E2B) and
Phase 5 (onboarding) are already DONE. This plan covers the UI→DB wiring that
is still mock: data layer, capture→confirm→persist, ledger+detail, ask charts,
and shared state widgets.

Target app: `apps/mobile/` (Flutter, drift + flutter_gemma + riverpod).

## Global Constraints (bind every task)

- **TDD.** Write a failing test first, then implement. Every task leaves tests
  that fail if the logic breaks.
- **No fake data ever enters the DB.** Mock/prototype seed data (The Wolseley,
  Caffè Nero, hardcoded donut segments) must be deleted, not persisted.
- **Real empty states.** When there are no expenses, show a real empty state —
  never seeded sample rows.
- **Reuse the existing Brass & Ink theme** (`lib/theme/app_theme.dart`:
  `MrCarsonColors`, `MrCarsonType`, `MrCarsonRadii`). No new visual redesign;
  match the current screen widgets' look exactly.
- **Architecture = Approach A:** `ExpenseRepository` + reactive riverpod
  providers over drift `.watch()` streams. Screens are dumb `ConsumerWidget`s;
  state via `AsyncValue`.
- **LLM never writes SQL.** Tools emit structured args; drift compiles queries.
- **Verification per task:** `flutter analyze lib test` → No issues found;
  `flutter test` → green. Run `dart run build_runner build
  --delete-conflicting-outputs` after any new drift `.watch()` / freezed / json
  model.
- Existing interfaces (do not rebuild): `AppDatabase` (`queryExpenses`,
  `topMerchants`, `byCategoryOverTime`, `insertExpense`, `findByImageHash`,
  `findSoftDuplicate`, `seedCategories`); `PendingRepository`
  (`create`, `setStatus`, `getById`, statuses via `PendingStatus`);
  `ReceiptPipeline` (`processReceipt`, `commitConfirmed`, `reject`);
  `ChatService` (native FC loop, tools `queryExpenses`/`topMerchants`/
  `chartSpending`); `model/` feature (model lifecycle, locked-state CTA,
  Model Management). `appDatabaseProvider` + `pendingRepositoryProvider` exist
  in `lib/data/providers.dart`.

---

## Task 1: Shared state widgets (Phase 6)

Add `lib/ui/core/widgets/loading_state.dart`, `error_retry_state.dart`,
`empty_state.dart` — small reusable widgets on the Brass & Ink theme:

- `LoadingState({String? message})` — centered brass spinner + optional caption.
  Reuse the existing brass spinner style from `lib/features/ask/ask_screen.dart`
  (the `_PreparingBanner`/spinner) if one is extractable; otherwise a
  `CircularProgressIndicator` tinted `MrCarsonColors.accent`.
- `ErrorRetryState({required String message, required VoidCallback onRetry})` —
  message + a "Try again" button (reuse the primary/outline button look).
- `EmptyState({required String title, String? body, IconData? icon})` —
  centered title (display font) + muted body, butler tone.

**Acceptance:** Three widgets, each rendering on the dark theme. Widget test per
widget: renders given text; `ErrorRetryState` invokes `onRetry` on tap.
No provider/data dependencies. ~1 file each.

**Files:** new `lib/ui/core/widgets/{loading_state,error_retry_state,empty_state}.dart`
+ `test/ui/core/widgets/*_test.dart`.

---

## Task 2: Data layer — ExpenseRepository + providers (Phase 1)

Add reactive reads over drift so screens stream live DB state.

1. **Domain models** under `lib/domain/models/` (freezed or plain immutable):
   - `ExpenseSummary` — id, merchant, category, total, currency, date (for the
     ledger recent list and detail header).
   - `MonthlySummary` — month, total, currency, `List<CategoryBucket>` (label,
     amount, color-key) for the donut.
   - `ExpenseDetail` — the expense + its line items (id, merchant, category,
     date, total, currency, source image path, `List<ExpenseItemRow>`).
2. **`AppDatabase` watch methods** (add `.watch()` variants — current reads are
   one-shot `.get()`): use `customSelect(...).watch()` /
   `.map(...).watch()`:
   - `Stream<List<ExpenseSummary>> watchRecentExpenses({int limit})`
   - `Stream<MonthlySummary> watchMonthlySummary(DateTime month)`
   - `Stream<ExpenseDetail?> watchExpenseById(String id)`
   - Keep the existing one-shot methods.
3. **`lib/data/repositories/expense_repository.dart`** wrapping `AppDatabase`:
   the three streams above + `Future<ChartData> categorySpending(
   QueryExpensesArgs args, {Granularity})` — thin pass-through to the existing
   `byCategoryOverTime`.
4. **Providers** in `lib/data/providers.dart`:
   - `expenseRepositoryProvider`
   - `recentExpensesProvider` — `StreamProvider`
   - `monthlySummaryProvider` — `StreamProvider` (current month)
   - `expenseDetailProvider` — `StreamProvider.family<ExpenseDetail?, String>`
   - `pendingReceiptsProvider` — `StreamProvider` watching `pending_expenses`
     rows in processing / awaitingConfirmation (add a `watchActive()` stream to
     `PendingRepository` if needed).

**Acceptance:** Repository tests over an in-memory drift DB
(`NativeDatabase.memory()`): insert an expense → `watchRecentExpenses` emits it;
insert two in different categories → `watchMonthlySummary` totals + buckets
correct; `watchExpenseById` emits expense + items; empty DB → empty/zero
emissions (no seeded data). Run build_runner.

**Files:** new `expense_repository.dart`, `lib/domain/models/{expense_summary,
monthly_summary,expense_detail}.dart`; edit `app_database.dart`,
`providers.dart`, `pending_repository.dart`; tests.

---

## Task 3: Capture → confirm → persist (Phase 2)

Make the receipt loop reach the DB for real.

1. **Deps:** `flutter pub add image_picker crypto`. iOS `Info.plist`: add
   `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` (butler-tone
   strings).
2. **`lib/data/receipt_image_store.dart`** — `ReceiptImageStore`: copy a picked
   `XFile` into `<app documents>/receipts/<uuid>.<ext>`, return the stable path;
   compute a sha256 `image_hash`; expose the receipts dir + a delete for
   rejected receipts. (Picker temp paths are not persistent — the copy is
   required. No image bytes in the DB.)
3. **`shell_view_model.dart`:** `capturePhoto` (camera) and `startUpload`
   (gallery) obtain an `XFile` via `image_picker`, copy via `ReceiptImageStore`,
   then run `receiptPipeline.processReceipt` for real. Delete the `_mockProcess`
   path and the in-memory pending list — drive pending off
   `pendingReceiptsProvider`. `saveConfirm` must call
   `receiptPipeline.commitConfirmed(pendingId, editedDraft)`; discard →
   `receiptPipeline.reject(pendingId)`.
4. **`confirm_screen.dart` → `ConsumerWidget` taking a `pendingId`:** load the
   real `ExpenseDraft` (from the pending row's `extractedJson` or the pipeline
   result), pre-fill **editable** merchant, category, line items, total. Delete
   the hardcoded `'Caffè Nero'`/`'Dining'`. Save → `commitConfirmed`; discard →
   `reject`.

**Acceptance:** Integration test (in-memory drift): given a stub
`ExpenseDraft`, `commitConfirmed` writes to `expenses` and
`recentExpensesProvider` then emits it; `reject` leaves the DB empty and the
pending row `rejected`. Confirm screen widget test: real draft renders, edited
total flows into the committed expense. image_picker calls are behind the store
so they can be faked in tests. `flutter analyze`/`flutter test` green.

**Files:** new `receipt_image_store.dart`; edit `shell_view_model.dart`,
`confirm_screen.dart`, `pubspec.yaml`, `ios/Runner/Info.plist`; tests.

---

## Task 4: Ledger + detail wired to providers (Phase 3)

1. **`ledger_screen.dart` → `ConsumerWidget`:** donut from
   `monthlySummaryProvider`; recent list from `recentExpensesProvider`; pending
   cards from `pendingReceiptsProvider`. Delete the hardcoded `_expenses` +
   `_segments`. Real `EmptyState` (Task 1) when no expenses. `AsyncValue.error`
   → `ErrorRetryState`; loading → `LoadingState`. A pending card "Review" routes
   to `ConfirmScreen(pendingId)`.
2. **`detail_screen.dart` → `ConsumerWidget`:** load via
   `expenseDetailProvider(id)`; render real merchant, date, line items, totals,
   and the source image if present. Delete the hardcoded "The Wolseley".

**Acceptance:** Widget tests pump under `ProviderScope` with overrides backed by
an in-memory drift DB (or stubbed stream providers): seeded expense → ledger
shows it + correct donut total; empty DB → empty state, no mock rows; detail
screen for an id renders its merchant + line items. analyze/test green.

**Files:** edit `ledger_screen.dart`, `detail_screen.dart`; tests.

---

## Task 5: Ask charts — real fl_chart from chartSpending (Phase 4)

chat_service already runs native function calling with a `chartSpending` tool
(DONE). Wire its output to a real chart in the UI.

1. **`ask_view_model.dart`:** replace the `hasChart` bool with real structured
   chart data attached to the assistant message when `chartSpending` was used
   (category buckets from `byCategoryOverTime`). Remove the canned `_replies` /
   `_mockReply`. When the model is not ready, surface an honest "AI unavailable"
   message — no fabricated answer (the locked/preparing states already exist in
   the model lifecycle).
2. **`ask_screen.dart`:** render a real `fl_chart` widget (bar or line over the
   category buckets) for a message carrying chart data — replacing the hardcoded
   mock chart (`_kChartRows`, ~lines 658–808). Keep the Brass & Ink styling and
   category color-keys.
3. Ensure `chartSpending` tool result shape and the message chart payload line
   up (define a small `ChartData`/bucket model if not already shared with
   Task 2's `categorySpending`).

**Acceptance:** A unit/widget test: an assistant message with chart buckets
renders an `fl_chart` chart (find the chart widget / N bars); a message without
chart data renders none; with the model unavailable, send() yields the honest
"AI unavailable" message, not a canned reply. analyze/test green.

**Files:** edit `ask_view_model.dart`, `ask_screen.dart`,
`chat_service.dart`/`prompts.dart` if the payload shape needs aligning; possibly
a small chart-data model; tests.

---

## Out of scope (YAGNI)

Multi-device sync, cloud backup, auth, new visual redesign, Android work beyond
what already compiles.
