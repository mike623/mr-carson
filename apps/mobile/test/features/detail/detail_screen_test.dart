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
import 'package:mr_carson/features/detail/detail_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

Widget _wrap({
  required AppDatabase db,
  required String expenseId,
  VoidCallback? onBack,
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
      home: DetailScreen(
        id: expenseId,
        onBack: onBack ?? () {},
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

  testWidgets('shows loading indicator while provider resolves', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => const Stream.empty(),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'loading-id', onBack: () {}),
        ),
      ),
    );

    // First frame — provider has not emitted yet.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ── null / not found ───────────────────────────────────────────────────────

  testWidgets('shows not-found state for unknown id', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    await tester.pumpWidget(_wrap(db: db, expenseId: 'no-such-id'));
    await tester.pump();
    await tester.pump();

    // Should not crash; should show an empty / not-found message.
    expect(find.text('The Wolseley'), findsNothing);
    expect(find.textContaining('Nothing found'), findsOneWidget);

    await _drain(tester);
  });

  // ── error state ────────────────────────────────────────────────────────────

  testWidgets('shows error state when provider errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseDetailProvider.overrideWith(
            (ref, id) => Stream.error(Exception('disk failure')),
          ),
        ],
        child: MaterialApp(
          theme: buildMrCarsonTheme(),
          home: DetailScreen(id: 'any', onBack: () {}),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
  });

  // ── happy path: merchant + line items ─────────────────────────────────────

  testWidgets('renders merchant name and line items from DB', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'The Wolseley',
        date: '2026-06-11',
        currency: 'GBP',
        total: 84.09,
        items: [
          ExpenseItemDraft(name: 'Eggs Royale', amount: 15.75, category: 'Dining'),
          ExpenseItemDraft(name: "Buck's Fizz", amount: 24.00, category: 'Dining'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db, expenseId: id));
    await tester.pump();
    await tester.pump();

    // Merchant name rendered
    expect(find.text('The Wolseley'), findsOneWidget);

    // Line items rendered
    expect(find.text('Eggs Royale'), findsOneWidget);
    expect(find.textContaining("Buck's Fizz"), findsOneWidget);

    // NO hardcoded stub data from old screen
    expect(find.text('Full English'), findsNothing);
    expect(find.text('Pastry basket'), findsNothing);

    await _drain(tester);
  });

  // ── total is displayed ────────────────────────────────────────────────────

  testWidgets('renders total amount', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Pret',
        date: '2026-06-10',
        currency: 'GBP',
        total: 7.50,
        items: [
          ExpenseItemDraft(name: 'Sandwich', amount: 7.50, category: 'Dining'),
        ],
      ),
    );

    await tester.pumpWidget(_wrap(db: db, expenseId: id));
    await tester.pump();
    await tester.pump();

    expect(find.text('Pret'), findsOneWidget);
    expect(find.textContaining('7.50'), findsAny);

    await _drain(tester);
  });

  // ── back callback ─────────────────────────────────────────────────────────

  testWidgets('onBack is called when back button is tapped', (tester) async {
    final db = _makeDb();
    addTearDown(db.close);

    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Costa',
        date: '2026-06-01',
        currency: 'GBP',
        total: 3.50,
        items: [
          ExpenseItemDraft(name: 'Coffee', amount: 3.50, category: 'Dining'),
        ],
      ),
    );

    bool backed = false;
    await tester.pumpWidget(_wrap(db: db, expenseId: id, onBack: () => backed = true));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    expect(backed, isTrue);

    await _drain(tester);
  });
}
