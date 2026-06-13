import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mr_carson/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

/// Represents an in-flight receipt being processed on-device.
///
/// [id] is the unique identifier used by [LedgerScreen.onReviewPending].
/// [ready] is true when processing is complete and the user can confirm.
/// [stage] is a human-readable processing stage label (e.g. "Extracting items").
/// [pct] is progress 0–100.
/// [merchant] and [total] are populated once extraction succeeds.
class LedgerPending {
  const LedgerPending({
    required this.id,
    required this.ready,
    required this.stage,
    required this.pct,
    this.merchant,
    this.total,
  });

  final String id;
  final bool ready;
  final String stage;
  final int pct;
  final String? merchant;
  final String? total;
}

// ---------------------------------------------------------------------------
// Public screen
// ---------------------------------------------------------------------------

/// The home / ledger screen — monthly summary donut, pending-receipt cards,
/// and a recent-expenses list.
///
/// Completely self-contained: no providers, no services. Pass mock data via
/// [pending] for previewing in-flight receipts. Tap callbacks are optional.
class LedgerScreen extends StatelessWidget {
  const LedgerScreen({
    super.key,
    this.onOpenExpense,
    this.onReviewPending,
    this.pending = const [],
  });

  /// Called when the user taps an expense tile. Receives the expense id.
  final void Function(String expenseId)? onOpenExpense;

  /// Called when the user taps "Review" on a ready pending card. Receives the pending id.
  final void Function(String pendingId)? onReviewPending;

  /// In-flight receipts to display. Defaults to empty so the screen renders standalone.
  final List<LedgerPending> pending;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: _Body(
              pending: pending,
              onOpenExpense: onOpenExpense,
              onReviewPending: onReviewPending,
            ),
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
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 14),
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(
          bottom: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The Ledger',
            style: MrCarsonType.display(size: 34, weight: FontWeight.w600, height: 1),
          ),
          const SizedBox(height: 4),
          Text(
            'June 2026 · all on device',
            style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scrollable body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.pending,
    required this.onOpenExpense,
    required this.onReviewPending,
  });

  final List<LedgerPending> pending;
  final void Function(String)? onOpenExpense;
  final void Function(String)? onReviewPending;

  static const _expenses = [
    _ExpenseData(
      id: 'nero',
      merchant: 'Caffè Nero',
      category: 'Dining',
      date: '12 June 2026',
      amount: '£6.15',
      initial: 'C',
      color: MrCarsonColors.accent,
    ),
    _ExpenseData(
      id: 'wolseley',
      merchant: 'The Wolseley',
      category: 'Dining',
      date: '11 June 2026',
      amount: '£84.09',
      initial: 'W',
      color: MrCarsonColors.accent,
    ),
    _ExpenseData(
      id: 'waitrose',
      merchant: 'Waitrose',
      category: 'Groceries',
      date: '10 June 2026',
      amount: '£63.40',
      initial: 'W',
      color: MrCarsonColors.grocery,
    ),
    _ExpenseData(
      id: 'uber',
      merchant: 'Uber',
      category: 'Transport',
      date: '9 June 2026',
      amount: '£18.50',
      initial: 'U',
      color: MrCarsonColors.transport,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(),
          if (pending.isNotEmpty) ...[
            _PendingSection(pending: pending, onReviewPending: onReviewPending),
          ],
          const SizedBox(height: 26),
          Text(
            'RECENT',
            style: MrCarsonType.ui(
              size: 11,
              color: MrCarsonColors.ink3,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: _expenses
                .map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExpenseTile(data: e, onTap: onOpenExpense),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(MrCarsonRadii.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DonutChart(),
          const SizedBox(width: 20),
          const Expanded(child: _LegendColumn()),
        ],
      ),
    );
  }
}

// Donut segment data
class _Segment {
  const _Segment(this.value, this.color);
  final double value;
  final Color color;
}

const _segments = [
  _Segment(412.0, MrCarsonColors.accent),
  _Segment(318.0, MrCarsonColors.grocery),
  _Segment(214.0, MrCarsonColors.house),
  _Segment(196.0, MrCarsonColors.transport),
  _Segment(144.6, MrCarsonColors.ink3),
];

class _DonutChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: CustomPaint(
        painter: _DonutPainter(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SPENT',
                style: MrCarsonType.ui(
                  size: 9.5,
                  color: MrCarsonColors.ink3,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '£1,284.60',
                style: MrCarsonType.display(size: 20, weight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    const inset = 15.0;
    final innerRadius = outerRadius - inset;

    final total = _segments.fold<double>(0, (s, e) => s + e.value);
    const gapAngle = 0.025; // radians gap between segments
    const startAngle = -math.pi / 2; // start at top

    double currentAngle = startAngle;

    for (final seg in _segments) {
      final sweep = (seg.value / total) * 2 * math.pi - gapAngle;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = inset
        ..strokeCap = StrokeCap.butt;

      final ringRadius = innerRadius + inset / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: ringRadius),
        currentAngle,
        sweep,
        false,
        paint,
      );
      currentAngle += sweep + gapAngle;
    }

    // Inner fill
    final innerPaint = Paint()
      ..color = MrCarsonColors.surface
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius - 1, innerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendColumn extends StatelessWidget {
  const _LegendColumn();

  static const _rows = [
    _LegendRow('Dining', '£412.00', MrCarsonColors.accent),
    _LegendRow('Groceries', '£318.00', MrCarsonColors.grocery),
    _LegendRow('Household', '£214.00', MrCarsonColors.house),
    _LegendRow('Transport', '£196.00', MrCarsonColors.transport),
    _LegendRow('Other', '£144.60', MrCarsonColors.ink3),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _rows
          .map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: r,
              ))
          .toList(),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(this.label, this.amount, this.color);

  final String label;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink2),
          ),
        ),
        Text(
          amount,
          style: MrCarsonType.ui(
            size: 13,
            weight: FontWeight.w600,
            color: MrCarsonColors.ink,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pending section
// ---------------------------------------------------------------------------

class _PendingSection extends StatelessWidget {
  const _PendingSection({
    required this.pending,
    required this.onReviewPending,
  });

  final List<LedgerPending> pending;
  final void Function(String)? onReviewPending;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        Row(
          children: [
            Text(
              'PENDING',
              style: MrCarsonType.ui(
                size: 11,
                color: MrCarsonColors.accent,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Divider(color: MrCarsonColors.line, thickness: 1, height: 1),
            ),
            const SizedBox(width: 10),
            Text(
              'processed on device',
              style: MrCarsonType.ui(size: 11, color: MrCarsonColors.ink3),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: pending
              .map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PendingCard(
                      item: p,
                      onReview: onReviewPending,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.item, required this.onReview});

  final LedgerPending item;
  final void Function(String)? onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PendingTile(ready: item.ready),
          const SizedBox(width: 14),
          Expanded(
            child: item.ready
                ? _ReadyContent(item: item)
                : _ProcessingContent(item: item),
          ),
          if (item.ready) ...[
            const SizedBox(width: 12),
            _ReviewButton(onTap: () => onReview?.call(item.id)),
          ],
        ],
      ),
    );
  }
}

/// The 46×46 thumbnail tile on the left of a pending card.
class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: MrCarsonColors.surface2,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: ready
            ? const Icon(Icons.check, color: MrCarsonColors.accent, size: 20)
            : const _SpinningRing(),
      ),
    );
  }
}

class _SpinningRing extends StatefulWidget {
  const _SpinningRing();

  @override
  State<_SpinningRing> createState() => _SpinningRingState();
}

class _SpinningRingState extends State<_SpinningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        size: const Size(20, 20),
        painter: _SpinnerPainter(_ctrl.value),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 8.0;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = MrCarsonColors.accentSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      t * 2 * math.pi - math.pi / 2,
      math.pi * 0.75,
      false,
      Paint()
        ..color = MrCarsonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter old) => old.t != t;
}

class _ProcessingContent extends StatelessWidget {
  const _ProcessingContent({required this.item});
  final LedgerPending item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.stage,
                style: MrCarsonType.ui(
                  size: 14.5,
                  weight: FontWeight.w600,
                  color: MrCarsonColors.ink,
                ),
              ),
            ),
            Text(
              '${item.pct}%',
              style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _ProgressBar(pct: item.pct),
        const SizedBox(height: 6),
        Text(
          'You may carry on — I shall not disturb you.',
          style: MrCarsonType.ui(size: 11.5, color: MrCarsonColors.ink3),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.pct});
  final int pct;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final total = constraints.maxWidth;
        final filled = (total * pct / 100).clamp(0.0, total);
        return Container(
          height: 6,
          decoration: BoxDecoration(
            color: MrCarsonColors.surface2,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: filled,
              decoration: BoxDecoration(
                color: MrCarsonColors.accent,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReadyContent extends StatelessWidget {
  const _ReadyContent({required this.item});
  final LedgerPending item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: item.merchant ?? 'Receipt',
                style: MrCarsonType.ui(
                  size: 15.5,
                  weight: FontWeight.w600,
                  color: MrCarsonColors.ink,
                ),
              ),
              if (item.total != null) ...[
                const WidgetSpan(child: SizedBox(width: 6)),
                TextSpan(
                  text: item.total,
                  style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: MrCarsonColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Ready for your review',
              style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.accent),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: MrCarsonColors.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          'Review',
          style: MrCarsonType.ui(
            size: 14,
            weight: FontWeight.w600,
            color: MrCarsonColors.accentInk,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expense tile
// ---------------------------------------------------------------------------

class _ExpenseData {
  const _ExpenseData({
    required this.id,
    required this.merchant,
    required this.category,
    required this.date,
    required this.amount,
    required this.initial,
    required this.color,
  });

  final String id;
  final String merchant;
  final String category;
  final String date;
  final String amount;
  final String initial;
  final Color color;
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.data, required this.onTap});

  final _ExpenseData data;
  final void Function(String)? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap?.call(data.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          color: MrCarsonColors.surface,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(MrCarsonRadii.tile),
        ),
        child: Row(
          children: [
            // Initial avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MrCarsonColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                data.initial,
                style: MrCarsonType.display(
                  size: 22,
                  weight: FontWeight.w600,
                  color: data.color,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Merchant + meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.merchant,
                    style: MrCarsonType.ui(
                      size: 15.5,
                      weight: FontWeight.w600,
                      color: MrCarsonColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.category} · ${data.date}',
                    style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount
            Text(
              data.amount,
              style: MrCarsonType.display(size: 21, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
