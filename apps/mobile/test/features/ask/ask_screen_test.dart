import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/features/ask/ask_screen.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Seeded [ModelLifecycleViewModel] with no service wiring (no network needed).
class _FakeModelVm extends ModelLifecycleViewModel {
  _FakeModelVm(this._seed);
  final ModelLifecycleState _seed;

  @override
  ModelLifecycleState build() {
    ref.onDispose(() {});
    return _seed;
  }
}

/// Seeded [ShellViewModel] that records navigation / focus calls without the
/// real receipt-pipeline wiring.
class _FakeShellVm extends ShellViewModel {
  ShellScreen? lastGo;
  String? lastRequireReason;
  final List<bool> focusCalls = [];

  @override
  ShellState build() {
    ref.onDispose(() {});
    return const ShellState();
  }

  @override
  void go(ShellScreen s) {
    lastGo = s;
    state = state.copyWith(screen: s);
  }

  @override
  void requireModel({String reason = ''}) {
    lastRequireReason = reason;
  }

  @override
  void setAskComposerFocused(bool focused) {
    focusCalls.add(focused);
    state = state.copyWith(askComposerFocused: focused);
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject(ModelLifecycleState model, {_FakeShellVm? shell}) {
    return ProviderScope(
      overrides: [
        modelLifecycleProvider.overrideWith(() => _FakeModelVm(model)),
        shellViewModelProvider
            .overrideWith(() => shell ?? _FakeShellVm()),
      ],
      child: MaterialApp(
        theme: buildMrCarsonTheme(),
        home: const AskScreen(),
      ),
    );
  }

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('header shows a gear (Settings) and not the old bell',
      (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.ready)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
  });

  testWidgets('tapping the gear navigates to Settings', (tester) async {
    sizeView(tester);
    final shell = _FakeShellVm();
    await tester.pumpWidget(
      buildSubject(
        const ModelLifecycleState(phase: GemmaState.ready),
        shell: shell,
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();

    expect(shell.lastGo, ShellScreen.settings);
  });

  testWidgets('ready state shows the input field', (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.ready)),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('On duty · offline'), findsOneWidget);
    expect(find.text('Set up Mr. Carson'), findsNothing);
  });

  testWidgets('locked state shows the setup invitation, not the input',
      (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.notDownloaded)),
    );
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Set up Mr. Carson'), findsOneWidget);
    expect(find.text('2.4 GB · one-time'), findsOneWidget);
    expect(find.text('Awaiting your word'), findsOneWidget);
  });

  testWidgets('locked CTA calls requireModel with the contextual reason',
      (tester) async {
    sizeView(tester);
    final shell = _FakeShellVm();
    await tester.pumpWidget(
      buildSubject(
        const ModelLifecycleState(phase: GemmaState.notDownloaded),
        shell: shell,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Set up Mr. Carson'));
    await tester.pump();

    expect(shell.lastRequireReason, isNotNull);
    expect(shell.lastRequireReason, contains('set up my mind'));
  });

  testWidgets('preparing state shows the top banner + setup card with percent',
      (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(
        phase: GemmaState.downloading,
        downloadPct: 42,
      )),
    );
    await tester.pump();

    expect(find.text('Mr. Carson is preparing — 42%'), findsOneWidget);
    expect(find.text('Setting up my mind — 42%'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Preparing — 42%'), findsOneWidget); // header status
  });

  testWidgets('error state shows the try-again invitation', (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(const ModelLifecycleState(phase: GemmaState.error)),
    );
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
