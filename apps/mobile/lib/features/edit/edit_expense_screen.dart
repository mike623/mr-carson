import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../theme/app_theme.dart';
import '../../ui/core/utils/app_date.dart';
import '../../ui/core/utils/currency_format.dart';
import '../../ui/core/widgets/carson_monogram.dart';
import '../../ui/core/widgets/empty_state.dart';
import '../../ui/core/widgets/error_retry_state.dart';
import '../../ui/core/widgets/loading_state.dart';
import '../shell/shell_view_model.dart';

/// Edit Expense — amend an existing committed expense's merchant, amount, date,
/// categories, and line items ("the particulars"). Mirrors the design's EDIT
/// EXPENSE screen (`designs/mr-carson/project/Mr Carson.dc.html`).
///
/// When the expense carries line items the Amount becomes a computed total,
/// totted up from the particulars; with no items it stays a free-form amount
/// input. Save persists via [AppDatabase.updateExpense]; the DB-reactive
/// detail/ledger streams reflect the change immediately.
///
/// ponytail: the design's optional "note" field is omitted — there is no note
/// column on the expenses table, so the input would not persist. Add the field
/// once a column exists.
class EditExpenseScreen extends ConsumerStatefulWidget {
  const EditExpenseScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  final _merchantController = TextEditingController();
  final _amountController = TextEditingController();

  String _merchant = '';
  String _amount = '';
  String _date = '';
  final Set<String> _selectedCategories = {};
  final List<_EditItem> _items = [];
  bool _initialized = false;

  static const _categories = [
    'Dining',
    'Groceries',
    'Household',
    'Transport',
    'Other',
  ];

  /// Category → accent color, matching the Ledger / Confirm / Manual idiom.
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
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, _date);
    if (picked != null) setState(() => _date = picked);
  }

  // --- derived state --------------------------------------------------------

  bool get _hasItems => _items.isNotEmpty;

  // ponytail: no service column; total = sum(items)
  double get _itemsTotal =>
      _items.fold<double>(0, (sum, it) => sum + it.amount);

  bool get _canSave {
    if (_merchant.trim().isEmpty) return false;
    if (_hasItems) {
      final named = _items.any((it) => it.name.trim().isNotEmpty);
      return named && _itemsTotal > 0;
    }
    return (double.tryParse(_amount.trim()) ?? 0) > 0;
  }

  // --- particulars ----------------------------------------------------------

  void _itemise() => setState(() {
        if (_items.isEmpty) _items.add(_EditItem());
      });

  void _addItem() => setState(() => _items.add(_EditItem()));

  void _removeItem(int index) => setState(() => _items.removeAt(index));

  void _cancel() =>
      ref.read(shellViewModelProvider.notifier).go(ShellScreen.detail);

  Future<void> _save() async {
    if (!_canSave) return;
    final notifier = ref.read(shellViewModelProvider.notifier);
    final cats =
        _selectedCategories.isEmpty ? ['Other'] : _selectedCategories.toList();
    try {
      if (_hasItems) {
        // New rows inherit the expense's first selected category; prefilled
        // rows keep the category they were filed under.
        final fallbackCategory = cats.first;
        final items = _items
            .where((it) => it.name.trim().isNotEmpty)
            .map((it) => (
                  name: it.name.trim(),
                  category: it.category ?? fallbackCategory,
                  amount: it.amount,
                ))
            .toList();
        final total = items.fold<double>(0, (sum, it) => sum + it.amount);
        await ref.read(appDatabaseProvider).updateExpense(
              widget.id,
              merchant: _merchant.trim(),
              total: total,
              date: _date.trim(),
              categories: cats,
              items: items,
            );
      } else {
        final total = double.tryParse(_amount.trim()) ?? 0;
        await ref.read(appDatabaseProvider).updateExpense(
              widget.id,
              merchant: _merchant.trim(),
              total: total,
              date: _date.trim(),
              categories: cats,
            );
      }
      notifier
        ..go(ShellScreen.detail)
        ..showToast('Amended. Very good, sir.');
    } catch (_) {
      notifier.showToast('Could not save those changes, sir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(expenseDetailProvider(widget.id));

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: detailAsync.when(
        loading: () => const LoadingState(message: 'Fetching the expense, sir.'),
        error: (e, _) => ErrorRetryState(
          message: 'I could not load that expense, sir.',
          onRetry: () => ref.invalidate(expenseDetailProvider(widget.id)),
        ),
        data: (detail) {
          if (detail == null) {
            return const EmptyState(
              title: 'Nothing found, sir.',
              body: 'That expense does not appear to be in the ledger.',
              icon: Icons.receipt_long_outlined,
            );
          }
          // Prefill once from the loaded expense.
          if (!_initialized) {
            _initialized = true;
            _merchant = detail.merchant;
            _amount = formatAmount(detail.total);
            _date = detail.date;
            _merchantController.text = _merchant;
            _amountController.text = _amount;
            _selectedCategories
              ..clear()
              ..addAll(detail.categories);
            _items
              ..clear()
              ..addAll(detail.items.map((it) => _EditItem(
                    name: it.name,
                    price: formatAmount(it.amount),
                    category: it.category,
                  )));
          }
          final currency = currencySymbol(detail.currency);
          final hasItems = _hasItems;
          final totalDisplay = '$currency${formatAmount(_itemsTotal)}';

          return Stack(
            children: [
              Column(
                children: [
                  _EditHeader(subtitle: _merchant.isEmpty ? 'This expense' : _merchant, onCancel: _cancel),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _CarsonNoteCard(),
                          const SizedBox(height: 18),
                          _MerchantField(
                            controller: _merchantController,
                            onChanged: (v) => setState(() => _merchant = v),
                          ),
                          const SizedBox(height: 13),
                          _AmountDateRow(
                            currency: currency,
                            amountController: _amountController,
                            dateIso: _date,
                            onAmountChanged: (v) => setState(() => _amount = v),
                            onPickDate: _pickDate,
                            hasItems: hasItems,
                            totalDisplay: totalDisplay,
                          ),
                          const SizedBox(height: 13),
                          _CategoryField(
                            categories: _categories,
                            selected: _selectedCategories,
                            colorFor: _categoryColor,
                            onToggle: (c) => setState(() {
                              if (!_selectedCategories.remove(c)) {
                                _selectedCategories.add(c);
                              }
                            }),
                          ),
                          const SizedBox(height: 13),
                          if (hasItems)
                            _ParticularsCard(
                              items: _items,
                              currency: currency,
                              totalDisplay: totalDisplay,
                              onAddItem: _addItem,
                              onRemoveItem: _removeItem,
                              onChanged: () => setState(() {}),
                            )
                          else
                            _ItemiseButton(onTap: _itemise),
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
                child: _EditFooter(
                  canSave: _canSave,
                  onCancel: _cancel,
                  onSave: _save,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _EditHeader extends StatelessWidget {
  const _EditHeader({required this.subtitle, required this.onCancel});

  final String subtitle;
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
                Text('Edit expense',
                    style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _CarsonNoteCard extends StatelessWidget {
  const _CarsonNoteCard();

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
          const CarsonMonogram(size: 30, borderWidth: 1),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              "Amend whatever you wish, sir — I shall re-file it the moment you're done.",
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
    required this.dateIso,
    required this.onAmountChanged,
    required this.onPickDate,
    required this.hasItems,
    required this.totalDisplay,
  });

  final String currency;
  final TextEditingController amountController;
  final String dateIso;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onPickDate;
  final bool hasItems;
  final String totalDisplay;

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
                if (hasItems) ...[
                  // With line items the amount is not editable — it is totted
                  // up from the particulars below.
                  Text(
                    totalDisplay,
                    style: MrCarsonType.display(
                            size: 26, weight: FontWeight.w600, height: 1)
                        .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: 4),
                  Text('Totted up from the particulars.',
                      style: MrCarsonType.ui(size: 11, color: MrCarsonColors.ink3)),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(currency,
                          style: MrCarsonType.display(
                              size: 26,
                              weight: FontWeight.w600,
                              color: MrCarsonColors.ink3)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          onChanged: onAmountChanged,
                          cursorColor: MrCarsonColors.accent,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: MrCarsonType.display(
                                  size: 26, weight: FontWeight.w600)
                              .copyWith(fontFeatures: const [
                            FontFeature.tabularFigures()
                          ]),
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
          child: GestureDetector(
            onTap: onPickDate,
            child: _SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('DATE'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatLongDate(dateIso),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MrCarsonType.ui(
                              size: 15.5, weight: FontWeight.w600, height: 1.2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.calendar_today_outlined,
                          size: 15, color: MrCarsonColors.ink3),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(relativeDateLabel(dateIso),
                      style:
                          MrCarsonType.ui(size: 11, color: MrCarsonColors.ink3)),
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
// Category field (multi-select chips)
// ---------------------------------------------------------------------------

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.categories,
    required this.selected,
    required this.colorFor,
    required this.onToggle,
  });

  final List<String> categories;
  final Set<String> selected;
  final Color Function(String) colorFor;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _fieldLabel('CATEGORY'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Choose as many as apply, sir',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MrCarsonType.display(
                    size: 12.5,
                    italic: true,
                    color: MrCarsonColors.ink3,
                  ),
                ),
              ),
            ],
          ),
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
                    isSelected: selected.contains(categories[i]),
                    onTap: () => onToggle(categories[i]),
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.18) : MrCarsonColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? color : MrCarsonColors.line,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: isSelected ? color.withValues(alpha: 0.30) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? color : MrCarsonColors.ink3,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: isSelected ? Icon(Icons.check, size: 10, color: color) : null,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: MrCarsonType.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: isSelected ? color : MrCarsonColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _EditFooter extends StatelessWidget {
  const _EditFooter({
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
                  color: canSave ? MrCarsonColors.accent : MrCarsonColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Save changes',
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

// ---------------------------------------------------------------------------
// Line items (particulars)
// ---------------------------------------------------------------------------

/// A single editable line item. `qty` is captured for display only — the
/// ExpenseItems schema has no qty column, so it is not persisted. `category` is
/// preserved from the filed row (null for freshly-added rows, which inherit the
/// expense's first category on save).
class _EditItem {
  _EditItem({this.name = '', this.price = '', this.category});

  String name;
  // ponytail: qty display-only, no ExpenseItems column to persist it
  String qty = '1';
  String price;
  String? category;

  double get amount => double.tryParse(price.trim()) ?? 0;
}

/// Dashed-look button shown when the expense has no line items — tapping it
/// starts the first particular and flips into items mode.
class _ItemiseButton extends StatelessWidget {
  const _ItemiseButton({required this.onTap});

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
            Text('Itemise the particulars',
                style: MrCarsonType.ui(
                    size: 14.5,
                    weight: FontWeight.w600,
                    color: MrCarsonColors.ink2)),
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
    required this.totalDisplay,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onChanged,
  });

  final List<_EditItem> items;
  final String currency;
  final String totalDisplay;
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
            child: _fieldLabel('THE PARTICULARS'),
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
                border:
                    Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 14, color: MrCarsonColors.accent),
                  const SizedBox(width: 8),
                  Text('Add another',
                      style: MrCarsonType.ui(
                          size: 14,
                          weight: FontWeight.w600,
                          color: MrCarsonColors.accent)),
                ],
              ),
            ),
          ),
          // ponytail: no service column; total = sum(items)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              color: MrCarsonColors.bg,
              border:
                  Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
            ),
            child: Row(
              children: [
                Text('Total',
                    style: MrCarsonType.ui(size: 14, weight: FontWeight.w600)),
                const Spacer(),
                Text(
                  totalDisplay,
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

  final _EditItem item;
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
          const Text('×',
              style: TextStyle(fontSize: 13, color: MrCarsonColors.ink3)),
          const SizedBox(width: 4),
          SizedBox(
            width: 26,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.center,
              cursorColor: MrCarsonColors.accent,
              keyboardType: TextInputType.number,
              // ponytail: qty display-only, no ExpenseItems column to persist it
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
