import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/ui_models.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/format.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

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
/// Provider-driven (spec §3): the donut + month total come from
/// [monthlySummaryProvider], the recent list from [recentExpensesProvider].
/// The [pending] list is still passed in by [AppShell] (it owns the
/// [pendingReceiptsProvider] → [LedgerPending] mapping, §2). Tap callbacks are
/// optional so the screen can render standalone in tests.
class LedgerScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(monthlySummaryProvider);
    final recent = ref.watch(recentExpensesProvider);

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _Header(summary: summary),
          Expanded(
            child: _Body(
              summary: summary,
              recent: recent,
              pending: pending,
              onOpenExpense: onOpenExpense,
              onReviewPending: onReviewPending,
              onRetrySummary: () => ref.invalidate(monthlySummaryProvider),
              onRetryRecent: () => ref.invalidate(recentExpensesProvider),
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
  const _Header({required this.summary});

  final AsyncValue<MonthlySummary> summary;

  @override
  Widget build(BuildContext context) {
    // The month subtitle tracks the loaded summary; falls back gracefully.
    final monthLabel = summary.maybeWhen(
      data: (s) => formatLongMonth(s.month),
      orElse: () => '',
    );
    final subtitle =
        monthLabel.isEmpty ? 'all on device' : '$monthLabel · all on device';

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
            style:
                MrCarsonType.display(size: 34, weight: FontWeight.w600, height: 1),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
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
    required this.summary,
    required this.recent,
    required this.pending,
    required this.onOpenExpense,
    required this.onReviewPending,
    required this.onRetrySummary,
    required this.onRetryRecent,
  });

  final AsyncValue<MonthlySummary> summary;
  final AsyncValue<List<ExpenseSummary>> recent;
  final List<LedgerPending> pending;
  final void Function(String)? onOpenExpense;
  final void Function(String)? onReviewPending;
  final VoidCallback onRetrySummary;
  final VoidCallback onRetryRecent;

  @override
  Widget build(BuildContext context) {
    // Whole-screen empty state: nothing recorded and nothing in flight.
    final recentIsEmpty = recent.maybeWhen(
      data: (rows) => rows.isEmpty,
      orElse: () => false,
    );
    if (recentIsEmpty && pending.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'The ledger is empty',
          subtitle:
              'Add a receipt and I shall keep your accounts in order, sir.',
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(summary: summary, onRetry: onRetrySummary),
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
          _RecentList(recent: recent, onOpenExpense: onOpenExpense, onRetry: onRetryRecent),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent list
// ---------------------------------------------------------------------------

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.recent,
    required this.onOpenExpense,
    required this.onRetry,
  });

  final AsyncValue<List<ExpenseSummary>> recent;
  final void Function(String)? onOpenExpense;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return recent.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingState(label: 'Reading the ledger…'),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ErrorRetryState(
          message: 'I could not read your recent expenses, sir.',
          onRetry: onRetry,
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          // Pending may be in flight while nothing is recorded yet.
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'No expenses recorded yet.',
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            ),
          );
        }
        return Column(
          children: rows
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ExpenseTile(data: e, onTap: onOpenExpense),
                  ))
              .toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.onRetry});

  final AsyncValue<MonthlySummary> summary;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(MrCarsonRadii.card),
      ),
      child: summary.when(
        loading: () => const SizedBox(
          height: 104,
          child: LoadingState(),
        ),
        error: (err, _) => SizedBox(
          height: 104,
          child: ErrorRetryState(
            message: 'I could not total this month, sir.',
            onRetry: onRetry,
          ),
        ),
        data: (s) {
          // Build slices from byCategory (per §1: donut uses byCategory; the
          // headline figure uses `total`).
          final slices = <_Slice>[
            for (var i = 0; i < s.byCategory.length; i++)
              _Slice(
                label: s.byCategory[i].category,
                value: s.byCategory[i].total,
                color: categoryColor(s.byCategory[i].category, index: i),
              ),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DonutChart(
                slices: slices,
                headline: formatMoney(s.currency, s.total),
              ),
              const SizedBox(width: 20),
              Expanded(child: _LegendColumn(slices: slices, currency: s.currency)),
            ],
          );
        },
      ),
    );
  }
}

/// A single donut/legend slice (category, amount, colour).
class _Slice {
  const _Slice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.slices, required this.headline});

  final List<_Slice> slices;
  final String headline;

  @override
  Widget build(BuildContext context) {
    final hasData = slices.any((s) => s.value > 0);
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasData)
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: 37,
                sections: [
                  for (final s in slices)
                    PieChartSectionData(
                      value: s.value,
                      color: s.color,
                      radius: 15,
                      showTitle: false,
                    ),
                ],
              ),
            )
          else
            // No itemised categories yet — draw an empty brass ring.
            CustomPaint(size: const Size(104, 104), painter: _EmptyRingPainter()),
          Column(
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
                headline,
                style: MrCarsonType.display(size: 20, weight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Draws a thin, faint ring for the "no categories yet" donut state.
class _EmptyRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const inset = 15.0;
    final ringRadius = size.width / 2 - inset / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = MrCarsonColors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = inset,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LegendColumn extends StatelessWidget {
  const _LegendColumn({required this.slices, required this.currency});

  final List<_Slice> slices;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return Text(
        'No itemised spending this month, sir.',
        style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: slices
          .map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LegendRow(
                  label: s.label,
                  amount: formatMoney(currency, s.value),
                  color: s.color,
                ),
              ))
          .toList(),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.amount,
    required this.color,
  });

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
            overflow: TextOverflow.ellipsis,
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

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.data, required this.onTap});

  final ExpenseSummary data;
  final void Function(String)? onTap;

  @override
  Widget build(BuildContext context) {
    final initial =
        data.merchant.isNotEmpty ? data.merchant[0].toUpperCase() : '?';
    return GestureDetector(
      onTap: () => onTap?.call(data.id),
      behavior: HitTestBehavior.opaque,
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
                initial,
                style: MrCarsonType.display(
                  size: 22,
                  weight: FontWeight.w600,
                  color: MrCarsonColors.accent,
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
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.itemCount} ${data.itemCount == 1 ? 'item' : 'items'} · ${formatLongDate(data.date)}',
                    style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount
            Text(
              formatMoney(data.currency, data.total),
              style: MrCarsonType.display(size: 21, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
