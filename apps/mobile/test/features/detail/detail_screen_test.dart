import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/detail/detail_screen.dart';
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

  Widget buildSubject(String id) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: DetailScreen(expenseId: id, onBack: () {}),
      ),
    );
  }

  testWidgets('renders merchant, date, items, total and VAT from the provider',
      (tester) async {
    final id = await db.insertExpense(
      const ExpenseDraft(
        merchant: 'The Wolseley',
        date: '2026-06-11',
        currency: 'GBP',
        total: 84.09,
        vat: 9.34,
        items: [
          ExpenseItemDraft(
              name: 'Eggs Royale', amount: 15.75, category: 'Dining'),
          ExpenseItemDraft(
              name: 'Full English', amount: 17.50, category: 'Dining'),
        ],
      ),
    );

    await tester.pumpWidget(buildSubject(id));
    // Let the drift watch streams deliver their first value (real async),
    // then rebuild with the data.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text('The Wolseley'), findsOneWidget);
    expect(find.text('11 June 2026'), findsOneWidget);
    expect(find.text('Eggs Royale'), findsOneWidget);
    expect(find.text('Full English'), findsOneWidget);
    // Total headline + total row both show £84.09.
    expect(find.text('£84.09'), findsWidgets);
    // VAT row.
    expect(find.text('VAT'), findsOneWidget);
    expect(find.text('£9.34'), findsOneWidget);
    // Striped placeholder shows because sourceFile is null.
    expect(find.text('NO PHOTO'), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('shows an empty state for an unknown expense id', (tester) async {
    await tester.pumpWidget(buildSubject('does-not-exist'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No such expense'), findsOneWidget);

    await disposeTree(tester);
  });
}
