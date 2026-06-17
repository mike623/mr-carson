// On-device e2e: add an expense by hand and confirm it lands in the Ledger.
//
// Runs on a real device/simulator. Drives the model-free Manual Entry path
// (no Gemma download needed), then verifies the DB-reactive Ledger renders the
// new row. Run with:
//   flutter test integration_test/manual_entry_e2e_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mr_carson/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual entry persists and shows in the ledger', (tester) async {
    const merchant = 'E2E Manual Cafe';

    await tester.pumpWidget(const ProviderScope(child: MrCarsonApp()));
    await tester.pumpAndSettle();

    // Onboarding → shell.
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();

    // Open the add sheet (center "+" in the bottom nav) → Enter manually.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter manually'));
    await tester.pumpAndSettle();

    // Fill merchant (1st field) and amount (2nd field), pick a category.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), merchant);
    await tester.enterText(fields.at(1), '12.50');
    await tester.tap(find.text('Dining'));
    await tester.pumpAndSettle();

    // Save → returns to ledger.
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // The DB-reactive ledger should now render the new expense.
    expect(find.text(merchant), findsWidgets);

    // Hold on the ledger so an external screenshot can capture it.
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
