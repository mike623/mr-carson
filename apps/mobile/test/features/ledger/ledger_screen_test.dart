import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/ledger/ledger_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _wrap({
  required AppDatabase db,
  List<LedgerPending> pending = const [],
  void Function(String)? onOpenExpense,
  void Function(String)? onReviewPending,
}) {
  final repo = ExpenseRepository(db);
  final pendingRepo = PendingRepository(db);

  return ProviderScope(
    overrides: [
      expenseRepositoryProvider.overrideWithValue(repo),
      pendingRepositoryProvider.overrideWithValue(pendingRepo),
    ],
    child: MaterialApp(
      theme: buildMrCarsonTheme(),
      home: LedgerScreen(
        pending: pending,
        onOpenExpense: onOpenExpense,
        onReviewPending: onReviewPending,
      ),
    ),
  );
}

/// Replace the widget tree with an empty container to flush Drift's
/// zero-duration stream-cleanup timers before the test ends.
/// Must be called at the END of each testWidgets body that uses a real DB.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── loading state ──────────────────────────────────────────────────────────

  testWidgets('shows loading state while providers are resolving', (tester) async {
    // Use a stream that never emits to keep it in loading state.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monthlySummaryProvider.overrideWith((_) => const Stream.empty()),
          recentExpensesProvider.overrideWith((_) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: const LedgerScreen(),
        ),
      ),
    );

    // Do NOT pump past the first frame — providers are still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ── error state ────────────────────────────────────────────────────────────

  testWidgets('shows error state when recentExpensesProvider errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentExpensesProvider.overrideWith(
            (_) => Stream.error(Exception('db gone')),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: const LedgerScreen(),
        ),
      ),
    );

    await tester.pump(); // let error propagate

    expect(find.text('Try again'), findsOneWidget);
  });

  // ── empty state ────────────────────────────────────────────────────────────

  testWidgets('empty DB shows empty state — no mock rows', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    await tester.pumpWidget(_wrap(db: db));
    await tester.pump(); // first frame
    await tester.pump(); // stream emits

    // No hardcoded expense names
    expect(find.text('Caffè Nero'), findsNothing);
    expect(find.text('The Wolseley'), findsNothing);
    expect(find.text('Waitrose'), findsNothing);

    // Empty state widget shown
    expect(find.textContaining('Nothing'), findsAny);

    await _drain(tester);
  });

  // ── seeded expense shows in list ──────────────────────────────────────────

  testWidgets('seeded expense appears in recent list', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Tesco Express',
        date: '2024-06-15',
        currency: 'GBP',
        total: 18.50,
        items: [
          ExpenseItemDraft(name: 'Milk', amount: 18.50, category: 'Groceries'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db));
    await tester.pump();
    await tester.pump();

    expect(find.text('Tesco Express'), findsOneWidget);

    await _drain(tester);
  });

  // ── donut total reflects seeded data ─────────────────────────────────────

  testWidgets('donut center shows correct total from seeded expenses', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-10';

    await db.insertExpense(
      ExpenseDraft(
        merchant: 'Costa',
        date: dateStr,
        currency: 'GBP',
        total: 10.00,
        items: const [
          ExpenseItemDraft(name: 'Coffee', amount: 10.00, category: 'Dining'),
        ],
      ),
    );
    await db.insertExpense(
      ExpenseDraft(
        merchant: 'Sainsbury',
        date: dateStr,
        currency: 'GBP',
        total: 20.00,
        items: const [
          ExpenseItemDraft(name: 'Bread', amount: 20.00, category: 'Groceries'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db));
    await tester.pump();
    await tester.pump();

    // Total is 30.00 — rendered in the donut center.
    expect(find.textContaining('30'), findsAny);
    // Both merchants appear in the recent list.
    expect(find.text('Costa'), findsOneWidget);
    expect(find.text('Sainsbury'), findsOneWidget);

    await _drain(tester);
  });

  // ── pending card from Task 3 wiring still works ───────────────────────────

  testWidgets('pending card passed in shows Review button', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    String? reviewedId;

    await tester.pumpWidget(
      _wrap(
        db: db,
        pending: const [
          LedgerPending(
            id: 'p1',
            ready: true,
            stage: 'Ready for your review',
            pct: 100,
            merchant: 'Caffè Nero',
            total: '£6.15',
          ),
        ],
        onReviewPending: (id) => reviewedId = id,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Ready for your review'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await tester.tap(find.text('Review'));
    expect(reviewedId, equals('p1'));

    await _drain(tester);
  });

  // ── tapping expense tile calls onOpenExpense ──────────────────────────────

  testWidgets('tapping expense tile invokes onOpenExpense with its id', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Pret',
        date: '2024-06-01',
        currency: 'GBP',
        total: 7.50,
        items: [
          ExpenseItemDraft(name: 'Sandwich', amount: 7.50, category: 'Dining'),
        ],
      ),
    );

    String? openedId;
    await tester.pumpWidget(_wrap(db: db, onOpenExpense: (eid) => openedId = eid));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Pret'));
    expect(openedId, equals(id));

    await _drain(tester);
  });
}
