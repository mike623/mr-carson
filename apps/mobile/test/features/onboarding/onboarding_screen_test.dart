import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/features/onboarding/onboarding_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject({required VoidCallback onEnter}) {
    return ProviderScope(
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: OnboardingScreen(onEnter: onEnter),
      ),
    );
  }

  testWidgets('welcome step renders title, tagline, and Begin button',
      (tester) async {
    await tester.pumpWidget(buildSubject(onEnter: () {}));
    await tester.pump();

    expect(find.text('Mr. Carson'), findsOneWidget);
    expect(find.text('At your service.'), findsOneWidget);
    expect(find.text('Begin'), findsOneWidget);
  });

  testWidgets('Begin enters the app directly (no privacy/download step)',
      (tester) async {
    // Tall surface so the welcome Column + Spacer don't overflow at the default
    // 800×600 test viewport (which would push Begin off-screen).
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var entered = false;
    await tester.pumpWidget(buildSubject(onEnter: () => entered = true));
    await tester.pumpAndSettle(); // let the entrance fade finish

    await tester.tap(find.text('Begin'));
    await tester.pump();

    expect(entered, isTrue);
  });
}
