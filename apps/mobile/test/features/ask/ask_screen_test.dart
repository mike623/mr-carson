import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/ask/ask_screen.dart';
import 'package:mr_carson/features/ask/ask_view_model.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';
import 'package:mr_carson/features/settings/transcript_prefs.dart';
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

/// Seeded [AskViewModel] that exposes a fixed message list so the screen can be
/// rendered without any inference wiring.
class _FakeAskVm extends AskViewModel {
  _FakeAskVm(this._seed);
  final AskState _seed;

  @override
  AskState build() => _seed;
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

/// Seeded transcript prefs override.
class _FakeTranscriptVm extends TranscriptPrefsNotifier {
  _FakeTranscriptVm(this._seed);
  final TranscriptPrefs _seed;

  @override
  TranscriptPrefs build() => _seed;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget buildSubject(
    ModelLifecycleState model, {
    _FakeShellVm? shell,
    AskState? ask,
    TranscriptPrefs? prefs,
  }) {
    return ProviderScope(
      overrides: [
        modelLifecycleProvider.overrideWith(() => _FakeModelVm(model)),
        shellViewModelProvider.overrideWith(() => shell ?? _FakeShellVm()),
        if (ask != null)
          askViewModelProvider.overrideWith(() => _FakeAskVm(ask)),
        if (prefs != null)
          transcriptPrefsProvider.overrideWith(() => _FakeTranscriptVm(prefs)),
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

  testWidgets('a message carrying ChartData renders an fl_chart with N bars',
      (tester) async {
    sizeView(tester);
    const chart = (
      rows: [
        CategoryBucket(bucket: '2026-06', category: 'Dining', total: 412),
        CategoryBucket(bucket: '2026-06', category: 'Groceries', total: 318),
        CategoryBucket(bucket: '2026-06', category: 'Household', total: 214),
      ],
      granularity: Granularity.month,
      currency: 'GBP',
    );
    await tester.pumpWidget(
      buildSubject(
        const ModelLifecycleState(phase: GemmaState.ready),
        ask: const AskState(
          messages: [
            ChatMessage(isUser: true, text: 'How did spending go?'),
            ChatMessage(
              isUser: false,
              text: 'Here is the breakdown, sir.',
              chart: chart,
            ),
          ],
        ),
      ),
    );
    // Let the chart animation settle.
    await tester.pump(const Duration(seconds: 1));

    // A real fl_chart is present...
    expect(find.byType(BarChart), findsOneWidget);

    // ...with one bar group per category bucket.
    final barChart = tester.widget<BarChart>(find.byType(BarChart));
    expect(barChart.data.barGroups.length, 3);
  });

  // Tool-call rows render via RichText/TextSpan, which `find.text` ignores.
  Finder richTextContaining(String s) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(s),
      );

  group('opt-in workings (thinking + tool calls)', () {
    const reply = AskState(
      messages: [
        ChatMessage(isUser: true, text: 'How much this month?'),
        ChatMessage(
          isUser: false,
          text: 'You have spent zero pounds this month.',
          thinkingText: 'Let me consult the ledger for this month.',
          toolCalls: [
            ToolCall(name: 'queryExpenses', args: {'dateRange': 'thisMonth'}),
          ],
        ),
      ],
    );

    testWidgets('hidden by default — clean answer only', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(
        buildSubject(
          const ModelLifecycleState(phase: GemmaState.ready),
          ask: reply,
        ),
      );
      await tester.pump();

      expect(find.text('You have spent zero pounds this month.'),
          findsOneWidget);
      expect(find.text('CONSULTED THE LEDGER'), findsNothing);
      expect(find.text('HIS REASONING'), findsNothing);
      expect(richTextContaining('queryExpenses'), findsNothing);
    });

    testWidgets('shown when both opt-ins are on', (tester) async {
      sizeView(tester);
      await tester.pumpWidget(
        buildSubject(
          const ModelLifecycleState(phase: GemmaState.ready),
          ask: reply,
          prefs: const TranscriptPrefs(
            showThinking: true,
            showToolCalls: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('CONSULTED THE LEDGER'), findsOneWidget);
      expect(find.text('HIS REASONING'), findsOneWidget);
      expect(richTextContaining('queryExpenses'), findsOneWidget);
      expect(richTextContaining('dateRange: thisMonth'), findsOneWidget);
      // The narrated answer is still present.
      expect(find.text('You have spent zero pounds this month.'),
          findsOneWidget);
    });

    testWidgets('only reasoning shows when only that opt-in is on',
        (tester) async {
      sizeView(tester);
      await tester.pumpWidget(
        buildSubject(
          const ModelLifecycleState(phase: GemmaState.ready),
          ask: reply,
          prefs: const TranscriptPrefs(showThinking: true),
        ),
      );
      await tester.pump();

      expect(find.text('HIS REASONING'), findsOneWidget);
      expect(find.text('CONSULTED THE LEDGER'), findsNothing);
    });
  });

  testWidgets('a message without ChartData renders no chart', (tester) async {
    sizeView(tester);
    await tester.pumpWidget(
      buildSubject(
        const ModelLifecycleState(phase: GemmaState.ready),
        ask: const AskState(
          messages: [
            ChatMessage(isUser: true, text: 'Good evening'),
            ChatMessage(isUser: false, text: 'Good evening, sir.'),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(BarChart), findsNothing);
  });
}
