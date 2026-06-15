import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../settings/currency_provider.dart';
import '../shell/shell_view_model.dart';

/// Manual Entry — the always-on, no-model path for recording an expense by
/// hand. Mirrors the design's MANUAL ENTRY screen
/// (`designs/mr-carson/project/Mr Carson.dc.html`, 667-771).
///
/// Fidelity note: this app is a high-fidelity prototype — the Ledger renders
/// hardcoded mock data and is NOT a DB-reactive list. Save therefore does not
/// persist; it shows the butler toast and returns to the Ledger, matching the
/// design prototype exactly. No DB write is performed here by design.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

/// One editable line item ("particular").
class _ManualItem {
  String name = '';
  String qty = '1';
  String price = '';

  double get lineTotal {
    final q = double.tryParse(qty.trim()) ?? 0;
    final p = double.tryParse(price.trim()) ?? 0;
    return q * p;
  }
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _merchant = '';
  String _amount = '';
  String _selectedCategory = '';
  bool _particularsOpen = false;
  final List<_ManualItem> _items = [];

  static const _categories = [
    'Dining',
    'Groceries',
    'Household',
    'Transport',
    'Other',
  ];

  /// Category → accent color, matching the Ledger / Confirm idiom.
  static Color _categoryColor(String category) {
    switch (category) {
      case 'Dining':
        return MrCarsonColors.accent;
      case 'Groceries':
        return MrCarsonColors.grocery;
      case 'Household':
        return MrCarsonColors.house;
      case 'Transport':
        return MrCarsonColors.transport;
      default:
        return MrCarsonColors.ink3;
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // --- derived state -------------------------------------------------------

  double get _itemsSubtotal =>
      _items.fold<double>(0, (sum, it) => sum + it.lineTotal);

  /// The effective amount used for the Save gate: subtotal when particulars are
  /// open, otherwise the typed amount.
  double get _effectiveAmount {
    if (_particularsOpen) return _itemsSubtotal;
    return double.tryParse(_amount.trim()) ?? 0;
  }

  bool get _canSave => _merchant.trim().isNotEmpty && _effectiveAmount > 0;

  // --- particulars ---------------------------------------------------------

  void _openParticulars() {
    setState(() {
      _particularsOpen = true;
      if (_items.isEmpty) _items.add(_ManualItem());
    });
  }

  void _closeParticulars() {
    setState(() {
      _particularsOpen = false;
      _items.clear();
    });
  }

  void _addItem() => setState(() => _items.add(_ManualItem()));

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      if (_items.isEmpty) _items.add(_ManualItem());
    });
  }

  // --- footer actions ------------------------------------------------------

  void _cancel() =>
      ref.read(shellViewModelProvider.notifier).go(ShellScreen.ledger);

  void _save() {
    if (!_canSave) return;
    ref.read(shellViewModelProvider.notifier)
      ..showToast('Very good, sir.')
      ..go(ShellScreen.ledger);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final subtotalDisplay = '$currency${_itemsSubtotal.toStringAsFixed(2)}';

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _ManualHeader(onCancel: _cancel),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ManualNoteCard(),
                      const SizedBox(height: 18),
                      _MerchantField(
                        controller: _merchantController,
                        onChanged: (v) => setState(() => _merchant = v),
                      ),
                      const SizedBox(height: 13),
                      _AmountDateRow(
                        currency: currency,
                        amountController: _amountController,
                        onAmountChanged: (v) => setState(() => _amount = v),
                        particularsOpen: _particularsOpen,
                        subtotalDisplay: subtotalDisplay,
                      ),
                      const SizedBox(height: 13),
                      _CategoryField(
                        categories: _categories,
                        selected: _selectedCategory,
                        colorFor: _categoryColor,
                        onSelect: (c) => setState(() => _selectedCategory = c),
                      ),
                      const SizedBox(height: 13),
                      if (!_particularsOpen)
                        _AddParticularsButton(onTap: _openParticulars)
                      else
                        _ParticularsCard(
                          items: _items,
                          currency: currency,
                          subtotalDisplay: subtotalDisplay,
                          onClear: _closeParticulars,
                          onAddItem: _addItem,
                          onRemoveItem: _removeItem,
                          onChanged: () => setState(() {}),
                        ),
                      const SizedBox(height: 13),
                      _NoteField(controller: _noteController),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ManualFooter(
              canSave: _canSave,
              onCancel: _cancel,
              onSave: _save,
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

class _ManualHeader extends StatelessWidget {
  const _ManualHeader({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 58, 16, 12),
      decoration: const BoxDecoration(
        color: MrCarsonColors.bg,
        border: Border(bottom: BorderSide(color: MrCarsonColors.line, width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MrCarsonColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MrCarsonColors.line, width: 1),
              ),
              child: const Icon(Icons.close, color: MrCarsonColors.ink2, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('By hand',
                    style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
                Text('No download needed, sir',
                    style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3)),
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

class _ManualNoteCard extends StatelessWidget {
  const _ManualNoteCard();

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
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MrCarsonColors.accent, width: 1),
            ),
            alignment: Alignment.center,
            child: Text('C',
                style: MrCarsonType.display(size: 17, color: MrCarsonColors.accent)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              "The figures whenever you're ready, sir — I shall file them at once.",
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
// Field label helper + surface card wrapper
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

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MrCarsonColors.line, width: 1),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Merchant field
// ---------------------------------------------------------------------------

class _MerchantField extends StatelessWidget {
  const _MerchantField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('MERCHANT'),
          const SizedBox(height: 2),
          Text(
            'Where was this, sir?',
            style: MrCarsonType.display(
              size: 12,
              italic: true,
              color: MrCarsonColors.ink3,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            onChanged: onChanged,
            cursorColor: MrCarsonColors.accent,
            style: MrCarsonType.ui(size: 18, weight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'The establishment…',
              hintStyle: MrCarsonType.ui(
                size: 18,
                weight: FontWeight.w600,
                color: MrCarsonColors.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Amount + Date row
// ---------------------------------------------------------------------------

class _AmountDateRow extends StatelessWidget {
  const _AmountDateRow({
    required this.currency,
    required this.amountController,
    required this.onAmountChanged,
    required this.particularsOpen,
    required this.subtotalDisplay,
  });

  final String currency;
  final TextEditingController amountController;
  final ValueChanged<String> onAmountChanged;
  final bool particularsOpen;
  final String subtotalDisplay;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 14,
          child: _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('AMOUNT'),
                const SizedBox(height: 6),
                if (particularsOpen) ...[
                  Text(
                    subtotalDisplay,
                    style: MrCarsonType.display(size: 26, weight: FontWeight.w600, height: 1)
                        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: 4),
                  Text('reconciled from the particulars',
                      style: MrCarsonType.ui(size: 11, color: MrCarsonColors.accent)),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(currency,
                          style: MrCarsonType.display(
                              size: 26, weight: FontWeight.w600, color: MrCarsonColors.ink3)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          onChanged: onAmountChanged,
                          cursorColor: MrCarsonColors.accent,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: MrCarsonType.display(size: 26, weight: FontWeight.w600)
                              .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            hintText: '0.00',
                            hintStyle: MrCarsonType.display(
                              size: 26,
                              weight: FontWeight.w600,
                              color: MrCarsonColors.ink3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          flex: 10,
          child: _SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('DATE'),
                const SizedBox(height: 6),
                Text('Today',
                    style: MrCarsonType.ui(size: 15.5, weight: FontWeight.w600, height: 1.2)),
                const SizedBox(height: 3),
                Text('Today', style: MrCarsonType.ui(size: 11, color: MrCarsonColors.ink3)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category field
// ---------------------------------------------------------------------------

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.categories,
    required this.selected,
    required this.colorFor,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final Color Function(String) colorFor;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
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
                    color: colorFor(categories[i]),
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
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : MrCarsonColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? color : MrCarsonColors.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: isSelected ? color : MrCarsonColors.ink2,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line items (particulars)
// ---------------------------------------------------------------------------

class _AddParticularsButton extends StatelessWidget {
  const _AddParticularsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MrCarsonColors.line,
            width: 1.5,
            // Dashed look isn't a first-class Border; a solid hairline is the
            // closest faithful match within the design system's palette.
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, size: 16, color: MrCarsonColors.ink2),
            const SizedBox(width: 9),
            Text('Add the particulars',
                style: MrCarsonType.ui(
                    size: 14.5, weight: FontWeight.w600, color: MrCarsonColors.ink2)),
          ],
        ),
      ),
    );
  }
}

class _ParticularsCard extends StatelessWidget {
  const _ParticularsCard({
    required this.items,
    required this.currency,
    required this.subtotalDisplay,
    required this.onClear,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onChanged,
  });

  final List<_ManualItem> items;
  final String currency;
  final String subtotalDisplay;
  final VoidCallback onClear;
  final VoidCallback onAddItem;
  final void Function(int) onRemoveItem;
  final VoidCallback onChanged;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                _fieldLabel('THE PARTICULARS'),
                const Spacer(),
                GestureDetector(
                  onTap: onClear,
                  child: Text('Clear',
                      style: MrCarsonType.ui(
                          size: 12.5, weight: FontWeight.w600, color: MrCarsonColors.ink3)),
                ),
              ],
            ),
          ),
          for (int i = 0; i < items.length; i++)
            _ItemRow(
              key: ObjectKey(items[i]),
              item: items[i],
              currency: currency,
              onChanged: onChanged,
              onRemove: () => onRemoveItem(i),
            ),
          GestureDetector(
            onTap: onAddItem,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 14, color: MrCarsonColors.accent),
                  const SizedBox(width: 8),
                  Text('Add another',
                      style: MrCarsonType.ui(
                          size: 14, weight: FontWeight.w600, color: MrCarsonColors.accent)),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              color: MrCarsonColors.bg,
              border: Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
            ),
            child: Row(
              children: [
                Text('Subtotal',
                    style: MrCarsonType.ui(size: 14, weight: FontWeight.w600)),
                const Spacer(),
                Text(
                  subtotalDisplay,
                  style: MrCarsonType.ui(
                    size: 16,
                    weight: FontWeight.w700,
                    color: MrCarsonColors.accent,
                  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.currency,
    required this.onChanged,
    required this.onRemove,
  });

  final _ManualItem item;
  final String currency;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _qty = TextEditingController(text: widget.item.qty);
    _price = TextEditingController(text: widget.item.price);
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _name,
              cursorColor: MrCarsonColors.accent,
              style: MrCarsonType.ui(size: 15),
              onChanged: (v) {
                widget.item.name = v;
                widget.onChanged();
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: 'Item',
                hintStyle: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('×', style: TextStyle(fontSize: 13, color: MrCarsonColors.ink3)),
          const SizedBox(width: 4),
          SizedBox(
            width: 26,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.center,
              cursorColor: MrCarsonColors.accent,
              keyboardType: TextInputType.number,
              style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink2),
              onChanged: (v) {
                widget.item.qty = v;
                widget.onChanged();
              },
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(widget.currency,
              style: MrCarsonType.ui(size: 14, color: MrCarsonColors.ink3)),
          const SizedBox(width: 2),
          SizedBox(
            width: 58,
            child: TextField(
              controller: _price,
              textAlign: TextAlign.right,
              cursorColor: MrCarsonColors.accent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: MrCarsonType.ui(size: 15, weight: FontWeight.w600)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              onChanged: (v) {
                widget.item.price = v;
                widget.onChanged();
              },
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink3),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: widget.onRemove,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: Icon(Icons.close, size: 12, color: MrCarsonColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note field
// ---------------------------------------------------------------------------

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _fieldLabel('NOTE'),
              const SizedBox(width: 5),
              Text('· optional',
                  style: MrCarsonType.ui(size: 11, color: MrCarsonColors.ink3)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            cursorColor: MrCarsonColors.accent,
            style: MrCarsonType.ui(size: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'A word, if you like…',
              hintStyle: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _ManualFooter extends StatelessWidget {
  const _ManualFooter({
    required this.canSave,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MrCarsonColors.bg.withAlpha(0), MrCarsonColors.bg],
          stops: const [0.0, 0.3],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: onCancel,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: MrCarsonColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MrCarsonColors.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Text('Cancel',
                    style: MrCarsonType.ui(
                        size: 16, weight: FontWeight.w600, color: MrCarsonColors.ink2)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: canSave ? onSave : null,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  // Disabled styling (design manualSaveBg/Color/Cursor).
                  color: canSave ? MrCarsonColors.accent : MrCarsonColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Save expense',
                  style: MrCarsonType.ui(
                    size: 16,
                    weight: FontWeight.w600,
                    color: canSave ? MrCarsonColors.accentInk : MrCarsonColors.ink3,
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
