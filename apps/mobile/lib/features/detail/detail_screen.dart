import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/ui_models.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/format.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

/// Expense detail screen showing a full receipt breakdown for a single expense.
///
/// Provider-driven (spec §3): loads via [expenseDetailProvider] keyed by
/// [expenseId] and renders the real merchant, date, line items, totals (total +
/// VAT) and — when present — the source receipt image from the filesystem.
/// [onBack] is called when the user taps the back button in the top bar.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({
    super.key,
    required this.expenseId,
    required this.onBack,
  });

  final String expenseId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(expenseDetailProvider(expenseId));

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _TopBar(onBack: onBack),
          Expanded(
            child: detail.when(
              loading: () => const LoadingState(label: 'Fetching the receipt…'),
              error: (err, _) => ErrorRetryState(
                message: 'I could not retrieve this expense, sir.',
                onRetry: () =>
                    ref.invalidate(expenseDetailProvider(expenseId)),
              ),
              data: (d) {
                if (d == null) {
                  return const EmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No such expense',
                    subtitle: 'It may have been removed, sir.',
                  );
                }
                return _DetailBody(detail: d);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final ExpenseDetail detail;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReceiptImage(sourceFile: detail.sourceFile),
          _MerchantBlock(detail: detail),
          _ItemsSection(detail: detail),
          const _ButlerNote(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 58, 16, 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: MrCarsonColors.ink2,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Title
          Expanded(
            child: Text(
              'Expense',
              style: MrCarsonType.ui(size: 16, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt image (real file, or striped placeholder when absent)
// ---------------------------------------------------------------------------

class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.sourceFile});

  final String? sourceFile;

  @override
  Widget build(BuildContext context) {
    final path = sourceFile;
    final file = (path != null && path.isNotEmpty) ? File(path) : null;
    // Skip gracefully if the path is missing or the file no longer exists.
    if (file == null || !file.existsSync()) {
      return const _ReceiptPlaceholder();
    }
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: MrCarsonColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        // If decoding fails at runtime, fall back to the placeholder look.
        errorBuilder: (_, __, ___) => const _ReceiptPlaceholder(),
      ),
    );
  }
}

class _ReceiptPlaceholder extends StatelessWidget {
  const _ReceiptPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 158,
      decoration: BoxDecoration(
        color: MrCarsonColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          children: [
            // Diagonal stripes via CustomPaint
            Positioned.fill(
              child: CustomPaint(painter: _StripePainter()),
            ),
            // Centered "NO PHOTO" chip
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MrCarsonColors.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MrCarsonColors.line, width: 1),
                ),
                child: Text(
                  'NO PHOTO',
                  style: MrCarsonType.ui(
                    size: 11,
                    color: MrCarsonColors.ink3,
                    letterSpacing: 1,
                  ).copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints alternating diagonal stripes using surface / surface2 colours.
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = MrCarsonColors.surface;
    final paintB = Paint()..color = MrCarsonColors.surface2;
    const stripeWidth = 18.0;
    final diagonal =
        math.sqrt(size.width * size.width + size.height * size.height);
    final count = (diagonal / stripeWidth).ceil() + 2;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(math.pi / 4);
    canvas.translate(-diagonal / 2, -diagonal / 2);

    for (int i = 0; i < count; i++) {
      final rect = Rect.fromLTWH(i * stripeWidth, 0, stripeWidth, diagonal);
      canvas.drawRect(rect, i.isEven ? paintA : paintB);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Merchant block
// ---------------------------------------------------------------------------

class _MerchantBlock extends StatelessWidget {
  const _MerchantBlock({required this.detail});

  final ExpenseDetail detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Center(
        child: Column(
          children: [
            // Merchant name
            Text(
              detail.merchant,
              style: MrCarsonType.display(
                  size: 30, weight: FontWeight.w600, height: 1.05),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            // Date
            Text(
              formatLongDate(detail.date),
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            ),
            const SizedBox(height: 14),
            // Amount
            Text(
              formatMoney(detail.currency, detail.total),
              style: MrCarsonType.display(
                size: 52,
                weight: FontWeight.w600,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items section
// ---------------------------------------------------------------------------

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.detail});

  final ExpenseDetail detail;

  @override
  Widget build(BuildContext context) {
    final items = detail.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        Padding(
          padding: const EdgeInsets.only(top: 30, bottom: 10),
          child: Text(
            'ITEMS',
            style: MrCarsonType.ui(
              size: 11,
              color: MrCarsonColors.ink3,
              letterSpacing: 1.2,
            ).copyWith(
              fontFeatures: null,
            ),
          ),
        ),
        // Items card
        Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MrCarsonColors.line, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No itemised lines, sir.',
                          style: MrCarsonType.ui(
                            size: 14,
                            color: MrCarsonColors.ink3,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final item in items)
                  _ItemRow(item: item, currency: detail.currency),
              if (detail.vat > 0)
                _SubtotalRow(
                  label: 'VAT',
                  amount: formatMoney(detail.currency, detail.vat),
                  isTotal: false,
                ),
              _SubtotalRow(
                label: 'Total',
                amount: formatMoney(detail.currency, detail.total),
                isTotal: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.currency});

  final ExpenseLineItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink),
                ),
                if (item.category.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.category,
                    style: MrCarsonType.ui(
                        size: 12, color: MrCarsonColors.ink3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(currency, item.amount),
            style: MrCarsonType.ui(size: 15, weight: FontWeight.w600).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtotalRow extends StatelessWidget {
  const _SubtotalRow({
    required this.label,
    required this.amount,
    required this.isTotal,
  });

  final String label;
  final String amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final labelStyle = isTotal
        ? MrCarsonType.ui(size: 15.5, weight: FontWeight.w700)
        : MrCarsonType.ui(size: 14, color: MrCarsonColors.ink2);

    final amountStyle = isTotal
        ? MrCarsonType.ui(
            size: 15.5,
            weight: FontWeight.w700,
            color: MrCarsonColors.accent,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : MrCarsonType.ui(size: 14, color: MrCarsonColors.ink2).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isTotal ? 15 : 14,
      ),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(amount, style: amountStyle),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Butler note
// ---------------------------------------------------------------------------

class _ButlerNote extends StatelessWidget {
  const _ButlerNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large italic opening quote
          Text(
            '“',
            style: MrCarsonType.display(
              size: 18,
              italic: true,
              color: MrCarsonColors.accent,
            ),
          ),
          const SizedBox(width: 9),
          // Butler's note
          Expanded(
            child: Text(
              'Filed and accounted for, sir.',
              style: MrCarsonType.display(
                size: 16,
                italic: true,
                color: MrCarsonColors.ink2,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
