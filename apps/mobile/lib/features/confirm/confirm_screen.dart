import 'package:flutter/material.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

/// AI-extraction review screen where the user can confirm or discard a
/// newly processed receipt.
///
/// Provides locally editable state for merchant name confidence, category
/// selection, and line-item display. Calls [onDiscard] or [onSave] when
/// the user taps the footer buttons.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.onDiscard,
    required this.onSave,
    this.note =
        'I read this while you were away, sir. Two figures want a glance.',
  });

  final VoidCallback onDiscard;
  final VoidCallback onSave;
  final String note;

  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  // Merchant field state
  String _merchant = 'Caffè Nero';
  bool _merchantLowConfidence = true;
  bool _merchantEditing = false;
  late final TextEditingController _merchantController;

  // Category state
  String _selectedCategory = 'Dining';

  static const _categories = [
    'Dining',
    'Groceries',
    'Transport',
    'Household',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController(text: _merchant);
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  void _commitMerchantEdit() {
    setState(() {
      _merchant = _merchantController.text.trim().isEmpty
          ? _merchant
          : _merchantController.text.trim();
      _merchantLowConfidence = false;
      _merchantEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _TopBar(
                onDiscard: widget.onDiscard,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Carson note card
                      _CarsonNoteCard(note: widget.note),
                      const SizedBox(height: 20),
                      // Fields column
                      _MerchantField(
                        merchant: _merchant,
                        lowConfidence: _merchantLowConfidence,
                        editing: _merchantEditing,
                        controller: _merchantController,
                        onTapValue: () {
                          setState(() {
                            _merchantEditing = true;
                            _merchantController.selection =
                                TextSelection.fromPosition(
                              TextPosition(
                                  offset: _merchantController.text.length),
                            );
                          });
                        },
                        onCommit: _commitMerchantEdit,
                      ),
                      const SizedBox(height: 13),
                      const _DateTotalRow(),
                      const SizedBox(height: 13),
                      _CategoryCard(
                        categories: _categories,
                        selected: _selectedCategory,
                        onSelect: (cat) =>
                            setState(() => _selectedCategory = cat),
                      ),
                      const SizedBox(height: 13),
                      const _LineItemsCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Pinned footer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Footer(
              onDiscard: widget.onDiscard,
              onSave: widget.onSave,
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
  const _TopBar({required this.onDiscard});

  final VoidCallback onDiscard;

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
          // Close button
          GestureDetector(
            onTap: onDiscard,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              child: const Icon(
                Icons.close,
                color: MrCarsonColors.ink2,
                size: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review expense',
                  style:
                      MrCarsonType.ui(size: 16, weight: FontWeight.w600),
                ),
                Text(
                  'Caffè Nero · just now',
                  style: MrCarsonType.ui(
                    size: 12,
                    color: MrCarsonColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carson note card
// ---------------------------------------------------------------------------

class _CarsonNoteCard extends StatelessWidget {
  const _CarsonNoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "C" monogram circle
          const CarsonMonogram(size: 30, filled: true),
          const SizedBox(width: 11),
          // Note text
          Expanded(
            child: Text(
              note,
              style: MrCarsonType.display(
                size: 15.5,
                italic: true,
                color: MrCarsonColors.ink2,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Field label helper
// ---------------------------------------------------------------------------

Widget _fieldLabel(String text) {
  return Text(
    text,
    style: MrCarsonType.ui(
      size: 11,
      color: MrCarsonColors.ink3,
      letterSpacing: 0.8,
    ),
  );
}

// ---------------------------------------------------------------------------
// Merchant field
// ---------------------------------------------------------------------------

class _MerchantField extends StatelessWidget {
  const _MerchantField({
    required this.merchant,
    required this.lowConfidence,
    required this.editing,
    required this.controller,
    required this.onTapValue,
    required this.onCommit,
  });

  final String merchant;
  final bool lowConfidence;
  final bool editing;
  final TextEditingController controller;
  final VoidCallback onTapValue;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        lowConfidence ? MrCarsonColors.warn : MrCarsonColors.line;
    final borderWidth = lowConfidence ? 1.5 : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: label + optional badge
          Row(
            children: [
              _fieldLabel('MERCHANT'),
              if (lowConfidence) ...[
                const SizedBox(width: 8),
                const _NeedsLookBadge(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Merchant value or TextField
          if (editing)
            TextField(
              controller: controller,
              autofocus: true,
              style: MrCarsonType.ui(size: 18, weight: FontWeight.w600),
              cursorColor: MrCarsonColors.accent,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: MrCarsonColors.accent,
                    width: 1.5,
                  ),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: MrCarsonColors.accent,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => onCommit(),
              textInputAction: TextInputAction.done,
            )
          else
            GestureDetector(
              onTap: onTapValue,
              child: Text(
                merchant,
                style: MrCarsonType.ui(size: 18, weight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

class _NeedsLookBadge extends StatelessWidget {
  const _NeedsLookBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MrCarsonColors.warnSoft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: MrCarsonColors.warn,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Needs a look',
            style: MrCarsonType.ui(size: 11, color: MrCarsonColors.warn),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date + Total row
// ---------------------------------------------------------------------------

class _DateTotalRow extends StatelessWidget {
  const _DateTotalRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: MrCarsonColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MrCarsonColors.line, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('DATE'),
                const SizedBox(height: 8),
                Text(
                  '12 June 2026',
                  style:
                      MrCarsonType.ui(size: 15.5, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: MrCarsonColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MrCarsonColors.line, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('TOTAL'),
                const SizedBox(height: 8),
                Text(
                  '£6.15',
                  style: MrCarsonType.display(
                    size: 26,
                    weight: FontWeight.w600,
                  ).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category card
// ---------------------------------------------------------------------------

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('CATEGORY'),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < categories.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _CategoryChip(
                    label: categories[i],
                    isSelected: categories[i] == selected,
                    onTap: () => onSelect(categories[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? MrCarsonColors.accent : MrCarsonColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? MrCarsonColors.accent : MrCarsonColors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: isSelected ? MrCarsonColors.accentInk : MrCarsonColors.ink2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line items card
// ---------------------------------------------------------------------------

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard();

  static const _items = [
    _ConfirmItem('Cappuccino', '£3.20', false),
    _ConfirmItem('Almond Croissant', '£2.95', true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: _fieldLabel('LINE ITEMS'),
          ),
          for (final item in _items) _ConfirmItemRow(item: item),
        ],
      ),
    );
  }
}

class _ConfirmItem {
  const _ConfirmItem(this.name, this.price, this.lowConfidence);
  final String name;
  final String price;
  final bool lowConfidence;
}

class _ConfirmItemRow extends StatelessWidget {
  const _ConfirmItemRow({required this.item});

  final _ConfirmItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: MrCarsonColors.line, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink),
            ),
          ),
          if (item.lowConfidence) ...[
            const _CheckBadge(),
            const SizedBox(width: 6),
          ],
          Text(
            item.price,
            style: MrCarsonType.ui(
              size: 15,
              weight: FontWeight.w600,
              color: item.lowConfidence
                  ? MrCarsonColors.warn
                  : MrCarsonColors.ink,
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: MrCarsonColors.warnSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'check',
        style: MrCarsonType.ui(size: 10.5, color: MrCarsonColors.warn),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.onDiscard, required this.onSave});

  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MrCarsonColors.bg.withAlpha(0),
            MrCarsonColors.bg,
          ],
          stops: const [0.0, 0.35],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      child: Row(
        children: [
          // Discard button (flex 1)
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: onDiscard,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: MrCarsonColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MrCarsonColors.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Discard',
                  style: MrCarsonType.ui(
                    size: 16,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.ink2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Save button (flex 2)
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: onSave,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: MrCarsonColors.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Save expense',
                  style: MrCarsonType.ui(
                    size: 16,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.accentInk,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
