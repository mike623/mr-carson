// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app smoke test — renders without crashing',
      (WidgetTester tester) async {
    // _Root reads onboarding state from SharedPreferences, so the provider
    // must be overridden (as main() does) before mounting the app.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MrCarsonApp(),
    ));
    await tester.pump();
    // A fresh install starts on the onboarding screen; verify the title.
    expect(find.text('Mr. Carson'), findsOneWidget);
  });
}
