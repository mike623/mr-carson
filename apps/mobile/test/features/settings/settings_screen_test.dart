import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';
import 'package:mr_carson/features/settings/currency_provider.dart';
import 'package:mr_carson/features/settings/settings_screen.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [ModelLifecycleViewModel] stand-in that simply returns a seeded state and
/// performs no service wiring (so tests run with no network / no GemmaService).
class _FakeModelVm extends ModelLifecycleViewModel {
  _FakeModelVm(this._seed);
  final ModelLifecycleState _seed;

  @override
  ModelLifecycleState build() {
    ref.onDispose(() {});
    return _seed;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Shared prefs instance seeded before each test — _DiscretionCard (now a
  // ConsumerWidget) reads modelModeProvider which depends on this provider.
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildSubject(ModelLifecycleState model) {
    return ProviderScope(
      overrides: [
        modelLifecycleProvider.overrideWith(() => _FakeModelVm(model)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('renders the section labels and version footer', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.ready)),
    );
    await tester.pump();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text("Mr. Carson's mind"), findsOneWidget);
    expect(find.text('The model'), findsOneWidget);
    expect(find.text('Mr. Carson · on-device · v1.0'), findsOneWidget);
  });

  testWidgets('model status row reflects ready state', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.ready)),
    );
    await tester.pump();

    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('model status row reflects absent state', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.notDownloaded)),
    );
    await tester.pump();

    expect(find.text('Not set up'), findsOneWidget);
  });

  testWidgets('model status row reflects downloading state with percent',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(
        const ModelLifecycleState(
          phase: GemmaState.downloading,
          downloadPct: 42,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Downloading… 42%'), findsOneWidget);
  });

  testWidgets('model status row reflects error state', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.error)),
    );
    await tester.pump();

    expect(find.text('Needs attention'), findsOneWidget);
  });

  testWidgets('currency toggle updates the selected symbol', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelLifecycleProvider.overrideWith(
            () => _FakeModelVm(
              const ModelLifecycleState(phase: GemmaState.ready),
            ),
          ),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: buildMrCarsonTheme(),
              home: const SettingsScreen(),
            );
          },
        ),
      ),
    );
    await tester.pump();

    // Defaults to £.
    expect(container.read(currencyProvider), '£');

    // Tap the $ segment.
    await tester.tap(find.text(r'$'));
    await tester.pump();

    expect(container.read(currencyProvider), r'$');
  });
}
