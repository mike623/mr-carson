import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/ledger/ledger_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ExpenseDraft draft({
    required String merchant,
    String date = '2026-06-10',
    String currency = 'GBP',
    required double total,
    double? vat,
    required List<ExpenseItemDraft> items,
  }) =>
      ExpenseDraft(
        merchant: merchant,
        date: date,
        currency: currency,
        total: total,
        vat: vat,
        items: items,
      );

  /// Unmounts the widget tree (disposing the ProviderScope and its drift watch
  /// subscriptions) and flushes the zero-duration timer drift schedules when it
  /// closes a stream — otherwise the framework reports a pending timer.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Flush the zero-duration timer drift schedules when it closes a stream;
    // there is no widget left so this settles immediately.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  /// Pumps the subject, lets the drift watch streams deliver their first value
  /// (real async — drift queries resolve off the fake test clock), then
  /// rebuilds with the data.
  Future<void> pumpAndDeliver(WidgetTester tester, Widget subject) async {
    await tester.pumpWidget(subject);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  Widget buildSubject({
    List<LedgerPending> pending = const [],
    void Function(String)? onReviewPending,
    void Function(String)? onOpenExpense,
  }) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: LedgerScreen(
          pending: pending,
          onReviewPending: onReviewPending,
          onOpenExpense: onOpenExpense,
        ),
      ),
    );
  }

  testWidgets('renders header, real month total, and recent expense tiles',
      (tester) async {
    // Seed two June 2026 expenses (the providers read DateTime.now()'s month;
    // the tests run with the system clock — see note below).
    final now = DateTime.now();
    final iso = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-15';

    await db.insertExpense(draft(
      merchant: 'Caffè Nero',
      date: iso,
      total: 6.15,
      items: const [
        ExpenseItemDraft(name: 'Latte', amount: 6.15, category: 'Dining'),
      ],
    ));
    await db.insertExpense(draft(
      merchant: 'Waitrose',
      date: iso,
      total: 63.40,
      items: const [
        ExpenseItemDraft(name: 'Shop', amount: 63.40, category: 'Groceries'),
      ],
    ));

    await pumpAndDeliver(tester, buildSubject());

    expect(find.text('The Ledger'), findsOneWidget);
    // Month total headline: 6.15 + 63.40 = 69.55.
    expect(find.text('£69.55'), findsOneWidget);
    // Recent tiles render the real merchants.
    expect(find.text('Caffè Nero'), findsOneWidget);
    expect(find.text('Waitrose'), findsOneWidget);
    // Donut legend reflects the seeded categories.
    expect(find.text('Dining'), findsWidgets);
    expect(find.text('Groceries'), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('shows the empty state when the database is empty',
      (tester) async {
    await pumpAndDeliver(tester, buildSubject());

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('The ledger is empty'), findsOneWidget);
    // No donut/recent content when wholly empty.
    expect(find.text('RECENT'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('tapping a recent expense reports its id', (tester) async {
    final now = DateTime.now();
    final iso = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-15';

    final id = await db.insertExpense(draft(
      merchant: 'The Wolseley',
      date: iso,
      total: 84.09,
      items: const [
        ExpenseItemDraft(name: 'Brunch', amount: 84.09, category: 'Dining'),
      ],
    ));

    String? tappedId;
    await pumpAndDeliver(
        tester, buildSubject(onOpenExpense: (i) => tappedId = i));

    await tester.tap(find.text('The Wolseley'));
    expect(tappedId, id);

    await disposeTree(tester);
  });

  testWidgets('shows pending card with stage text and Review button',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(
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
        onReviewPending: (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('Ready for your review'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    await disposeTree(tester);
  });
}
