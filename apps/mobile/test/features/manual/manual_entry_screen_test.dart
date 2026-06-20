import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/manual/manual_entry_screen.dart';
import 'package:mr_carson/features/settings/currency_provider.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({String currency = '£'}) {
    return ProviderScope(
      overrides: [
        currencyProvider.overrideWith(() => _FixedCurrency(currency)),
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: const ManualEntryScreen(),
      ),
    );
  }

  Future<void> sizeAndPump(WidgetTester tester, Widget subject) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(subject);
    await tester.pump();
  }

  testWidgets('renders the core fields and header', (tester) async {
    await sizeAndPump(tester, buildSubject());

    expect(find.text('By hand'), findsOneWidget);
    expect(find.text('MERCHANT'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('Save expense'), findsOneWidget);
    // Category chips.
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
  });

  testWidgets('Save is disabled until merchant AND amount are present',
      (tester) async {
    await sizeAndPump(tester, buildSubject());

    // The innermost (closest) Container ancestor is the button surface that
    // carries the enabled/disabled background color.
    Color saveColor() {
      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Save expense'),
              matching: find.byType(Container),
            )
            .first,
      );
      return (container.decoration as BoxDecoration).color!;
    }

    // Initially disabled (surface2, not accent).
    expect(saveColor(), MrCarsonColors.surface2);

    // Type a merchant only — still disabled (no amount).
    await tester.enterText(
        find.widgetWithText(TextField, 'The establishment…'), 'Caffè Nero');
    await tester.pump();
    expect(saveColor(), MrCarsonColors.surface2);

    // Type an amount — now enabled (accent).
    await tester.enterText(
        find.widgetWithText(TextField, '0.00'), '6.15');
    await tester.pump();
    expect(saveColor(), MrCarsonColors.accent);
  });

  testWidgets('tapping "Add the particulars" reveals editable item rows',
      (tester) async {
    await sizeAndPump(tester, buildSubject());

    expect(find.text('Add the particulars'), findsOneWidget);
    expect(find.text('Subtotal'), findsNothing);

    await tester.tap(find.text('Add the particulars'));
    await tester.pump();

    // The particulars card is revealed with an item row + subtotal footer.
    expect(find.text('THE PARTICULARS'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Add another'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Item'), findsOneWidget);
  });

  testWidgets('currency prefix reflects the currencyProvider', (tester) async {
    await sizeAndPump(tester, buildSubject(currency: r'$'));

    // The amount field prefix shows the selected currency symbol.
    expect(find.text(r'$'), findsWidgets);
  });

  // --- persistence (the wired _save) ---------------------------------------

  /// Builds the screen over an explicit container so tests can read the DB and
  /// the shell toast after Save.
  ProviderContainer pumpWithDb(
    WidgetTester tester,
    AppDatabase db, {
    String currency = '£',
  }) {
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      currencyProvider.overrideWith(() => _FixedCurrency(currency)),
    ]);
    addTearDown(container.dispose);
    // Keep the AutoDispose shell provider alive so its toast survives the
    // async gap between Save and the assertion.
    final sub = container.listen(shellViewModelProvider, (_, __) {});
    addTearDown(sub.close);
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return container;
  }

  Future<void> mountScreen(WidgetTester tester, ProviderContainer c) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildMrCarsonTheme(), home: const ManualEntryScreen()),
    ));
    await tester.pump();
  }

  testWidgets('Save persists merchant/amount/currency and one item',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = pumpWithDb(tester, db); // £ → GBP
    await mountScreen(tester, container);

    await tester.enterText(
        find.widgetWithText(TextField, 'The establishment…'), 'Caffè Nero');
    await tester.enterText(find.widgetWithText(TextField, '0.00'), '6.15');
    await tester.tap(find.text('Dining'));
    await tester.pump();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 2300)); // drain toast timer
    final rows = await db.select(db.expenses).get();
    expect(rows, hasLength(1));
    expect(rows.single.merchant, 'Caffè Nero');
    expect(rows.single.total, 6.15);
    expect(rows.single.currency, 'GBP');

    final items = await db.select(db.expenseItems).get();
    expect(items, hasLength(1));
    expect(items.single.category, 'Dining');
  });

  testWidgets('Save with particulars persists each item, total = subtotal',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = pumpWithDb(tester, db);
    await mountScreen(tester, container);

    await tester.enterText(
        find.widgetWithText(TextField, 'The establishment…'), 'Tesco');
    await tester.tap(find.text('Add the particulars'));
    await tester.pump();

    // First (auto-added) item row: name / qty / price fields.
    await tester.enterText(find.widgetWithText(TextField, 'Item'), 'Milk');
    final priceField = find.widgetWithText(TextField, '0.00');
    await tester.enterText(priceField, '2.00');
    // qty defaults to '1' → lineTotal 2.00.
    await tester.pump();

    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 2300)); // drain toast timer
    final rows = await db.select(db.expenses).get();
    expect(rows.single.total, 2.00);
    final items = await db.select(db.expenseItems).get();
    expect(items.single.name, 'Milk');
    expect(items.single.amount, 2.00);
  });

  testWidgets('Save failure shows the error toast and does not navigate away',
      (tester) async {
    final db = _ThrowingDb();
    addTearDown(db.close);
    final container = pumpWithDb(tester, db);
    await mountScreen(tester, container);

    await tester.enterText(
        find.widgetWithText(TextField, 'The establishment…'), 'X');
    await tester.enterText(find.widgetWithText(TextField, '0.00'), '5');
    await tester.pump(); // flush setState so canSave is true before tapping
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(container.read(shellViewModelProvider).toast,
        contains('Could not save'));
    expect(container.read(shellViewModelProvider).screen,
        isNot(ShellScreen.ledger));
    await tester.pump(const Duration(milliseconds: 2300)); // drain toast timer
  });
}

/// AppDatabase whose insertExpense always fails — exercises the save error path.
class _ThrowingDb extends AppDatabase {
  _ThrowingDb() : super(NativeDatabase.memory());

  @override
  Future<String> insertExpense(ExpenseDraft expense,
      {String? sourceFile, String? imageHash}) async {
    throw Exception('db down');
  }
}

/// A [CurrencyNotifier] stand-in seeded with a fixed symbol for tests.
class _FixedCurrency extends CurrencyNotifier {
  _FixedCurrency(this._symbol);
  final String _symbol;

  @override
  String build() => _symbol;
}
