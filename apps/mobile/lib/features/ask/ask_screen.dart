import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/utils/currency_format.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

import '../../data/repositories/expense_repository.dart' show ChartData;
import '../model/model_lifecycle_view_model.dart';
import '../shell/shell_view_model.dart';
import 'ask_view_model.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// The HERO chat screen — streaming conversation with Mr. Carson.
///
/// A dumb view over [AskViewModel]: it renders bubbles/suggestions/input/chart
/// from VM state and forwards user actions to the VM. The only state held here
/// is UI-specific (scroll position + the text input controller).
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _AskScreenState extends ConsumerState<AskScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  /// Captured in [initState] so [dispose] can drop the focus flag without
  /// touching `ref` (which is no longer valid once the element is disposed).
  ShellViewModel? _shell;

  static const _chips = [
    "How much have I spent this month?",
    "Where did most of my money go?",
    "What was my largest expense?",
    "How do groceries compare to last month?",
  ];

  @override
  void initState() {
    super.initState();
    _shell = ref.read(shellViewModelProvider.notifier);
    // Mirror composer focus into the shell so the bottom nav steps aside while
    // asking (and reappears, reserving space, when the field blurs).
    _inputFocus.addListener(() {
      _shell?.setAskComposerFocused(_inputFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    // Drop the focus flag so a rebuild of the shell doesn't leave the nav hidden.
    _shell?.setAskComposerFocused(false);
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || ref.read(askViewModelProvider).streaming) return;
    _inputController.clear();
    ref.read(askViewModelProvider.notifier).send(trimmed);
  }

  void _stop() => ref.read(askViewModelProvider.notifier).stop();

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(askViewModelProvider);
    final model = ref.watch(modelLifecycleProvider);
    final navVisible = ref.watch(
      shellViewModelProvider.select((s) => s.navVisible),
    );
    final messages = s.messages;
    final hasMessages = messages.isNotEmpty;

    // Keep the list pinned to the bottom as messages/tokens arrive.
    ref.listen(askViewModelProvider, (_, __) => _scheduleScroll());

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _Header(
            model: model,
            onSettings: () => ref
                .read(shellViewModelProvider.notifier)
                .go(ShellScreen.settings),
          ),
          if (model.isDownloading)
            _PreparingBanner(
              pct: model.downloadPct,
              onView: () => ref
                  .read(shellViewModelProvider.notifier)
                  .go(ShellScreen.modelMgmt),
            ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              children: [
                if (!hasMessages) _GreetingBlock(),
                for (final msg in messages) ...[
                  if (msg != messages.first) const SizedBox(height: 18),
                  if (msg.isUser)
                    _UserBubble(text: msg.text)
                  else
                    _CarsonBubble(
                      text: msg.text,
                      isThinking: msg.thinking,
                      isStreaming: msg.streaming,
                      chart: msg.chart,
                    ),
                ],
              ],
            ),
          ),
          _Footer(
            model: model,
            // Reserve space for the bottom nav while it's visible (idle); drop it
            // when the composer is focused and the nav has stepped aside.
            navReserve: navVisible ? _kNavReserve : 0,
            showChips: !hasMessages,
            chips: _chips,
            streaming: s.streaming,
            controller: _inputController,
            focusNode: _inputFocus,
            onSend: _send,
            onStop: _stop,
            onSetup: () => ref.read(shellViewModelProvider.notifier).requireModel(
                  reason:
                      'To answer your questions, I shall need a moment to set up my mind.',
                ),
            onView: () => ref
                .read(shellViewModelProvider.notifier)
                .go(ShellScreen.modelMgmt),
          ),
        ],
      ),
    );
  }
}

/// Bottom padding reserved under the Ask footer for the full-width bottom nav so
/// the composer / cards clear the bar when idle (~nav height incl. safe area).
const double _kNavReserve = 96;

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.model, required this.onSettings});

  final ModelLifecycleState model;
  final VoidCallback onSettings;

  /// Status dot colour + label driven by the model lifecycle phase.
  ({Color dot, String text}) _status() {
    if (model.isReady) {
      return (dot: MrCarsonColors.grocery, text: 'On duty · offline');
    }
    if (model.isDownloading) {
      return (
        dot: MrCarsonColors.accent,
        text: 'Preparing — ${model.downloadPct.round()}%',
      );
    }
    if (model.isError) {
      return (dot: MrCarsonColors.warn, text: 'Needs attention');
    }
    // Absent.
    return (dot: MrCarsonColors.ink3, text: 'Awaiting your word');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status();
    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(
          bottom: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: avatar + name
          Row(
            children: [
              // 40×40 accent-bordered circle with "C"
              const CarsonMonogram(size: 40),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mr. Carson',
                    style: MrCarsonType.display(
                      size: 25,
                      weight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: status.dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status.text,
                        style: MrCarsonType.ui(
                          size: 12,
                          color: MrCarsonColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Right: settings gear button
          GestureDetector(
            onTap: onSettings,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(MrCarsonRadii.control),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.settings_outlined,
                color: MrCarsonColors.accent,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preparing banner (top, while downloading)
// ---------------------------------------------------------------------------

class _PreparingBanner extends StatelessWidget {
  const _PreparingBanner({required this.pct, required this.onView});

  final double pct;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onView,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: MrCarsonColors.accentSoft,
          border: Border(
            bottom: BorderSide(color: MrCarsonColors.line, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            const _BrassSpinner(size: 16, stroke: 2),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Mr. Carson is preparing — ${pct.round()}%',
                style: MrCarsonType.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: MrCarsonColors.ink,
                ),
              ),
            ),
            Text(
              'View',
              style: MrCarsonType.ui(
                size: 12,
                weight: FontWeight.w600,
                color: MrCarsonColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brass spinner (shared by banner + preparing card)
// ---------------------------------------------------------------------------

class _BrassSpinner extends StatelessWidget {
  const _BrassSpinner({required this.size, required this.stroke});

  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: stroke,
        valueColor: const AlwaysStoppedAnimation(MrCarsonColors.accent),
        backgroundColor: MrCarsonColors.accentSoft,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Greeting block
// ---------------------------------------------------------------------------

class _GreetingBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good evening.',
            style: MrCarsonType.display(
              size: 34,
              weight: FontWeight.w600,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'How may I be of service? You may ask me anything about your '
              'spending — I keep a faithful record.',
              style: MrCarsonType.ui(
                size: 15.5,
                color: MrCarsonColors.ink2,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User bubble
// ---------------------------------------------------------------------------

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: const BoxDecoration(
            color: MrCarsonColors.accent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Text(
            text,
            style: MrCarsonType.ui(
              size: 15,
              weight: FontWeight.w500,
              color: MrCarsonColors.accentInk,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carson bubble
// ---------------------------------------------------------------------------

class _CarsonBubble extends StatelessWidget {
  const _CarsonBubble({
    required this.text,
    required this.isThinking,
    required this.isStreaming,
    required this.chart,
  });

  final String text;
  final bool isThinking;
  final bool isStreaming;
  final ChartData? chart;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 28×28 avatar
        const CarsonMonogram(size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.96,
              minWidth: 54,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(5),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              child: isThinking
                  ? const _ThinkingDots()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StreamingText(
                          text: text,
                          isStreaming: isStreaming,
                        ),
                        if (chart != null) ...[
                          const SizedBox(height: 12),
                          _ChartCard(chart: chart!),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thinking dots
// ---------------------------------------------------------------------------

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 560),
      );
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) c.repeat(reverse: true);
      });
      return c;
    });
    _anims = _controllers
        .map(
          (c) => Tween<double>(begin: 0, end: -6).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
            child: AnimatedBuilder(
              animation: _anims[i],
              builder: (_, __) => Transform.translate(
                offset: Offset(0, _anims[i].value),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: MrCarsonColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming text with blinking caret
// ---------------------------------------------------------------------------

class _StreamingText extends StatefulWidget {
  const _StreamingText({required this.text, required this.isStreaming});

  final String text;
  final bool isStreaming;

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _caretCtrl;

  @override
  void initState() {
    super.initState();
    _caretCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _caretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            widget.text,
            style: MrCarsonType.ui(
              size: 15,
              color: MrCarsonColors.ink,
              height: 1.55,
            ),
          ),
        ),
        if (widget.isStreaming) ...[
          const SizedBox(width: 2),
          AnimatedBuilder(
            animation: _caretCtrl,
            builder: (_, __) => Opacity(
              opacity: _caretCtrl.value,
              child: Container(
                width: 2,
                height: 15,
                decoration: BoxDecoration(
                  color: MrCarsonColors.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chart card
// ---------------------------------------------------------------------------

/// One category's aggregated total, ready to plot as a single bar.
class _CategoryTotal {
  const _CategoryTotal(this.label, this.total, this.color);

  final String label;
  final double total;
  final Color color;
}

/// Fixed Brass & Ink palette for category bars — cycles past 5 categories.
/// Mirrors the ledger donut/legend palette so colour-keys stay consistent.
const _kCategoryPalette = [
  MrCarsonColors.accent,
  MrCarsonColors.grocery,
  MrCarsonColors.house,
  MrCarsonColors.transport,
  MrCarsonColors.ink3,
];

/// Renders the `chartSpending` result as a real `fl_chart` bar chart, one bar
/// per category (time-buckets are summed per category), in Brass & Ink colours.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart});

  final ChartData chart;

  /// Sums each category's totals across all time-buckets and orders them by
  /// total descending, assigning a stable palette colour per category.
  List<_CategoryTotal> _categoryTotals() {
    final sums = <String, double>{};
    for (final b in chart.rows) {
      sums[b.category] = (sums[b.category] ?? 0) + b.total;
    }
    final entries = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (var i = 0; i < entries.length; i++)
        _CategoryTotal(
          entries[i].key,
          entries[i].value,
          _kCategoryPalette[i % _kCategoryPalette.length],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categoryTotals();
    final symbol = currencySymbol(chart.currency);
    final grandTotal = cats.fold<double>(0, (s, c) => s + c.total);
    final maxTotal =
        cats.fold<double>(0, (m, c) => c.total > m ? c.total : m);

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'BY CATEGORY',
                  style: MrCarsonType.ui(
                    size: 11,
                    color: MrCarsonColors.ink3,
                    letterSpacing: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$symbol${grandTotal.toStringAsFixed(2)}',
                  style: MrCarsonType.display(
                    size: 24,
                    weight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (cats.isEmpty)
            Text(
              'No spending to chart, sir.',
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            )
          else
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxTotal <= 0 ? 1 : maxTotal * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= cats.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              cats[i].label,
                              style: MrCarsonType.ui(
                                size: 11,
                                color: MrCarsonColors.ink3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < cats.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: cats[i].total,
                            color: cats[i].color,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar (suggestions + input)
// ---------------------------------------------------------------------------

/// The Ask footer — a 3-state composer area (ready / locked / preparing) wrapped
/// in animated bottom padding that reserves room for the bottom nav when idle and
/// releases it while the composer is focused (nav hidden).
class _Footer extends StatelessWidget {
  const _Footer({
    required this.model,
    required this.navReserve,
    required this.showChips,
    required this.chips,
    required this.streaming,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onStop,
    required this.onSetup,
    required this.onView,
  });

  final ModelLifecycleState model;
  final double navReserve;
  final bool showChips;
  final List<String> chips;
  final bool streaming;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final VoidCallback onSetup;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (model.isReady) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showChips) ...[
            _ChipRow(chips: chips, onTap: onSend),
            const SizedBox(height: 10),
          ],
          _InputRow(
            streaming: streaming,
            controller: controller,
            focusNode: focusNode,
            onSend: onSend,
            onStop: onStop,
          ),
        ],
      );
    } else if (model.isDownloading) {
      content = _PreparingCard(pct: model.downloadPct, onView: onView);
    } else {
      // Absent or error — both invite (re)setup.
      content = _LockedCard(isError: model.isError, onSetup: onSetup);
    }

    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(
          top: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(12, 16, 16, 18 + navReserve),
        child: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Locked card — setup invitation (model absent / error)
// ---------------------------------------------------------------------------

class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.isError, required this.onSetup});

  final bool isError;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final copy = isError
        ? 'Something went amiss — shall I try again?'
        : "To answer your questions, I'll need a moment to set up my mind — "
            'a one-time download. Shall I?';
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CarsonMonogram(size: 30, borderWidth: 1),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  copy,
                  style: MrCarsonType.display(
                    size: 16.5,
                    weight: FontWeight.w500,
                    color: MrCarsonColors.ink2,
                    italic: true,
                    height: 1.42,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: onSetup,
              behavior: HitTestBehavior.opaque,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MrCarsonColors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  isError ? 'Try again' : 'Set up Mr. Carson',
                  style: MrCarsonType.ui(
                    size: 16,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.accentInk,
                  ),
                ),
              ),
            ),
          ),
          if (!isError) ...[
            const SizedBox(height: 13),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 18,
              runSpacing: 6,
              children: [
                _MetaDot(
                  color: MrCarsonColors.accent,
                  label: '2.4 GB · one-time',
                ),
                _MetaDot(
                  color: MrCarsonColors.grocery,
                  label: 'Stays on device',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Preparing card — tappable "setting up… X%"
// ---------------------------------------------------------------------------

class _PreparingCard extends StatelessWidget {
  const _PreparingCard({required this.pct, required this.onView});

  final double pct;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onView,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
          border: Border.all(color: MrCarsonColors.line, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(
          children: [
            const _BrassSpinner(size: 20, stroke: 2),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Setting up my mind — ${pct.round()}%',
                    style: MrCarsonType.ui(
                      size: 14.5,
                      weight: FontWeight.w600,
                      color: MrCarsonColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'I shall be ready in a moment, sir.',
                    style: MrCarsonType.ui(
                      size: 12.5,
                      color: MrCarsonColors.ink3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'View',
              style: MrCarsonType.ui(
                size: 13,
                weight: FontWeight.w600,
                color: MrCarsonColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips, required this.onTap});

  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return GestureDetector(
            onTap: () => onTap(chips[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(MrCarsonRadii.chip),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              child: Text(
                chips[i],
                style: MrCarsonType.ui(
                  size: 13.5,
                  color: MrCarsonColors.ink,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.streaming,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6, right: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink),
                decoration: InputDecoration(
                  hintText: 'Ask Mr. Carson…',
                  hintStyle: MrCarsonType.ui(
                    size: 15,
                    color: MrCarsonColors.ink3,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: onSend,
                textInputAction: TextInputAction.send,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ActionButton(streaming: streaming, onSend: onSend, onStop: onStop, controller: controller),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.streaming,
    required this.onSend,
    required this.onStop,
    required this.controller,
  });

  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    if (streaming) {
      // Stop button
      return GestureDetector(
        onTap: onStop,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: MrCarsonColors.surface2,
            borderRadius: BorderRadius.circular(MrCarsonRadii.control),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: MrCarsonColors.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
    }

    // Send button
    return GestureDetector(
      onTap: () => onSend(controller.text),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: MrCarsonColors.accent,
          borderRadius: BorderRadius.circular(MrCarsonRadii.control),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.arrow_upward,
          color: MrCarsonColors.accentInk,
          size: 17,
        ),
      ),
    );
  }
}
