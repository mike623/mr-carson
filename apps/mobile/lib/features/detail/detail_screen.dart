import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';

/// Expense detail screen showing a full receipt breakdown for a single expense.
///
/// Uses mock data for "The Wolseley". [onBack] is called when the user taps the
/// back button in the top bar.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Column(
        children: [
          _TopBar(onBack: onBack),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(18, 22, 18, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReceiptPlaceholder(),
                  _MerchantBlock(),
                  _ItemsSection(),
                  _ButlerNote(),
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
          const SizedBox(width: 10),
          // Edit pill
          Container(
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt placeholder
// ---------------------------------------------------------------------------

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
            // Centered "RECEIPT PHOTO" chip
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

/// Paints alternating diagonal stripes using surface / surface2 colours.
class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = MrCarsonColors.surface;
    final paintB = Paint()..color = MrCarsonColors.surface2;
    const stripeWidth = 18.0;
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
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
  const _MerchantBlock();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Center(
        child: Column(
          children: [
            // Merchant name
            Text(
              'The Wolseley',
              style: MrCarsonType.display(size: 30, weight: FontWeight.w600, height: 1.05),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            // Date
            Text(
              '11 June 2026',
              style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
            ),
            const SizedBox(height: 14),
            // Amount
            Text(
              '£84.09',
              style: MrCarsonType.display(
                size: 52,
                weight: FontWeight.w600,
              ).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 14),
            // Category pill
            const _CategoryPill(),
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill();

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
          // Small accent square
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: MrCarsonColors.accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Dining',
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
  const _ItemsSection();

  static const _items = [
    _LineItem('Eggs Royale', 1, '£15.75'),
    _LineItem('Full English', 1, '£17.50'),
    _LineItem("Buck's Fizz", 2, '£24.00'),
    _LineItem('Espresso', 2, '£9.00'),
    _LineItem('Pastry basket', 1, '£8.50'),
  ];

  @override
  Widget build(BuildContext context) {
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
              for (final item in _items) _ItemRow(item: item),
              const _SubtotalRow(label: 'Subtotal', amount: '£74.75', isTotal: false),
              const _SubtotalRow(label: 'Service', amount: '£9.34', isTotal: false),
              const _SubtotalRow(label: 'Total', amount: '£84.09', isTotal: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineItem {
  const _LineItem(this.name, this.qty, this.price);
  final String name;
  final int qty;
  final String price;
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final _LineItem item;

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
            child: Row(
              children: [
                Text(
                  item.name,
                  style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink),
                ),
                const SizedBox(width: 6),
                Text(
                  '×${item.qty}',
                  style: MrCarsonType.ui(size: 13, color: MrCarsonColors.ink3),
                ),
              ],
            ),
          ),
          Text(
            item.price,
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
