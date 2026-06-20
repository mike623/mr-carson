import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the model-location section', (tester) async {
    await _pump(tester);
    expect(find.text('WHERE HE THINKS'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('switching to Online asks for consent then applies', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    // A consent dialog appears.
    expect(find.textContaining('leaves your phone'), findsOneWidget);
    await tester.tap(find.text('Use Online'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(modelModeProvider), ModelMode.online);
  });

  testWidgets('declining consent leaves mode unchanged', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep offline'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(modelModeProvider), isNot(ModelMode.online));
  });
}
