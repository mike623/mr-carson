# Mr. Carson — Mobile (Flutter)

Offline-first receipt expense tracker. On-device Gemma 3n (via `flutter_gemma`)
does OCR + extraction + chat. Local DB via drift/SQLite. No backend, no account.

This is the Flutter sibling of `apps/api` + `apps/telegram-bot`. It is a Dart
app, **not** part of the pnpm/turbo JS workspace (excluded in
`pnpm-workspace.yaml`). It carries its own toolchain (`pubspec.yaml`).

## Layout

```
apps/mobile/
  pubspec.yaml
  lib/
    data/
      db/
        tables.dart          drift table defs (ported from schema.sql)
        app_database.dart     AppDatabase: queries ported from expenses.ts
        *.g.dart              generated (drift) — do not edit
      repositories/          (todo) thin wrappers if UI wants narrower APIs
    domain/
      models/
        ai_models.dart        ExpenseDraft / OcrResult / QueryExpensesArgs … (ported from shared-types)
        *.g.dart *.freezed.dart   generated (freezed/json) — do not edit
      date_range.dart         resolveDateRange (ported from util/dateRange.ts)
    ai/
      prompts.dart            kReceiptExtractionSystem / kChatSystemPersona (verbatim from apps/api)
      gemma_service.dart      GemmaService: download/load/dispose model + gemmaServiceProvider
      receipt_pipeline.dart   ReceiptPipelineService: vision call → ExpenseDraft, confirm-before-insert
      chat_service.dart       ChatService: streaming butler chat, manual tool-loop → queryExpenses
    data/
      providers.dart          appDatabaseProvider / pendingRepositoryProvider (shared riverpod)
    features/                 (todo) onboarding / home / capture / confirm / history / chat / insights / settings
    main.dart                 (todo) bootstrap: init gemma, open db, seedCategories, run app
```

## What's done (data layer, verified)

- **Schema** — `tables.dart`. Ported from `packages/database/src/schema.sql`.
  Dropped `user_id` / `chat_id` (single device). DECIMAL→REAL, DATE→TEXT
  `YYYY-MM-DD`, UUID→TEXT.
- **Queries** — `app_database.dart`. Faithful ports of `expenses.ts`:
  `insertExpense`, `findByImageHash`, `findSoftDuplicate`, `queryExpenses`
  (incl. the ORed `itemNames` synonym-expansion search), `byCategoryOverTime`,
  `topMerchants`, `seedCategories`.
- **Models** — `ai_models.dart`. Ported from `packages/shared-types`. These are
  the Gemma I/O boundary + tool args.

Verified: `flutter pub get`, `dart run build_runner build`, `flutter analyze` →
no issues.

## Adaptations to note (DuckDB → SQLite)

- `DATE_TRUNC` has no SQLite equivalent → `byCategoryOverTime` uses
  `substr`/`strftime` over the date text (week bucket = ISO `%Y-%W`).
- `ANY_VALUE` → `MAX(currency)`.
- Money kept as REAL to match the existing `CAST(... AS DOUBLE)` arithmetic.
  Switch to integer cents later if exact money is required.

## AI layer (done, verified)

Built + two-stage reviewed (spec compliance, then code quality), `flutter analyze lib/` clean.

- `ai/prompts.dart` — extraction + chat persona copied verbatim from `apps/api`.
- `ai/gemma_service.dart` — model lifecycle. Built against the REAL installed
  flutter_gemma v0.9.0 legacy API (not the newer docs API). Provider disposes the
  native handle; state exposed as read-only `ValueListenable`.
- `ai/receipt_pipeline.dart` + `data/repositories/pending_repository.dart` —
  merges old `ocr.ts` + `extractReceipt.ts` into ONE vision call. Enforces
  confirm-before-insert via the pending lifecycle (received → awaitingConfirmation
  → inserted/rejected/failed). Vision session closed on every path.
- `ai/chat_service.dart` — streaming butler Q&A. flutter_gemma v0.9.0 has NO native
  function-calling, so a manual `TOOL:`-prefix loop maps model JSON →
  `QueryExpensesArgs` → `AppDatabase.queryExpenses`/`topMerchants`. Both paths
  stream; single-tool-call guard; LLM never writes SQL.
- `data/providers.dart` — shared `appDatabaseProvider` / `pendingRepositoryProvider`.

`kDefaultModelUrl` in gemma_service.dart is a PLACEHOLDER — point it at the
self-hosted Gemma 3n `.litertlm` before any real build.

## Next (not built yet)

1. `ai/` — `chartSpending` tool (needs `fl_chart` render) — left as a TODO in chat_service.
2. `features/**` — onboarding (model download UX), home, capture, confirm, history, chat, insights, settings.
3. `main.dart` — bootstrap: `FlutterGemma.initialize`, open db, `seedCategories`, `ProviderScope`, run app.

## Codegen

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```
