import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/features/manual/manual_entry_screen.dart';
import 'package:mr_carson/features/settings/currency_provider.dart';
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
}

/// A [CurrencyNotifier] stand-in seeded with a fixed symbol for tests.
class _FixedCurrency extends CurrencyNotifier {
  _FixedCurrency(this._symbol);
  final String _symbol;

  @override
  String build() => _symbol;
}
