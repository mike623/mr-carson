import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/features/onboarding/onboarding_screen.dart';
import 'package:mr_carson/features/onboarding/onboarding_view_model.dart';
import 'package:mr_carson/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Shared helper — pumps the screen with a tall enough surface to avoid
  // overflow on both welcome and privacy steps.
  Widget buildSubject({List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: OnboardingScreen(onEnter: () {}),
      ),
    );
  }

  testWidgets('welcome step renders title, tagline, and Begin button',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.text('Mr. Carson'), findsOneWidget);
    expect(find.text('At your service.'), findsOneWidget);
    expect(find.text('Begin'), findsOneWidget);
  });

  testWidgets('privacy step renders when step == 1', (tester) async {
    // Use a tall logical size so the privacy Column + Spacer don't overflow.
    // Default test surface is 800×600; the privacy step needs ~473px height.
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Override the provider so we start directly on step 1, bypassing the
    // welcome layout and its Spacer overflow at the default test viewport.
    await tester.pumpWidget(
      buildSubject(
        overrides: [
          onboardingViewModelProvider.overrideWith(
            () => _Step1ViewModel(),
          ),
        ],
      ),
    );
    // Let the fade animation start (not settle — no timer involved at step 1).
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('On your phone.\nOnly.'), findsOneWidget);
    expect(find.text('Allow & continue'), findsOneWidget);
  });

  // download step exercised via integration test
}

/// A ViewModel that starts at step 1 (Privacy) so tests can verify that step
/// without fighting the welcome screen's layout at the small test viewport.
class _Step1ViewModel extends OnboardingViewModel {
  @override
  OnboardingState build() {
    ref.onDispose(() {});
    return const OnboardingState(step: 1);
  }
}
