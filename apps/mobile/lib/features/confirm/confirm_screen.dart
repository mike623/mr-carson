import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mr_carson/ai/receipt_pipeline.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/receipt_image_store.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/theme/app_theme.dart';
import 'package:mr_carson/ui/core/widgets/carson_monogram.dart';
import 'package:mr_carson/ui/core/widgets/error_retry_state.dart';
import 'package:mr_carson/ui/core/widgets/loading_state.dart';

/// AI-extraction review screen for a single pending receipt.
///
/// Provider-driven: loads the real [ExpenseDraft] for [pendingId] from the
/// pending row's `extractedJson` (streamed via [pendingReceiptByIdProvider]),
/// pre-fills editable fields, and on confirm calls
/// [ReceiptPipelineService.commitConfirmed]; on discard calls
/// [ReceiptPipelineService.reject] (and cleans up the stored image). Returns
/// control to the shell via [onDone]/[onDiscarded].
class ConfirmScreen extends ConsumerWidget {
  const ConfirmScreen({
    super.key,
    required this.pendingId,
    required this.onDone,
    required this.onDiscarded,
    this.note =
        'I read this while you were away, sir. Two figures want a glance.',
  });

  /// The pending receipt being reviewed.
  final String pendingId;

  /// Called after a successful commit.
  final VoidCallback onDone;

  /// Called after the receipt is discarded (rejected).
  final VoidCallback onDiscarded;

  final String note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPending = ref.watch(pendingReceiptByIdProvider(pendingId));

    return Scaffold(
      backgroundColor: MrCarsonColors.bg,
      body: asyncPending.when(
        loading: () => Column(
          children: [
            _TopBar(subtitle: 'just now', onClose: onDiscarded),
            const Expanded(
              child: LoadingState(label: 'Fetching the receipt…'),
            ),
          ],
        ),
        error: (e, _) => Column(
          children: [
            _TopBar(subtitle: 'error', onClose: onDiscarded),
            Expanded(
              child: ErrorRetryState(
                title: 'I could not load this receipt',
                message: '$e',
                retryLabel: 'Go back',
                onRetry: onDiscarded,
              ),
            ),
          ],
        ),
        data: (pending) {
          // Not ready yet, gone (committed/rejected elsewhere), or extraction
          // failed — there is no editable draft to show.
          if (pending == null) {
            return Column(
              children: [
                _TopBar(subtitle: 'just now', onClose: onDiscarded),
                Expanded(
                  child: ErrorRetryState(
                    title: 'Nothing to review',
                    message:
                        'This receipt is no longer awaiting your confirmation.',
                    retryLabel: 'Back to the ledger',
                    onRetry: onDiscarded,
                  ),
                ),
              ],
            );
          }

          if (pending.status != PendingStatus.awaitingConfirmation.name) {
            // Still processing, or it failed.
            final failed = pending.status == PendingStatus.failed.name;
            return Column(
              children: [
                _TopBar(subtitle: 'just now', onClose: onDiscarded),
                Expanded(
                  child: failed
                      ? ErrorRetryState(
                          title: 'I struggled with this one',
                          message: pending.errorMessage ??
                              'The receipt could not be read.',
                          retryLabel: 'Discard',
                          onRetry: () => _discard(ref, pending.filePath),
                        )
                      : const LoadingState(label: 'Reading the receipt…'),
                ),
              ],
            );
          }

          final draft = _parseDraft(pending.extractedJson);
          if (draft == null) {
            return Column(
              children: [
                _TopBar(subtitle: 'just now', onClose: onDiscarded),
                Expanded(
                  child: ErrorRetryState(
                    title: 'The extraction looks empty',
                    message: 'I could not read structured figures from this '
                        'receipt, sir.',
                    retryLabel: 'Discard',
                    onRetry: () => _discard(ref, pending.filePath),
                  ),
                ),
              ],
            );
          }

          return _ConfirmForm(
            pendingId: pendingId,
            filePath: pending.filePath,
            draft: draft,
            note: note,
            onDone: onDone,
            onDiscarded: onDiscarded,
          );
        },
      ),
    );
  }

  ExpenseDraft? _parseDraft(String? extractedJson) {
    if (extractedJson == null || extractedJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(extractedJson);
      if (decoded is! Map<String, dynamic>) return null;
      return ExpenseDraft.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _discard(WidgetRef ref, String? filePath) async {
    // Capture references before awaiting — rejecting rebuilds this screen.
    final pipeline = ref.read(receiptPipelineProvider);
    final store = ref.read(receiptImageStoreProvider);
    await pipeline.reject(pendingId);
    if (filePath != null) {
      await store.cleanup(filePath);
    }
    onDiscarded();
  }
}

// ---------------------------------------------------------------------------
// Editable form
// ---------------------------------------------------------------------------

/// The editable review form, seeded from a real [ExpenseDraft].
class _ConfirmForm extends ConsumerStatefulWidget {
  const _ConfirmForm({
    required this.pendingId,
    required this.filePath,
    required this.draft,
    required this.note,
    required this.onDone,
    required this.onDiscarded,
  });

  final String pendingId;
  final String? filePath;
  final ExpenseDraft draft;
  final String note;
  final VoidCallback onDone;
  final VoidCallback onDiscarded;

  @override
  ConsumerState<_ConfirmForm> createState() => _ConfirmFormState();
}

class _ConfirmFormState extends ConsumerState<_ConfirmForm> {
  late String _merchant;
  bool _merchantLowConfidence = false;
  bool _merchantEditing = false;
  late final TextEditingController _merchantController;

  late String _selectedCategory;
  late List<ExpenseItemDraft> _items;
  late double _total;
  bool _saving = false;

  /// Category options — the shared taxonomy, ensuring the draft's own category
  /// is always selectable even if it falls outside the defaults.
  late final List<String> _categories;

  @override
  void initState() {
    super.initState();
    _merchant = widget.draft.merchant;
    _merchantLowConfidence = _merchant.trim().isEmpty;
    _merchantController = TextEditingController(text: _merchant);

    _items = List<ExpenseItemDraft>.from(widget.draft.items);
    _total = widget.draft.total;

    // The dominant item category, falling back to the first taxonomy entry.
    _selectedCategory = _items.isNotEmpty
        ? _items.first.category
        : (kDefaultCategories.isNotEmpty ? kDefaultCategories.first : 'Other');

    _categories = <String>{
      _selectedCategory,
      ...kDefaultCategories,
    }.toList();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  void _commitMerchantEdit() {
    setState(() {
      final trimmed = _merchantController.text.trim();
      _merchant = trimmed.isEmpty ? _merchant : trimmed;
      _merchantLowConfidence = false;
      _merchantEditing = false;
    });
  }

  /// Builds the edited [ExpenseDraft] from current field state. The selected
  /// category is applied to every line item (single-category review surface).
  ExpenseDraft _editedDraft() {
    return widget.draft.copyWith(
      merchant: _merchant,
      total: _total,
      items: [
        for (final item in _items) item.copyWith(category: _selectedCategory),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(receiptPipelineProvider)
          .commitConfirmed(widget.pendingId, _editedDraft());
      widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('I could not save that, sir. $e')),
        );
      }
    }
  }

  Future<void> _discard() async {
    if (_saving) return;
    setState(() => _saving = true);
    // Capture provider references up-front: rejecting the receipt makes it leave
    // the active stream, which rebuilds (and may unmount) this widget — after
    // which `ref.read` would throw.
    final pipeline = ref.read(receiptPipelineProvider);
    final store = ref.read(receiptImageStoreProvider);
    final onDiscarded = widget.onDiscarded;
    final filePath = widget.filePath;

    await pipeline.reject(widget.pendingId);
    if (filePath != null) {
      await store.cleanup(filePath);
    }
    onDiscarded();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _TopBar(subtitle: _merchant, onClose: _discard),
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
                      date: widget.draft.date,
                      currency: widget.draft.currency,
                      total: _total,
                    ),
                    const SizedBox(height: 13),
                    _CategoryCard(
                      categories: _categories,
                      selected: _selectedCategory,
                      onSelect: (cat) =>
                          setState(() => _selectedCategory = cat),
                    ),
                    const SizedBox(height: 13),
                    _LineItemsCard(
                      items: _items,
                      currency: widget.draft.currency,
                    ),
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
            saving: _saving,
            onDiscard: _discard,
            onSave: _save,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

/// A small set of common currency symbols; falls back to the ISO code + space.
String _currencyPrefix(String currency) {
  switch (currency.toUpperCase()) {
    case 'GBP':
      return '£';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    default:
      return '$currency ';
  }
}

String _money(String currency, double amount) =>
    '${_currencyPrefix(currency)}${amount.toStringAsFixed(2)}';

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.subtitle, required this.onClose});

  final String subtitle;
  final VoidCallback onClose;

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
            onTap: onClose,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review expense',
                  style: MrCarsonType.ui(size: 16, weight: FontWeight.w600),
                ),
                Text(
                  subtitle.trim().isEmpty ? 'just now' : subtitle,
                  style: MrCarsonType.ui(
                    size: 12,
                    color: MrCarsonColors.ink3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                merchant.trim().isEmpty ? 'Unknown merchant' : merchant,
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
  const _DateTotalRow({
    required this.date,
    required this.currency,
    required this.total,
  });

  final String date;
  final String currency;
  final double total;

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
                  date.trim().isEmpty ? '—' : date,
                  style: MrCarsonType.ui(size: 15.5, weight: FontWeight.w600),
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
                  _money(currency, total),
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
  const _LineItemsCard({required this.items, required this.currency});

  final List<ExpenseItemDraft> items;
  final String currency;

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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                'No line items were read.',
                style: MrCarsonType.ui(size: 13.5, color: MrCarsonColors.ink3),
              ),
            )
          else
            for (final item in items)
              _ConfirmItemRow(item: item, currency: currency),
        ],
      ),
    );
  }
}

class _ConfirmItemRow extends StatelessWidget {
  const _ConfirmItemRow({required this.item, required this.currency});

  final ExpenseItemDraft item;
  final String currency;

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
          Text(
            _money(currency, item.amount),
            style: MrCarsonType.ui(
              size: 15,
              weight: FontWeight.w600,
              color: MrCarsonColors.ink,
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
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

class _Footer extends StatelessWidget {
  const _Footer({
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  final bool saving;
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
          Expanded(
            flex: 1,
            child: GestureDetector(
              onTap: saving ? null : onDiscard,
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
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: saving ? null : onSave,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: MrCarsonColors.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor:
                              AlwaysStoppedAnimation(MrCarsonColors.accentInk),
                        ),
                      )
                    : Text(
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
