import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

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

  static const _chips = [
    "How much have I spent this month?",
    "Where did most of my money go?",
    "What was my largest expense?",
    "How do groceries compare to last month?",
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
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
    final messages = s.messages;
    final hasMessages = messages.isNotEmpty;

    // Keep the list pinned to the bottom as messages/tokens arrive.
    ref.listen(askViewModelProvider, (_, __) => _scheduleScroll());

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _Header(),
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
                      showChart: msg.hasChart,
                    ),
                ],
              ],
            ),
          ),
          _BottomBar(
            showChips: !hasMessages,
            chips: _chips,
            streaming: s.streaming,
            controller: _inputController,
            onSend: _send,
            onStop: _stop,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
                        decoration: const BoxDecoration(
                          color: MrCarsonColors.grocery,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'On duty · offline',
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
          // Right: service bell button
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: MrCarsonColors.surface,
              borderRadius: BorderRadius.circular(MrCarsonRadii.control),
              border: Border.all(color: MrCarsonColors.line, width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_none,
              color: MrCarsonColors.accent,
              size: 19,
            ),
          ),
        ],
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
    required this.showChart,
  });

  final String text;
  final bool isThinking;
  final bool isStreaming;
  final bool showChart;

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
                        if (showChart) ...[
                          const SizedBox(height: 12),
                          const _ChartCard(),
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

const _kChartRows = [
  _ChartRow('Dining', '£412', MrCarsonColors.accent, 1.00),
  _ChartRow('Groceries', '£318', MrCarsonColors.grocery, 0.77),
  _ChartRow('Household', '£214', MrCarsonColors.house, 0.52),
  _ChartRow('Transport', '£196', MrCarsonColors.transport, 0.48),
  _ChartRow('Other', '£144.60', MrCarsonColors.ink3, 0.35),
];

class _ChartRow {
  const _ChartRow(this.label, this.amount, this.color, this.fraction);

  final String label;
  final String amount;
  final Color color;
  final double fraction;
}

class _ChartCard extends StatefulWidget {
  const _ChartCard();

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            children: [
              Text(
                'THIS MONTH',
                style: MrCarsonType.ui(
                  size: 11,
                  color: MrCarsonColors.ink3,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '£1,284.60',
                style: MrCarsonType.display(
                  size: 24,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Bar rows
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) {
              return Column(
                children: _kChartRows.map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              row.label,
                              style: MrCarsonType.ui(
                                size: 13,
                                color: MrCarsonColors.ink2,
                              ),
                            ),
                            Text(
                              row.amount,
                              style: MrCarsonType.ui(
                                size: 13,
                                weight: FontWeight.w600,
                                color: MrCarsonColors.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                // Track
                                Container(
                                  height: 7,
                                  width: constraints.maxWidth,
                                  decoration: BoxDecoration(
                                    color: MrCarsonColors.surface2,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                // Fill — animated
                                Container(
                                  height: 7,
                                  width: constraints.maxWidth *
                                      row.fraction *
                                      _anim.value,
                                  decoration: BoxDecoration(
                                    color: row.color,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom bar (suggestions + input)
// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.showChips,
    required this.chips,
    required this.streaming,
    required this.controller,
    required this.onSend,
    required this.onStop,
  });

  final bool showChips;
  final List<String> chips;
  final bool streaming;
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(
          top: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showChips) ...[
            _ChipRow(chips: chips, onTap: onSend),
            const SizedBox(height: 10),
          ],
          _InputRow(
            streaming: streaming,
            controller: controller,
            onSend: onSend,
            onStop: onStop,
          ),
        ],
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
    required this.onSend,
    required this.onStop,
  });

  final bool streaming;
  final TextEditingController controller;
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
