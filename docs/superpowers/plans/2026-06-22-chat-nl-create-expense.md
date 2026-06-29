# Natural-Language Expense Creation in Chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user record an expense by typing it in plain language on the chat (Ask) screen; Carson files it directly when confident, otherwise opens the existing Confirm screen prefilled.

**Architecture:** Add one native function-calling tool `addExpense` to the chat agent. Its handler builds an `ExpenseDraft` with tolerant coercion, then routes by field completeness: `merchant non-empty && total > 0` → `AppDatabase.insertExpense` directly; otherwise write an `awaitingConfirmation` pending row and emit a new `DraftReady(pendingId)` stream event that `AskViewModel` turns into a navigation to the Confirm screen. Reuses the entire existing `ExpenseDraft` / pending / `commitConfirmed` write path; no new screens.

**Tech Stack:** Flutter, Riverpod, drift (SQLite), flutter_gemma native function calling, freezed models, vitest-style `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-22-chat-nl-create-expense-design.md`.
- Routing rule (verbatim): `merchant non-empty AND total > 0 → insert directly; otherwise → open Confirm screen prefilled`.
- Confidence is **deterministic field completeness** — never a model-reported flag.
- The LLM never writes SQL; it produces structured tool args only.
- Categories must come from `kDefaultCategories` (`domain/models/ai_models.dart`); unknown → `'Other'`.
- Default currency is `kDefaultCurrency` (`'GBP'`) when the model omits it — matches the receipt pipeline (do **not** wire `currencyProvider`; out of scope).
- Tool handlers never throw — failures return an `{'error': …}` map (existing convention in `chat_service.dart`).
- All commands run from `apps/mobile/`. Test runner: `flutter test`. Analyzer must stay clean: `flutter analyze`.
- Commit after every task.

---

### Task 1: Optional `filePath` on `PendingRepository.create`

The chat path creates a pending row with no receipt image. The DB column is already a nullable `Value`; only the Dart signature needs relaxing.

**Files:**
- Modify: `apps/mobile/lib/data/repositories/pending_repository.dart:28-38`
- Test: `apps/mobile/test/data/pending_repository_create_test.dart` (create)

**Interfaces:**
- Produces: `Future<String> PendingRepository.create({String? filePath})` — returns the new row's UUID; row status is `PendingStatus.received`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/data/pending_repository_create_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  test('create with no filePath inserts a received row with null filePath', () async {
    final db = AppDatabase(); // in-memory (no executor)
    addTearDown(db.close);
    final repo = PendingRepository(db);

    final id = await repo.create();

    final row = await repo.getById(id);
    expect(row, isNotNull);
    expect(row!.status, PendingStatus.received.name);
    expect(row.filePath, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/pending_repository_create_test.dart`
Expected: FAIL — `create` requires the named arg `filePath` (compile error).

- [ ] **Step 3: Make `filePath` optional**

In `pending_repository.dart`, change the signature and use `Value.absentIfNull` so an omitted path is left to the column default (null):

```dart
  /// Inserts a new pending receipt row with status [PendingStatus.received].
  ///
  /// [filePath] is optional — chat-created drafts have no receipt image.
  /// Returns the generated UUID for the new row.
  Future<String> create({String? filePath}) async {
    final id = _uuid.v4();
    await _db.into(_db.pendingExpenses).insert(
          PendingExpensesCompanion.insert(
            id: id,
            status: PendingStatus.received.name,
            filePath: Value.absentIfNull(filePath),
          ),
        );
    return id;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/pending_repository_create_test.dart`
Expected: PASS. Then `flutter analyze` — clean (existing caller `create(filePath: imagePath)` still compiles).

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/pending_repository.dart test/data/pending_repository_create_test.dart
git commit -m "feat(mobile): allow PendingRepository.create with no filePath"
```

---

### Task 2: `buildExpenseDraftJson` — tolerant arg coercion

A pure static helper that turns loose `addExpense` tool args into an `ExpenseDraft`-shaped JSON map. Pure function → fully unit-testable with no DB or model.

**Files:**
- Modify: `apps/mobile/lib/ai/chat_service.dart` (add a static method + private coercion helpers to the `ChatService` class)
- Test: `apps/mobile/test/ai/add_expense_coercion_test.dart` (create)

**Interfaces:**
- Produces: `@visibleForTesting static Map<String, dynamic> ChatService.buildExpenseDraftJson(Map<String, dynamic> args, String today)` — returns a map with keys `merchant, date, currency, total, vat, items, categories` that `ExpenseDraft.fromJson` accepts. `today` is `'YYYY-MM-DD'`.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/ai/add_expense_coercion_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  const today = '2026-06-22';

  Map<String, dynamic> build(Map<String, dynamic> args) =>
      ChatService.buildExpenseDraftJson(args, today);

  test('full args round-trip into a valid ExpenseDraft', () {
    final d = ExpenseDraft.fromJson(build({
      'merchant': 'Wagamama',
      'total': 12.0,
      'category': 'Dining',
      'date': '2026-06-20',
      'currency': 'gbp',
    }));
    expect(d.merchant, 'Wagamama');
    expect(d.total, 12.0);
    expect(d.currency, 'GBP'); // uppercased
    expect(d.date, '2026-06-20');
    expect(d.categories, ['Dining']);
  });

  test('date "today" / "yesterday" resolve relative to the passed today', () {
    expect(build({'date': 'today'})['date'], '2026-06-22');
    expect(build({'date': 'yesterday'})['date'], '2026-06-21');
  });

  test('missing date defaults to today', () {
    expect(build({'merchant': 'X'})['date'], '2026-06-22');
  });

  test('unknown category falls back to Other', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X', 'category': 'Spaceship'}));
    expect(d.categories, ['Other']);
    expect(d.items.single.category, 'Other');
  });

  test('missing currency defaults to kDefaultCurrency', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X'}));
    expect(d.currency, kDefaultCurrency);
  });

  test('no items: synthesizes one item equal to the total', () {
    final d = ExpenseDraft.fromJson(build({
      'merchant': 'Tesco',
      'total': 9.5,
      'category': 'Groceries',
    }));
    expect(d.items, hasLength(1));
    expect(d.items.single.name, 'Tesco');
    expect(d.items.single.amount, 9.5);
    expect(d.items.single.category, 'Groceries');
  });

  test('empty merchant + zero total still produce a parseable draft', () {
    final d = ExpenseDraft.fromJson(build({}));
    expect(d.merchant, '');
    expect(d.total, 0);
    expect(d.items.single.name, 'Expense'); // fallback name when no merchant
  });

  test('loose total string is parsed', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X', 'total': '12.30'}));
    expect(d.total, 12.30);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/add_expense_coercion_test.dart`
Expected: FAIL — `buildExpenseDraftJson` is not defined.

- [ ] **Step 3: Implement the static helper + coercion privates**

In `chat_service.dart`, inside the `ChatService` class, add `import 'package:flutter/foundation.dart' show visibleForTesting;` at the top of the file (alongside existing imports) and add these members (place them near the other arg-coercion helpers):

```dart
  /// Builds an [ExpenseDraft]-shaped JSON map from loose `addExpense` tool
  /// [args]. [today] is 'YYYY-MM-DD'. Tolerant of missing/loose fields so the
  /// draft is always parseable; completeness is judged by the caller, not here.
  @visibleForTesting
  static Map<String, dynamic> buildExpenseDraftJson(
    Map<String, dynamic> args,
    String today,
  ) {
    final merchant = _addStr(args['merchant']);
    final total = _addNum(args['total']);
    final category = _addCategory(args['category']);
    final currency = _addCurrency(args['currency']);
    final date = _addDate(args['date'], today);

    final rawItems = args['items'];
    final List<Map<String, dynamic>> items = (rawItems is List && rawItems.isNotEmpty)
        ? rawItems.whereType<Map>().map((it) {
            return <String, dynamic>{
              'name': _addStr(it['name']).isEmpty ? 'Item' : _addStr(it['name']),
              'amount': _addNum(it['amount']),
              'category': _addCategory(it['category'] ?? category),
            };
          }).toList()
        : [
            {
              'name': merchant.isEmpty ? 'Expense' : merchant,
              'amount': total,
              'category': category,
            },
          ];

    return {
      'merchant': merchant,
      'date': date,
      'currency': currency,
      'total': total,
      'vat': 0,
      'items': items,
      'categories': [category],
    };
  }

  static String _addStr(Object? v) =>
      (v is String) ? v.trim() : (v == null ? '' : v.toString().trim());

  static double _addNum(Object? v) {
    if (v is num) return v.toDouble();
    final cleaned = '${v ?? ''}'.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// Returns a category from [kDefaultCategories] (case-insensitive match),
  /// else 'Other'.
  static String _addCategory(Object? v) {
    final raw = _addStr(v);
    for (final c in kDefaultCategories) {
      if (c.toLowerCase() == raw.toLowerCase()) return c;
    }
    return 'Other';
  }

  static String _addCurrency(Object? v) {
    final cur = _addStr(v).toUpperCase();
    return cur.length == 3 ? cur : kDefaultCurrency;
  }

  /// Maps 'today' / 'yesterday' / a 'YYYY-MM-DD' string to an ISO date,
  /// defaulting to [today] for anything else.
  static String _addDate(Object? v, String today) {
    final raw = _addStr(v).toLowerCase();
    if (raw.isEmpty || raw == 'today') return today;
    if (raw == 'yesterday') {
      final t = DateTime.parse(today).subtract(const Duration(days: 1));
      final y = t.year.toString().padLeft(4, '0');
      final m = t.month.toString().padLeft(2, '0');
      final d = t.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    return today;
  }
```

Note: `kDefaultCategories` and `kDefaultCurrency` are already imported via `'../domain/models/ai_models.dart'`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ai/add_expense_coercion_test.dart`
Expected: PASS (all 7). Then `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ai/chat_service.dart test/ai/add_expense_coercion_test.dart
git commit -m "feat(mobile): tolerant arg coercion for addExpense drafts"
```

---

### Task 3: `DraftReady` event + `PendingRepository` dependency on `ChatService`

Wire the new dependency and the new stream event. No `addExpense` behavior yet — this task just makes everything compile with the new constructor and the event type, and fixes the existing fake.

**Files:**
- Modify: `apps/mobile/lib/ai/chat_service.dart` (add `DraftReady`; add `_pending` field + constructor arg; extend `_ToolOutcome`; update `chatServiceProvider`)
- Modify: `apps/mobile/test/features/ask/ask_view_model_test.dart:27-47` (fix `_FakeChatService` super call)
- Test: reuse `apps/mobile/test/features/ask/ask_view_model_test.dart` (must still pass)

**Interfaces:**
- Produces: `class DraftReady extends ChatEvent { const DraftReady(this.pendingId); final String pendingId; }`
- Produces: `ChatService(GemmaService gemma, AppDatabase db, PendingRepository pending)` — three positional args.
- Produces: extended `_ToolOutcome(Map<String,dynamic> response, {ChartData? chart, String? draftPendingId})`.
- Consumes (Task 1): `PendingRepository.create({String? filePath})`.

- [ ] **Step 1: Add the `DraftReady` event**

In `chat_service.dart`, after the `ChartReady` class (around line 57), add:

```dart
/// A draft the model produced via `addExpense` that needs the user's review
/// (low-confidence extraction). Carries the id of the `awaitingConfirmation`
/// pending row so the UI can open the Confirm screen prefilled.
class DraftReady extends ChatEvent {
  const DraftReady(this.pendingId);

  final String pendingId;
}
```

- [ ] **Step 2: Extend `_ToolOutcome` and add the `PendingRepository` dependency**

Extend `_ToolOutcome` (around line 81) to optionally carry a draft pending id:

```dart
class _ToolOutcome {
  const _ToolOutcome(this.response, {this.chart, this.draftPendingId});

  final Map<String, dynamic> response;
  final ChartData? chart;

  /// Set only by `addExpense` on the low-confidence branch — the id of the
  /// pending row the UI should open for review.
  final String? draftPendingId;
}
```

Add the import near the top: `import '../data/repositories/pending_repository.dart';`

Change the constructor and fields (around lines 124-129):

```dart
  /// Creates a chat service over [gemma] (inference), [db] (expense reads/
  /// writes) and [pending] (draft confirmation rows for low-confidence adds).
  ChatService(this._gemma, this._db, this._pending);

  final GemmaService _gemma;
  final AppDatabase _db;
  final PendingRepository _pending;

  InferenceChat? _chat;
```

Update the provider (around line 758):

```dart
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(
    ref.watch(gemmaServiceProvider),
    ref.watch(appDatabaseProvider),
    ref.watch(pendingRepositoryProvider),
  );
});
```

`pendingRepositoryProvider` is exported from `'../data/providers.dart'`, which is already imported (it currently pulls `appDatabaseProvider` with `show appDatabaseProvider`). Update that import line to also show the new provider:

```dart
import '../data/providers.dart' show appDatabaseProvider, pendingRepositoryProvider;
```

- [ ] **Step 3: Fix the existing fake so the suite compiles**

In `test/features/ask/ask_view_model_test.dart`, the `_FakeChatService` super call (line ~29) now needs a third arg. Add the import and update the constructor:

```dart
import 'package:mr_carson/data/repositories/pending_repository.dart';
```

```dart
class _FakeChatService extends ChatService {
  _FakeChatService(this._events)
      : super(_NullGemmaService(), AppDatabase(), PendingRepository(AppDatabase()));
```

- [ ] **Step 4: Run the affected suites to verify they pass**

Run: `flutter test test/features/ask/ask_view_model_test.dart test/ai/chat_service_envelope_test.dart`
Expected: PASS (no behavior changed; only the constructor signature). Then `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/ai/chat_service.dart test/features/ask/ask_view_model_test.dart
git commit -m "feat(mobile): add DraftReady event and PendingRepository dep to ChatService"
```

---

### Task 4: `addExpense` tool — registration, schema, routing

Register the tool, declare its schema, and implement the `_runTool` case using `buildExpenseDraftJson` (Task 2) and the completeness rule. Expose a `@visibleForTesting` `runToolDebug` so the routing is testable without a live `InferenceChat`.

**Files:**
- Modify: `apps/mobile/lib/ai/chat_service.dart` (`_tools` list; `_runTool` switch; new `_addExpenseSchema`; `runToolDebug`)
- Test: `apps/mobile/test/ai/add_expense_tool_test.dart` (create)

**Interfaces:**
- Consumes (Task 2): `ChatService.buildExpenseDraftJson(args, today)`.
- Consumes (Task 1): `PendingRepository.create()`, `PendingRepository.setStatus(id, PendingStatus.awaitingConfirmation, extractedJson: …)`.
- Consumes (Task 3): `_ToolOutcome(..., draftPendingId: …)`.
- Produces: `@visibleForTesting Future<({Map<String, dynamic> response, ChartData? chart, String? draftPendingId})> runToolDebug(String name, Map<String, dynamic> args)`.
- Produces tool result shapes: confident → `{'_tool':'addExpense','saved':true,'merchant':…,'total':…,'currency':…,'category':…}`; low → `{'_tool':'addExpense','needsReview':true}` plus `draftPendingId`.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/ai/add_expense_tool_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

class _NullGemma extends GemmaService {
  @override
  GemmaState get state => GemmaState.ready;
}

void main() {
  late AppDatabase db;
  late PendingRepository pending;
  late ChatService chat;

  setUp(() {
    db = AppDatabase(); // in-memory
    pending = PendingRepository(db);
    chat = ChatService(_NullGemma(), db, pending);
  });
  tearDown(() => db.close());

  test('confident add (merchant + total) inserts an expense directly', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': 'Wagamama',
      'total': 12.0,
      'category': 'Dining',
      'date': 'yesterday',
    });

    expect(out.response['saved'], isTrue);
    expect(out.draftPendingId, isNull);

    // The expense is now queryable.
    final result = await db.queryExpenses(const QueryExpensesArgs());
    expect(result.count, 1);
    expect(result.rows.single.merchant, 'Wagamama');
  });

  test('low-confidence add (no total) writes an awaitingConfirmation pending row', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': 'Wagamama',
      // no total
    });

    expect(out.response['needsReview'], isTrue);
    expect(out.draftPendingId, isNotNull);

    // No expense was inserted.
    final result = await db.queryExpenses(const QueryExpensesArgs());
    expect(result.count, 0);

    // The pending row exists, awaiting confirmation, with the draft JSON.
    final row = await pending.getById(out.draftPendingId!);
    expect(row, isNotNull);
    expect(row!.status, PendingStatus.awaitingConfirmation.name);
    expect(row.filePath, isNull);
    expect(row.extractedJson, contains('Wagamama'));
  });

  test('low-confidence add (empty merchant) routes to review even with a total', () async {
    final out = await chat.runToolDebug('addExpense', {
      'merchant': '',
      'total': 5.0,
    });
    expect(out.response['needsReview'], isTrue);
    expect(out.draftPendingId, isNotNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ai/add_expense_tool_test.dart`
Expected: FAIL — `runToolDebug` is not defined / `addExpense` is an unknown tool.

- [ ] **Step 3: Register the tool and its schema**

In `chat_service.dart`, add a fourth entry to the `_tools` list (after `chartSpending`):

```dart
    Tool(
      name: 'addExpense',
      description:
          "Record a NEW expense the user states in plain language (e.g. \"I "
          "spent £12 on lunch at Wagamama yesterday\", \"add £4 coffee\", "
          "\"log groceries 30 quid at Tesco\"). Provide merchant, total, and a "
          'category from the allowed list. Never invent an amount.',
      parameters: _addExpenseSchema(),
    ),
```

Add the schema builder next to the other `_*Schema()` methods:

```dart
  Map<String, dynamic> _addExpenseSchema() => {
        'type': 'object',
        'properties': {
          'merchant': {
            'type': 'string',
            'description': 'Store / vendor name, e.g. "Wagamama".',
          },
          'total': {
            'type': 'number',
            'description': 'Total amount paid.',
          },
          'category': {
            'type': 'string',
            'description': 'Expense category.',
            'enum': kDefaultCategories,
          },
          'date': {
            'type': 'string',
            'description': 'today, yesterday, or YYYY-MM-DD. Defaults to today.',
          },
          'currency': {
            'type': 'string',
            'description': '3-letter ISO code. Defaults to the user default.',
          },
        },
        'required': <String>['merchant', 'total'],
      };
```

- [ ] **Step 4: Implement the `_runTool` case + `runToolDebug`**

Add a case to the `switch (name)` in `_runTool` (before `default:`):

```dart
        case 'addExpense':
          return _runAddExpense(args);
```

Add the handler method and the test seam to the class:

```dart
  /// Builds a draft from [args], then routes by completeness: a confident
  /// extraction (merchant present AND total > 0) is inserted directly; an
  /// incomplete one is parked as an `awaitingConfirmation` pending row for the
  /// user to finish on the Confirm screen.
  Future<_ToolOutcome> _runAddExpense(Map<String, dynamic> args) async {
    final draftJson = buildExpenseDraftJson(_coerceArgsMap(args), _todayIso());
    final draft = ExpenseDraft.fromJson(draftJson);

    final confident = draft.merchant.trim().isNotEmpty && draft.total > 0;
    if (confident) {
      await _db.insertExpense(draft);
      return _ToolOutcome({
        '_tool': 'addExpense',
        'saved': true,
        'merchant': draft.merchant,
        'total': draft.total,
        'currency': draft.currency,
        'category': draft.categories?.first ?? 'Other',
      });
    }

    final pendingId = await _pending.create();
    await _pending.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: jsonEncode(draft.toJson()),
    );
    return _ToolOutcome(
      {'_tool': 'addExpense', 'needsReview': true},
      draftPendingId: pendingId,
    );
  }

  /// Today's date as 'YYYY-MM-DD'.
  String _todayIso() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Test seam: runs a tool by name and exposes the outcome (response map,
  /// optional chart, optional draft pending id) without needing a live chat
  /// session. Not used in production.
  @visibleForTesting
  Future<({Map<String, dynamic> response, ChartData? chart, String? draftPendingId})>
      runToolDebug(String name, Map<String, dynamic> args) async {
    final o = await _runTool(name, args);
    return (response: o.response, chart: o.chart, draftPendingId: o.draftPendingId);
  }
```

`jsonEncode` is already imported (`dart:convert` at the top of the file). `_coerceArgsMap` already exists.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/ai/add_expense_tool_test.dart`
Expected: PASS (all 3). Then `flutter analyze` — clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ai/chat_service.dart test/ai/add_expense_tool_test.dart
git commit -m "feat(mobile): addExpense chat tool with completeness-based routing"
```

---

### Task 5: Emit `DraftReady` from the agent loop

The `send` loop already surfaces `ChartReady` from a tool outcome; do the same for a draft pending id.

**Files:**
- Modify: `apps/mobile/lib/ai/chat_service.dart` (the `for (final call in pendingCalls)` block in `send`, around lines 257-266)
- Test: covered by Task 4's outcome tests (the emission is a one-line forward of `_runAddExpense`'s already-tested `draftPendingId`).

**Interfaces:**
- Consumes (Task 3/4): `_ToolOutcome.draftPendingId`, `DraftReady`.

- [ ] **Step 1: Forward the draft pending id as a `DraftReady` event**

In `send`, extend the post-tool emission block so it mirrors the chart branch:

```dart
      for (final call in pendingCalls) {
        yield ToolCallStarted(call.name, call.args);
        final outcome = await _runTool(call.name, call.args);
        await chat.addQueryChunk(
          Message.toolResponse(toolName: call.name, response: outcome.response),
        );
        if (outcome.chart != null) {
          yield ChartReady(outcome.chart!);
        }
        if (outcome.draftPendingId != null) {
          yield DraftReady(outcome.draftPendingId!);
        }
      }
```

- [ ] **Step 2: Run the chat suites to verify nothing regressed**

Run: `flutter test test/ai/`
Expected: PASS. Then `flutter analyze` — clean.

- [ ] **Step 3: Commit**

```bash
git add lib/ai/chat_service.dart
git commit -m "feat(mobile): emit DraftReady from the chat agent loop"
```

---

### Task 6: `AskViewModel` opens the Confirm screen on `DraftReady`

**Files:**
- Modify: `apps/mobile/lib/features/ask/ask_view_model.dart` (import shell VM; handle `DraftReady` in the `send().listen` switch, around lines 200-219)
- Test: `apps/mobile/test/features/ask/ask_view_model_test.dart` (add a group)

**Interfaces:**
- Consumes (Task 3): `DraftReady(pendingId)`.
- Consumes (existing): `ShellViewModel.reviewPending(String id)` sets `screen = ShellScreen.confirm`, `reviewingId = id`.

- [ ] **Step 1: Write the failing test**

Add to `test/features/ask/ask_view_model_test.dart` (the file already imports the needed pieces after Task 3; add the shell import at the top if missing):

```dart
import 'package:mr_carson/features/shell/shell_view_model.dart';
```

Add this group inside `main()`:

```dart
  group('DraftReady navigation', () {
    test('a DraftReady event opens the Confirm screen for that pending id', () async {
      final container = makeContainerWithChat([
        const DraftReady('pending-123'),
      ]);
      // Observe the shell so its notifier is alive.
      container.listen(shellViewModelProvider, (_, __) {}, fireImmediately: true);

      final vm = container.read(askViewModelProvider.notifier);
      vm.send('add lunch');

      await pumpUntil(
        container,
        (_) => container.read(shellViewModelProvider).screen == ShellScreen.confirm,
      );

      final shell = container.read(shellViewModelProvider);
      expect(shell.screen, ShellScreen.confirm);
      expect(shell.reviewingId, 'pending-123');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/ask/ask_view_model_test.dart -p vm`
Expected: FAIL — shell screen stays `ask` (the event is unhandled).

- [ ] **Step 3: Handle `DraftReady` in the VM**

In `ask_view_model.dart`, add the import:

```dart
import '../shell/shell_view_model.dart';
```

Add a case to the `switch (event)` in `_realReply`'s listener (alongside `ChartReady`):

```dart
            case DraftReady(:final pendingId):
              ref.read(shellViewModelProvider.notifier).reviewPending(pendingId);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/ask/ask_view_model_test.dart`
Expected: PASS (new group + all existing tests). Then `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ask/ask_view_model.dart test/features/ask/ask_view_model_test.dart
git commit -m "feat(mobile): open Confirm screen when chat produces a low-confidence draft"
```

---

### Task 7: Persona guidance + today's date in `start()`

Tell the model when to call `addExpense`, and give it today's date so it can resolve relative dates.

**Files:**
- Modify: `apps/mobile/lib/ai/prompts.dart` (extend `kChatSystemPersona`)
- Modify: `apps/mobile/lib/ai/chat_service.dart` (`start()` seeds a today chunk)
- Test: `apps/mobile/test/ai/chat_persona_test.dart` (create)

**Interfaces:**
- Consumes: `kChatSystemPersona` (extended string).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/ai/chat_persona_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/prompts.dart';

void main() {
  test('persona instructs the model to use addExpense for logging a purchase', () {
    expect(kChatSystemPersona, contains('addExpense'));
    // Never fabricate an amount.
    expect(kChatSystemPersona.toLowerCase(), contains('never invent'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/chat_persona_test.dart`
Expected: FAIL — `kChatSystemPersona` does not contain `addExpense`.

- [ ] **Step 3: Extend the persona**

In `prompts.dart`, add a section to `kChatSystemPersona` immediately before the `## Hard rules` heading:

```
## Recording a new expense

When the user states or logs a purchase they made — phrasings like "I spent",
"I bought", "I paid", "add", "log", "put down" followed by an amount — call the
addExpense tool instead of querying. Supply merchant, total, and a category
from the list above. Resolve the date to today, yesterday, or YYYY-MM-DD.
Never invent an amount — if no amount is given, still call addExpense with what
you have and the user will be asked to complete it.

```

- [ ] **Step 4: Seed today's date in `start()`**

In `chat_service.dart` `start()`, after the persona chunk is added, add a second chunk:

```dart
    await chat.addQueryChunk(
      Message.text(text: kChatSystemPersona, isUser: false),
    );
    await chat.addQueryChunk(
      Message.text(text: "Today's date is ${_todayIso()}.", isUser: false),
    );
```

(`_todayIso()` was added in Task 4.)

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/ai/chat_persona_test.dart`
Expected: PASS. Then `flutter analyze` — clean.

- [ ] **Step 6: Commit**

```bash
git add lib/ai/prompts.dart lib/ai/chat_service.dart test/ai/chat_persona_test.dart
git commit -m "feat(mobile): teach Carson to log expenses via addExpense"
```

---

### Task 8: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the whole mobile suite**

Run: `flutter test`
Expected: PASS — all tests green, including pre-existing suites.

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: "No issues found!"

- [ ] **Step 3: Manual smoke (optional, on device/sim with the model loaded)**

- Type "spent £12 on lunch at Wagamama yesterday" → Carson narrates a confirmation; the row appears in the Ledger dated yesterday.
- Type "add a coffee" (no amount/merchant detail) → the Confirm screen opens prefilled; Save files it.

- [ ] **Step 4: Commit any doc touch-ups (if needed)**

```bash
git commit --allow-empty -m "chore(mobile): verify NL expense creation end-to-end"
```

---

## Self-Review

**Spec coverage:**
- `addExpense` tool + schema → Task 4. ✓
- Deterministic completeness routing → Task 4 (`_runAddExpense`). ✓
- Direct insert via `insertExpense` → Task 4. ✓
- Low-confidence → pending `awaitingConfirmation` + `extractedJson` → Task 4. ✓
- `DraftReady` event (ChartReady pattern) → Tasks 3 (type) + 5 (emission). ✓
- `ChatService` gains `PendingRepository` → Task 3. ✓
- `AskViewModel` → `reviewPending` (Confirm screen) → Task 6. ✓
- Tolerant coercion (date today/yesterday/ISO, category→Other, currency default, item synthesis) → Task 2. ✓
- Persona guidance + today injection → Task 7. ✓
- `pending_repository.create` optional filePath → Task 1. ✓
- Tests for routing, coercion, navigation → Tasks 2, 4, 6. ✓

**Placeholder scan:** none — every code step shows complete code and exact commands.

**Type consistency:** `buildExpenseDraftJson(args, today)` defined Task 2, used Task 4. `_ToolOutcome(..., draftPendingId:)` defined Task 3, set Task 4, read Task 5. `DraftReady(pendingId)` defined Task 3, emitted Task 5, consumed Task 6. `runToolDebug` return record shape identical in Task 4 definition and test. `ChatService(gemma, db, pending)` 3-arg form consistent across Tasks 3, 4 (test), and the existing fake fix. `_todayIso()` added Task 4, reused Task 7.

**Known limitation (documented in spec):** direct insert defaults currency to `kDefaultCurrency`, not `currencyProvider` — matches the receipt pipeline; out of scope.
