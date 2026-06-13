import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/features/confirm/confirm_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({
    VoidCallback? onDiscard,
    VoidCallback? onSave,
  }) {
    return MaterialApp(
      theme: buildMrCarsonTheme(),
      home: ConfirmScreen(
        onDiscard: onDiscard ?? () {},
        onSave: onSave ?? () {},
      ),
    );
  }

  testWidgets('renders low-confidence badge and merchant name', (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Needs a look'), findsOneWidget);
    expect(find.text('Caffè Nero'), findsAtLeastNWidgets(1));
  });

  testWidgets('editing merchant removes the low-confidence badge',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    // Tap the merchant value text to enter edit mode.
    // The merchant text is rendered as a GestureDetector-wrapped Text widget.
    // There may be multiple 'Caffè Nero' occurrences (header subtitle + field).
    // The tappable one is the GestureDetector in _MerchantField (not editing branch).
    final merchantValueFinder = find.descendant(
      of: find.byType(GestureDetector),
      matching: find.text('Caffè Nero'),
    );
    await tester.tap(merchantValueFinder.first);
    await tester.pump();

    // A TextField should now be visible.
    expect(find.byType(TextField), findsOneWidget);

    // Clear and type a new merchant name.
    await tester.enterText(find.byType(TextField), 'Pret A Manger');
    await tester.pump();

    // Submit via TextInputAction.done.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Low-confidence badge should be gone.
    expect(find.text('Needs a look'), findsNothing);
    // New merchant name is shown.
    expect(find.text('Pret A Manger'), findsAtLeastNWidgets(1));
  });

  testWidgets('tapping Save expense fires the onSave callback', (tester) async {
    var saveCalled = false;
    await tester.pumpWidget(buildSubject(onSave: () => saveCalled = true));
    await tester.pump();

    await tester.tap(find.text('Save expense'));
    await tester.pump();

    expect(saveCalled, isTrue);
  });
}
