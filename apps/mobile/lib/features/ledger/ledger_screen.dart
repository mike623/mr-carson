import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/monthly_summary.dart';
import 'package:mr_carson/domain/models/expense_summary.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/utils/currency_format.dart';
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
    this.failed = false,
    this.error,
    this.merchant,
    this.total,
  });

  final String id;
  final bool ready;

  /// True when OCR failed; the card shows the error and a Retry button.
  final bool failed;

  /// Failure detail, shown on a failed card.
  final String? error;
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
/// Pending cards are fed in via [pending] from the shell (Task 3 wiring).
/// Monthly summary and recent expenses are loaded from Riverpod providers.
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({
    super.key,
    this.onOpenExpense,
    this.onReviewPending,
    this.onRetryPending,
    this.onDeletePending,
    this.pending = const [],
  });

  /// Called when the user taps an expense tile. Receives the expense id.
  final void Function(String expenseId)? onOpenExpense;

  /// Called when the user taps "Review" on a ready pending card. Receives the pending id.
  final void Function(String pendingId)? onReviewPending;

  /// Called when the user taps "Retry" on a failed pending card. Receives the pending id.
  final void Function(String pendingId)? onRetryPending;

  /// Called when the user taps the delete action on a pending card. Receives the pending id.
  final void Function(String pendingId)? onDeletePending;

  /// In-flight receipts to display (fed from shell via pendingReceiptsProvider).
  final List<LedgerPending> pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(monthlySummaryProvider);
    final expensesAsync = ref.watch(recentExpensesProvider);

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: _buildBody(ref, summaryAsync, expensesAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    WidgetRef ref,
    AsyncValue<MonthlySummary> summaryAsync,
    AsyncValue<List<ExpenseSummary>> expensesAsync,
  ) {
    // Show loading if either primary provider is still loading.
    if (expensesAsync.isLoading) {
      return const LoadingState(message: 'One moment, sir.');
    }

    // Error state — let user retry.
    if (expensesAsync.hasError) {
      return ErrorRetryState(
        message: 'I could not fetch the ledger, sir.',
        onRetry: () {
          ref.invalidate(recentExpensesProvider);
          ref.invalidate(monthlySummaryProvider);
        },
      );
    }

    final expenses = expensesAsync.value ?? [];
    final summary = summaryAsync.value;

    return _Body(
      summary: summary,
      expenses: expenses,
      pending: pending,
      onOpenExpense: onOpenExpense,
      onReviewPending: onReviewPending,
      onRetryPending: onRetryPending,
      onDeletePending: onDeletePending,
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthName = _monthName(now.month);
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
            '$monthName ${now.year} · all on device',
            style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
          ),
        ],
      ),
    );
  }

  static String _monthName(int month) {
    const names = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names[month];
  }
}

// ---------------------------------------------------------------------------
// Scrollable body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.summary,
    required this.expenses,
    required this.pending,
    required this.onOpenExpense,
    required this.onReviewPending,
    required this.onRetryPending,
    required this.onDeletePending,
  });

  final MonthlySummary? summary;
  final List<ExpenseSummary> expenses;
  final List<LedgerPending> pending;
  final void Function(String)? onOpenExpense;
  final void Function(String)? onReviewPending;
  final void Function(String)? onRetryPending;
  final void Function(String)? onDeletePending;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCard(summary: summary),
          if (pending.isNotEmpty) ...[
            _PendingSection(
              pending: pending,
              onReviewPending: onReviewPending,
              onRetryPending: onRetryPending,
              onDeletePending: onDeletePending,
            ),
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
          if (expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                title: 'Nothing to show just yet, sir.',
                body: 'Add your first expense to get started.',
                icon: Icons.receipt_long_outlined,
              ),
            )
          else
            Column(
              children: expenses
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ExpenseTile(expense: e, onTap: onOpenExpense),
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
  const _SummaryCard({required this.summary});

  final MonthlySummary? summary;

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
          _DonutChart(summary: summary),
          const SizedBox(width: 20),
          Expanded(child: _LegendColumn(summary: summary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donut chart
// ---------------------------------------------------------------------------

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.summary});

  final MonthlySummary? summary;

  @override
  Widget build(BuildContext context) {
    final total = summary?.total ?? 0.0;
    final currency = summary?.currency ?? 'GBP';
    final symbol = currencySymbol(currency);
    final totalStr = '$symbol${formatAmount(total)}';

    return SizedBox(
      width: 104,
      height: 104,
      child: CustomPaint(
        painter: _DonutPainter(buckets: summary?.buckets ?? []),
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
                totalStr,
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
  const _DonutPainter({required this.buckets});

  final List<CategoryBucket> buckets;

  // Fixed palette for categories — cycles if more than 5.
  static const _palette = [
    MrCarsonColors.accent,
    MrCarsonColors.grocery,
    MrCarsonColors.house,
    MrCarsonColors.transport,
    MrCarsonColors.ink3,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    const inset = 15.0;
    final innerRadius = outerRadius - inset;

    if (buckets.isEmpty) {
      // Draw a single empty-state ring.
      canvas.drawCircle(
        center,
        innerRadius + inset / 2,
        Paint()
          ..color = MrCarsonColors.surface2
          ..style = PaintingStyle.stroke
          ..strokeWidth = inset,
      );
      canvas.drawCircle(
        center,
        innerRadius - 1,
        Paint()
          ..color = MrCarsonColors.surface
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final total = buckets.fold<double>(0, (s, b) => s + b.total);
    const gapAngle = 0.025;
    const startAngle = -math.pi / 2;
    double currentAngle = startAngle;

    for (var i = 0; i < buckets.length; i++) {
      final sweep = (buckets[i].total / total) * 2 * math.pi - gapAngle;
      final color = _palette[i % _palette.length];
      final paint = Paint()
        ..color = color
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

    // Inner fill.
    canvas.drawCircle(
      center,
      innerRadius - 1,
      Paint()
        ..color = MrCarsonColors.surface
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.buckets != buckets;
}

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

class _LegendColumn extends StatelessWidget {
  const _LegendColumn({required this.summary});

  final MonthlySummary? summary;

  static const _palette = [
    MrCarsonColors.accent,
    MrCarsonColors.grocery,
    MrCarsonColors.house,
    MrCarsonColors.transport,
    MrCarsonColors.ink3,
  ];

  @override
  Widget build(BuildContext context) {
    final buckets = summary?.buckets ?? [];
    final currency = summary?.currency ?? 'GBP';
    final symbol = currencySymbol(currency);

    if (buckets.isEmpty) {
      return Text(
        'No spending this month',
        style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: buckets
          .asMap()
          .entries
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LegendRow(
                e.value.category,
                '$symbol${formatAmount(e.value.total)}',
                _palette[e.key % _palette.length],
              ),
            ),
          )
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
    required this.onRetryPending,
    required this.onDeletePending,
  });

  final List<LedgerPending> pending;
  final void Function(String)? onReviewPending;
  final void Function(String)? onRetryPending;
  final void Function(String)? onDeletePending;

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
                      onRetry: onRetryPending,
                      onDelete: onDeletePending,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.item,
    required this.onReview,
    required this.onRetry,
    required this.onDelete,
  });

  final LedgerPending item;
  final void Function(String)? onReview;
  final void Function(String)? onRetry;
  final void Function(String)? onDelete;

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
          _PendingTile(ready: item.ready, failed: item.failed),
          const SizedBox(width: 14),
          Expanded(
            child: item.failed
                ? _FailedContent(item: item)
                : item.ready
                    ? _ReadyContent(item: item)
                    : _ProcessingContent(item: item),
          ),
          if (item.failed) ...[
            const SizedBox(width: 12),
            _PillButton(
              label: 'Retry',
              onTap: () => onRetry?.call(item.id),
            ),
          ] else if (item.ready) ...[
            const SizedBox(width: 12),
            _PillButton(
              label: 'Review',
              onTap: () => onReview?.call(item.id),
            ),
          ],
          // Delete is offered on actionable cards (failed or ready), not while
          // a receipt is still being read.
          if ((item.failed || item.ready) && onDelete != null) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => onDelete!.call(item.id),
              icon: const Icon(Icons.delete_outline),
              color: MrCarsonColors.ink3,
              iconSize: 20,
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// The 46×46 thumbnail tile on the left of a pending card.
class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.ready, this.failed = false});
  final bool ready;
  final bool failed;

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
        child: failed
            ? const Icon(Icons.error_outline,
                color: MrCarsonColors.ink3, size: 20)
            : ready
                ? const Icon(Icons.check,
                    color: MrCarsonColors.accent, size: 20)
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

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = MrCarsonColors.accentSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

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

/// Failed-card body: butler apology + the underlying error, kept terse.
class _FailedContent extends StatelessWidget {
  const _FailedContent({required this.item});
  final LedgerPending item;

  @override
  Widget build(BuildContext context) {
    final detail = (item.error ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.stage,
          style: MrCarsonType.ui(
            size: 14.5,
            weight: FontWeight.w600,
            color: MrCarsonColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          detail.isEmpty
              ? 'Your photo is kept safe — retry when ready.'
              : detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
        ),
      ],
    );
  }
}

/// Accent pill button used for "Review" and "Retry" on pending cards.
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});
  final String label;
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
          label,
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
  const _ExpenseTile({required this.expense, required this.onTap});

  final ExpenseSummary expense;
  final void Function(String)? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = expense.merchant.isNotEmpty
        ? expense.merchant[0].toUpperCase()
        : '?';
    final color = _categoryColor(expense.category);
    final currency = currencySymbol(expense.currency);
    final amountStr = '$currency${formatAmount(expense.total)}';
    final dateStr = _formatDate(expense.date);

    return GestureDetector(
      onTap: () => onTap?.call(expense.id),
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
                  color: color,
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
                    expense.merchant,
                    style: MrCarsonType.ui(
                      size: 15.5,
                      weight: FontWeight.w600,
                      color: MrCarsonColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${expense.category} · $dateStr',
                    style: MrCarsonType.ui(size: 12.5, color: MrCarsonColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount
            Text(
              amountStr,
              style: MrCarsonType.display(size: 21, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _categoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'groceries':
      return MrCarsonColors.grocery;
    case 'transport':
      return MrCarsonColors.transport;
    case 'household':
    case 'house':
      return MrCarsonColors.house;
    default:
      return MrCarsonColors.accent;
  }
}

/// Format YYYY-MM-DD → "15 June 2026"
String _formatDate(String iso) {
  try {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final day = int.parse(parts[2]);
    final month = int.parse(parts[1]);
    final year = parts[0];
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '$day ${months[month]} $year';
  } catch (_) {
    return iso;
  }
}
