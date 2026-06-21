import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/domain/models/expense_detail.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/utils/currency_format.dart';
import 'package:mr_carson/ui/core/widgets/empty_state.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

/// Expense detail screen — loads a single expense from [expenseDetailProvider]
/// and renders merchant, date, line items, totals, and the source image if present.
///
/// [id] is the expense id to load. [onBack] is called when the user taps back.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({
    super.key,
    required this.id,
    required this.onBack,
    required this.onEdit,
    required this.onDelete,
  });

  final String id;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(expenseDetailProvider(id));

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _TopBar(onBack: onBack, onEdit: onEdit),
          Expanded(
            child: detailAsync.when(
              loading: () => const LoadingState(message: 'Fetching the receipt, sir.'),
              error: (e, _) => ErrorRetryState(
                message: 'I could not load that expense, sir.',
                onRetry: () => ref.invalidate(expenseDetailProvider(id)),
              ),
              data: (detail) {
                if (detail == null) {
                  return const EmptyState(
                    title: 'Nothing found, sir.',
                    body: 'That expense does not appear to be in the ledger.',
                    icon: Icons.receipt_long_outlined,
                  );
                }
                return _DetailBody(detail: detail, onDelete: onDelete);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onEdit});

  final VoidCallback onBack;
  final VoidCallback onEdit;

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
          Expanded(
            child: Text(
              'Expense',
              style: MrCarsonType.ui(size: 16, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          // Edit pill → opens the Edit Expense screen.
          GestureDetector(
            onTap: onEdit,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                'Edit',
                style: MrCarsonType.ui(
                  size: 14,
                  weight: FontWeight.w600,
                  color: MrCarsonColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail body (scrollable content)
// ---------------------------------------------------------------------------

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.onDelete});

  final ExpenseDetail detail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MerchantBlock(detail: detail),
          _ItemsSection(detail: detail),
          const _ButlerNote(),
          // Receipt now sits at the foot of the page (moved from the top).
          Padding(
            padding: const EdgeInsets.only(top: 30, bottom: 10),
            child: Text(
              'RECEIPT',
              style: MrCarsonType.ui(
                size: 11,
                color: MrCarsonColors.ink3,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _ReceiptImage(sourceFile: detail.sourceFile),
          _DeleteButton(merchant: detail.merchant, onDelete: onDelete),
        ],
      ),
    );
  }
}

/// "Delete expense" — destructive, so it confirms first (committed expenses are
/// not recoverable). The design's button alone deletes silently; the dialog is
/// the real-app safeguard for irreversible removal.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.merchant, required this.onDelete});

  final String merchant;
  final VoidCallback onDelete;

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MrCarsonColors.surface,
        title: Text('Remove this expense, sir?',
            style: MrCarsonType.ui(size: 17, weight: FontWeight.w600)),
        content: Text(
          'I shall strike $merchant from the ledger for good — there is no undoing it.',
          style: MrCarsonType.ui(size: 14, color: MrCarsonColors.ink2, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep it',
                style: MrCarsonType.ui(
                    size: 14.5, weight: FontWeight.w600, color: MrCarsonColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: MrCarsonType.ui(
                    size: 14.5, weight: FontWeight.w600, color: MrCarsonColors.warn)),
          ),
        ],
      ),
    );
    if (ok == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: GestureDetector(
        onTap: () => _confirm(context),
        child: Container(
          height: 50,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MrCarsonColors.line, width: 1),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delete_outline, size: 16, color: MrCarsonColors.ink3),
              const SizedBox(width: 9),
              Text('Delete expense',
                  style: MrCarsonType.ui(
                      size: 14.5, weight: FontWeight.w600, color: MrCarsonColors.ink3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt image / placeholder
// ---------------------------------------------------------------------------

class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.sourceFile});

  final String? sourceFile;

  @override
  Widget build(BuildContext context) {
    // If a source file path exists, show the image; otherwise show the
    // striped placeholder that matches the original design.
    if (sourceFile != null) {
      return Container(
        height: 158,
        decoration: BoxDecoration(
          color: MrCarsonColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MrCarsonColors.line, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.file(
            File(sourceFile!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _ReceiptPlaceholder(),
          ),
        ),
      );
    }
    return const _ReceiptPlaceholder();
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
            Positioned.fill(
              child: CustomPaint(painter: _StripePainter()),
            ),
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
                  'RECEIPT PHOTO',
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
    final symbol = currencySymbol(detail.currency);
    final totalStr = '$symbol${formatAmount(detail.total)}';
    final dateStr = _formatDate(detail.date);

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Center(
        child: Column(
          children: [
            Text(
              detail.merchant,
              style: MrCarsonType.display(
                  size: 30, weight: FontWeight.w600, height: 1.05),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            ),
            const SizedBox(height: 14),
            Text(
              totalStr,
              style: MrCarsonType.display(
                size: 52,
                weight: FontWeight.w600,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in detail.categories) _CategoryPill(category: c),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: MrCarsonColors.accentSoft,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: MrCarsonColors.forCategory(category),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            category,
            style: MrCarsonType.ui(
              size: 13.5,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink,
            ),
          ),
        ],
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
    final symbol = currencySymbol(detail.currency);
    final totalStr = '$symbol${formatAmount(detail.total)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 30, bottom: 10),
          child: Text(
            'ITEMS',
            style: MrCarsonType.ui(
              size: 11,
              color: MrCarsonColors.ink3,
              letterSpacing: 1.2,
            ).copyWith(fontFeatures: null),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: MrCarsonColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MrCarsonColors.line, width: 1),
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            children: [
              for (final item in detail.items)
                _ItemRow(
                  name: item.name,
                  amount: '$symbol${formatAmount(item.amount)}',
                ),
              _SubtotalRow(
                label: 'Total',
                amount: totalStr,
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
  const _ItemRow({required this.name, required this.amount});

  final String name;
  final String amount;

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
            child: Text(
              name,
              style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink),
            ),
          ),
          Text(
            amount,
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
          Text(
            '"',
            style: MrCarsonType.display(
              size: 18,
              italic: true,
              color: MrCarsonColors.accent,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'A civilised way to begin a day, if I may say so, sir.',
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format YYYY-MM-DD → "11 June 2026"
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
