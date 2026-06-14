import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/features/onboarding/onboarding_screen.dart';
import 'package:mr_carson/features/onboarding/onboarding_view_model.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';

/// A fake [GemmaService] with a scripted download stream + load behaviour, so
/// onboarding can be exercised end-to-end with NO real network or model.
class _FakeGemmaService extends GemmaService {
  _FakeGemmaService({
    this.installed = false,
    this.failDownload = false,
    this.failLoad = false,
  });

  /// Whether a previous session already installed the model (fast-path).
  final bool installed;

  /// Whether the download stream should emit an error after some progress.
  final bool failDownload;

  /// Whether loadModel() should throw.
  final bool failLoad;

  /// Drives the scripted stream from the test so progress can be asserted tick
  /// by tick.
  final StreamController<int> controller = StreamController<int>();

  int loadCalls = 0;

  @override
  bool hasActiveModel() => installed;

  @override
  Stream<int> downloadModel([String? url]) {
    if (failDownload) {
      // Emit a little progress, then fail — exercises the onError arm.
      scheduleMicrotask(() async {
        controller.add(10);
        await Future<void>.delayed(Duration.zero);
        controller.addError(Exception('network down'));
      });
    }
    return controller.stream;
  }

  @override
  Future<void> loadModel() async {
    loadCalls++;
    if (failLoad) throw Exception('GPU delegate failed');
  }
}

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
    await tester.pumpWidget(buildSubject(overrides: [
      gemmaServiceProvider.overrideWithValue(_FakeGemmaService()),
    ]));
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

  testWidgets('real download progress drives the ring; load → Enter',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _FakeGemmaService();
    await tester.pumpWidget(buildSubject(overrides: [
      gemmaServiceProvider.overrideWithValue(fake),
    ]));

    // Jump to the download step.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
    container.read(onboardingViewModelProvider.notifier).allowAndStartDownload();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // A scripted progress tick from the REAL stream drives the ring. The stream
    // listener fires asynchronously, so pump once to deliver the event (state
    // update) and again to flush the resulting rebuild.
    fake.controller.add(42);
    await tester.pump();
    await tester.pump();
    expect(find.text('42'), findsOneWidget);

    // Completing the stream → loadModel → done → Enter button.
    fake.controller.add(100);
    await tester.pump();
    await tester.pump(); // let _loadModel's await complete
    await tester.pump();

    expect(fake.loadCalls, 1);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('At your service, sir.'), findsOneWidget);
  });

  testWidgets('download error shows ErrorRetryState with retry', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _FakeGemmaService(failDownload: true);
    await tester.pumpWidget(buildSubject(overrides: [
      gemmaServiceProvider.overrideWithValue(fake),
    ]));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
    container.read(onboardingViewModelProvider.notifier).allowAndStartDownload();
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 10)); // let stream error fire
    await tester.pump();

    // The honest error UI is shown with a retry affordance.
    expect(find.byType(ErrorRetryState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // No mock ramp / fake completion sneaked in.
    expect(find.text('Enter'), findsNothing);
  });

  testWidgets('load failure shows ErrorRetryState (no fake completion)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _FakeGemmaService(failLoad: true);
    await tester.pumpWidget(buildSubject(overrides: [
      gemmaServiceProvider.overrideWithValue(fake),
    ]));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
    container.read(onboardingViewModelProvider.notifier).allowAndStartDownload();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Download completes but the model fails to load → honest error, no Enter.
    fake.controller.add(100);
    await tester.pump();
    await tester.pump(); // let _loadModel's await reject
    await tester.pump();

    expect(fake.loadCalls, 1);
    expect(find.byType(ErrorRetryState), findsOneWidget);
    expect(find.text('Enter'), findsNothing);
  });

  testWidgets('already-installed fast-path skips download, loads, → Enter',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _FakeGemmaService(installed: true);
    await tester.pumpWidget(buildSubject(overrides: [
      gemmaServiceProvider.overrideWithValue(fake),
    ]));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
    container.read(onboardingViewModelProvider.notifier).allowAndStartDownload();
    await tester.pump();
    await tester.pump(); // let _loadModel complete
    await tester.pump();

    expect(fake.loadCalls, 1);
    expect(find.text('Enter'), findsOneWidget);
  });
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
