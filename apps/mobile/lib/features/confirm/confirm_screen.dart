import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';

import '../../data/providers.dart';
import '../../domain/models/ai_models.dart';
import '../shell/shell_view_model.dart';

// ---------------------------------------------------------------------------
// Provider: load draft from pending row's extractedJson
// ---------------------------------------------------------------------------

/// Loads the [ExpenseDraft] stored in the pending row for [pendingId].
/// Returns null if the row is missing or the JSON cannot be parsed.
final pendingDraftProvider =
    FutureProvider.autoDispose.family<ExpenseDraft?, String>(
        (ref, pendingId) async {
  final repo = ref.read(pendingRepositoryProvider);
  final row = await repo.getById(pendingId);
  final json = row?.extractedJson;
  if (json == null) return null;
  return ExpenseDraft.fromJson(jsonDecode(json) as Map<String, dynamic>);
});

// ---------------------------------------------------------------------------
// Public screen
// ---------------------------------------------------------------------------

class ConfirmScreen extends ConsumerStatefulWidget {
  const ConfirmScreen({
    super.key,
    required this.pendingId,
    this.note = 'I read this while you were away, sir. Two figures want a glance.',
  });

  final String pendingId;
  final String note;

  @override
  ConsumerState<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends ConsumerState<ConfirmScreen> {
  // Editable state — populated once the draft loads
  ExpenseDraft? _draft;
  bool _loaded = false;

  // Merchant field state
  late String _merchant;
  bool _merchantLowConfidence = false;
  bool _merchantEditing = false;
  late TextEditingController _merchantController;

  // Category state — an expense may carry several tags.
  final Set<String> _selectedCategories = {};

  // Total editing
  late double _total;
  bool _totalEditing = false;
  late TextEditingController _totalController;

  // Line items
  late List<ExpenseItemDraft> _items;

  @override
  void dispose() {
    if (_loaded) {
      _merchantController.dispose();
      _totalController.dispose();
    }
    super.dispose();
  }

  void _initFromDraft(ExpenseDraft draft) {
    if (_loaded) return;
    _loaded = true;
    _draft = draft;
    _merchant = draft.merchant;
    _merchantLowConfidence = false;
    _merchantController = TextEditingController(text: _merchant);
    // Seed tags from the draft's expense-level categories, else the distinct
    // line-item categories, else the first default.
    _selectedCategories
      ..clear()
      ..addAll((draft.categories != null && draft.categories!.isNotEmpty)
          ? draft.categories!
          : (draft.items.isNotEmpty
              ? draft.items.map((i) => i.category).toSet()
              : {kDefaultCategories.first}));
    _total = draft.total;
    _totalController =
        TextEditingController(text: draft.total.toStringAsFixed(2));
    _items = List.from(draft.items);
  }

  ExpenseDraft _buildEditedDraft() {
    // Tags persist via the expense-level `categories` column; line items keep
    // their own extracted categories.
    return _draft!.copyWith(
      merchant: _merchant,
      total: _total,
      items: _items,
      categories: _selectedCategories.toList(),
    );
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

  void _commitTotalEdit() {
    final parsed = double.tryParse(_totalController.text.trim());
    setState(() {
      if (parsed != null) _total = parsed;
      _totalEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(pendingDraftProvider(widget.pendingId));
    final vm = ref.read(shellViewModelProvider.notifier);

    return draftAsync.when(
      loading: () => const Scaffold(
        backgroundColor: MrCarsonColors.bg,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: MrCarsonColors.bg,
        body: Center(
          child: Text('Could not load receipt, sir.',
              style: MrCarsonType.ui(size: 16, color: MrCarsonColors.ink2)),
        ),
      ),
      data: (draft) {
        if (draft == null) {
          return Scaffold(
            backgroundColor: MrCarsonColors.bg,
            body: Center(
              child: Text('Receipt not found, sir.',
                  style: MrCarsonType.ui(size: 16, color: MrCarsonColors.ink2)),
            ),
          );
        }
        _initFromDraft(draft);
        return _buildScaffold(vm);
      },
    );
  }

  Widget _buildScaffold(ShellViewModel vm) {
    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _TopBar(
                merchant: _merchant,
                onDiscard: () => vm.discardConfirm(widget.pendingId),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 130),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CarsonNoteCard(note: widget.note),
                      const SizedBox(height: 20),
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
                      _DateTotalRow(
                        date: _draft!.date,
                        currency: _draft!.currency,
                        total: _total,
                        totalEditing: _totalEditing,
                        totalController: _totalController,
                        onTapTotal: () {
                          setState(() {
                            _totalEditing = true;
                            _totalController.selection =
                                TextSelection.fromPosition(TextPosition(
                                    offset: _totalController.text.length));
                          });
                        },
                        onCommitTotal: _commitTotalEdit,
                      ),
                      const SizedBox(height: 13),
                      _CategoryCard(
                        categories: kDefaultCategories,
                        selected: _selectedCategories,
                        onToggle: (cat) => setState(() {
                          if (!_selectedCategories.remove(cat)) {
                            _selectedCategories.add(cat);
                          }
                        }),
                      ),
                      const SizedBox(height: 13),
                      _LineItemsCard(items: _items),
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
            child: _Footer(
              onDiscard: () => vm.discardConfirm(widget.pendingId),
              onSave: () =>
                  vm.saveConfirm(widget.pendingId, _buildEditedDraft()),
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
  const _TopBar({required this.merchant, required this.onDiscard});

  final String merchant;
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
              child: const Icon(Icons.close, color: MrCarsonColors.ink2, size: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Review expense',
                    style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
                Text(
                  '$merchant · just now',
                  style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
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
          const CarsonMonogram(size: 30, filled: true),
          const SizedBox(width: 11),
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
    final borderColor = lowConfidence ? MrCarsonColors.warn : MrCarsonColors.line;
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
                  borderSide: BorderSide(color: MrCarsonColors.accent, width: 1.5),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: MrCarsonColors.accent, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onCommit(),
              textInputAction: TextInputAction.done,
            )
          else
            GestureDetector(
              onTap: onTapValue,
              child: Text(merchant,
                  style: MrCarsonType.ui(size: 18, weight: FontWeight.w600)),
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
          Text('Needs a look',
              style: MrCarsonType.ui(size: 11, color: MrCarsonColors.warn)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date + Total row
// ---------------------------------------------------------------------------

class _DateTotalRow extends StatelessWidget {
  const _DateTotalRow({
    required this.date,
    required this.currency,
    required this.total,
    required this.totalEditing,
    required this.totalController,
    required this.onTapTotal,
    required this.onCommitTotal,
  });

  final String date;
  final String currency;
  final double total;
  final bool totalEditing;
  final TextEditingController totalController;
  final VoidCallback onTapTotal;
  final VoidCallback onCommitTotal;

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

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
                Text(_formatDate(date),
                    style: MrCarsonType.ui(size: 15.5, weight: FontWeight.w600)),
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
                if (totalEditing)
                  TextField(
                    controller: totalController,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: MrCarsonType.display(
                            size: 26, weight: FontWeight.w600)
                        .copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    cursorColor: MrCarsonColors.accent,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: MrCarsonColors.accent, width: 1.5),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: MrCarsonColors.accent, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => onCommitTotal(),
                    textInputAction: TextInputAction.done,
                  )
                else
                  GestureDetector(
                    onTap: onTapTotal,
                    child: Text(
                      '$currency ${total.toStringAsFixed(2)}',
                      style: MrCarsonType.display(
                              size: 26, weight: FontWeight.w600)
                          .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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
    required this.onToggle,
  });

  final List<String> categories;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? MrCarsonColors.accent : MrCarsonColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? MrCarsonColors.accent : MrCarsonColors.line,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkbox tick — filled when selected.
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: isSelected
                    ? MrCarsonColors.accentInk.withAlpha(38)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? MrCarsonColors.accentInk
                      : MrCarsonColors.ink3,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: isSelected
                  ? const Icon(Icons.check,
                      size: 10, color: MrCarsonColors.accentInk)
                  : null,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: MrCarsonType.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color:
                    isSelected ? MrCarsonColors.accentInk : MrCarsonColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line items card
// ---------------------------------------------------------------------------

class _LineItemsCard extends StatelessWidget {
  const _LineItemsCard({required this.items});

  final List<ExpenseItemDraft> items;

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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: _fieldLabel('LINE ITEMS'),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Text('No line items, sir.',
                  style: MrCarsonType.ui(size: 14, color: MrCarsonColors.ink3)),
            )
          else
            for (final item in items) _ItemRow(item: item),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final ExpenseItemDraft item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MrCarsonColors.line, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(item.name,
                style: MrCarsonType.ui(size: 15, color: MrCarsonColors.ink)),
          ),
          Text(
            item.amount.toStringAsFixed(2),
            style: MrCarsonType.ui(
              size: 15,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
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
          colors: [MrCarsonColors.bg.withAlpha(0), MrCarsonColors.bg],
          stops: const [0.0, 0.35],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      child: Row(
        children: [
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
                child: Text('Discard',
                    style: MrCarsonType.ui(
                        size: 16,
                        weight: FontWeight.w600,
                        color: MrCarsonColors.ink2)),
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                child: Text('Save expense',
                    style: MrCarsonType.ui(
                        size: 16,
                        weight: FontWeight.w600,
                        color: MrCarsonColors.accentInk)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
