import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/receipt_pipeline.dart';
import '../../data/providers.dart';
import '../../data/receipt_image_store.dart';
import '../../domain/models/ai_models.dart';

// ---------------------------------------------------------------------------
// Picker seam — injectable so tests can supply a fake without platform calls
// ---------------------------------------------------------------------------

/// Signature for an image-picker call.
typedef ImagePickerFn = Future<XFile?> Function(ImageSource source);

/// Provider for the [ImagePickerFn] used by [ShellViewModel].
///
/// Override this in tests to supply a fake file path without invoking the
/// real platform picker.
final imagePickerFnProvider = Provider<ImagePickerFn>((_) {
  final picker = ImagePicker();
  return (source) => picker.pickImage(source: source);
});

// ---------------------------------------------------------------------------
// Screen enum
// ---------------------------------------------------------------------------

/// Which screen the shell is currently presenting.
enum ShellScreen {
  ask,
  ledger,
  detail,
  confirm,
  settings,
  modelMgmt,
  manual,
  engage,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable state for the in-app shell.
@immutable
class ShellState {
  const ShellState({
    this.screen = ShellScreen.ask,
    this.reviewingId,
    this.selectedExpenseId,
    this.toast,
    this.engageReason = '',
    this.askComposerFocused = false,
  });

  final ShellScreen screen;

  /// Whether the Ask composer's text field currently holds focus.
  final bool askComposerFocused;

  /// The pending id currently being reviewed on the confirm screen, if any.
  final String? reviewingId;

  /// The expense id currently open on the detail screen, if any.
  final String? selectedExpenseId;

  /// Active butler toast message, or null when none is shown.
  final String? toast;

  /// Contextual italic line shown in the Engage screen's reason card.
  final String engageReason;

  bool get navVisible =>
      (screen == ShellScreen.ask || screen == ShellScreen.ledger) &&
      !askComposerFocused;

  ShellState copyWith({
    ShellScreen? screen,
    Object? reviewingId = _unset,
    Object? selectedExpenseId = _unset,
    Object? toast = _unset,
    String? engageReason,
    bool? askComposerFocused,
  }) {
    return ShellState(
      screen: screen ?? this.screen,
      reviewingId:
          identical(reviewingId, _unset) ? this.reviewingId : reviewingId as String?,
      selectedExpenseId: identical(selectedExpenseId, _unset)
          ? this.selectedExpenseId
          : selectedExpenseId as String?,
      toast: identical(toast, _unset) ? this.toast : toast as String?,
      engageReason: engageReason ?? this.engageReason,
      askComposerFocused: askComposerFocused ?? this.askComposerFocused,
    );
  }

  static const _unset = Object();
}

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/// Drives the in-app shell: navigation, receipt capture/upload, and the
/// butler toast.
///
/// Pending state is driven off [pendingReceiptsProvider] (a DB stream) —
/// there is no in-memory pending list.
class ShellViewModel extends AutoDisposeNotifier<ShellState> {
  Timer? _toastTimer;

  @override
  ShellState build() {
    ref.onDispose(() => _toastTimer?.cancel());
    return const ShellState();
  }

  // --- navigation ----------------------------------------------------------

  void go(ShellScreen s) => state = state.copyWith(screen: s);

  /// Navigate to the detail screen for a specific expense id.
  void openExpense(String id) {
    state = state.copyWith(selectedExpenseId: id, screen: ShellScreen.detail);
  }

  void setAskComposerFocused(bool focused) {
    if (state.askComposerFocused == focused) return;
    state = state.copyWith(askComposerFocused: focused);
  }

  void requireModel({String reason = ''}) {
    state = state.copyWith(engageReason: reason, screen: ShellScreen.engage);
  }

  void showToast(String msg) {
    state = state.copyWith(toast: msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      state = state.copyWith(toast: null);
    });
  }

  /// Surfaces a receipt-processing failure. The on-device pipeline swallows the
  /// real cause into a generic toast; this keeps the butler line but appends the
  /// actual error so failures are diagnosable instead of silent.
  void _showReceiptError(String? error) {
    final e = error ?? '';
    // Most common cause: the lifecycle UI reached "ready" via the mock ramp
    // while the real Gemma engine never loaded — createVisionSession throws.
    if (e.contains('model is not loaded')) {
      showToast('The model is not ready yet, sir. Please finish setup.');
      return;
    }
    showToast(
      e.isEmpty
          ? 'I could not read that receipt, sir.'
          : 'I could not read that receipt, sir. ($e)',
    );
  }

  // --- add sheet outcomes --------------------------------------------------

  /// "Take a photograph" — pick via camera, copy, process.
  Future<void> capturePhoto() => _pickAndProcess(ImageSource.camera);

  /// "Upload from library" — pick via gallery, copy, process.
  Future<void> startUpload() => _pickAndProcess(ImageSource.gallery);

  // --- internal pick + process flow ----------------------------------------

  Future<void> _pickAndProcess(ImageSource source) async {
    final pick = ref.read(imagePickerFnProvider);
    XFile? file;
    try {
      file = await pick(source);
    } catch (_) {
      showToast('Could not access the image, sir.');
      return;
    }
    if (file == null) return; // user cancelled

    final store = ref.read(receiptImageStoreProvider);
    late final String stablePath;
    try {
      final copy = await store.copyReceipt(file.path);
      // Duplicate guard: if an expense with this exact image already exists,
      // skip OCR and drop the just-made copy. Only catches byte-identical
      // re-uploads against committed expenses — a re-photographed receipt has
      // different bytes and is caught later by soft-duplicate at confirm.
      final existing =
          await ref.read(appDatabaseProvider).findByImageHash(copy.imageHash);
      if (existing != null) {
        await store.deleteReceipt(copy.path);
        showToast('I already have that receipt, sir.');
        go(ShellScreen.ledger);
        return;
      }
      stablePath = copy.path;
    } catch (_) {
      showToast('Could not save the image, sir.');
      return;
    }

    // Navigate to ledger and show toast — processing runs in the background.
    // The pending card driven by pendingReceiptsProvider will appear; the user
    // opens ConfirmScreen by tapping its "Review" button.
    showToast('Very good, sir. Reading it in the background.');
    go(ShellScreen.ledger);

    // Fire-and-forget: errors are surfaced via toast; the pending row's failed
    // status is reflected in the ledger automatically via pendingReceiptsProvider.
    unawaited(() async {
      try {
        final result =
            await ref.read(receiptPipelineProvider).processReceipt(stablePath);
        if (!result.ok) {
          _showReceiptError(result.error);
        }
      } catch (e) {
        _showReceiptError(e.toString());
      }
    }());
  }

  /// Re-runs OCR on a previously-failed pending receipt, reusing its stored
  /// image — no re-upload. The card updates live via [pendingReceiptsProvider].
  Future<void> retryPending(String id) async {
    showToast('Trying that again, sir.');
    unawaited(() async {
      try {
        final result = await ref.read(receiptPipelineProvider).retry(id);
        if (!result.ok) _showReceiptError(result.error);
      } catch (e) {
        _showReceiptError(e.toString());
      }
    }());
  }

  /// Deletes a pending receipt from the ledger (rejects the row + removes its
  /// stored image). Used by the ledger's pending-card delete action. The card
  /// disappears live via [pendingReceiptsProvider].
  Future<void> deletePending(String id) async {
    try {
      final pending = await ref.read(pendingRepositoryProvider).getById(id);
      await ref.read(receiptPipelineProvider).reject(id);
      if (pending?.filePath != null) {
        await ref
            .read(receiptImageStoreProvider)
            .deleteReceipt(pending!.filePath!);
      }
      showToast('Removed, sir.');
    } catch (_) {
      showToast('Could not remove that receipt, sir.');
    }
  }

  // --- review / confirm ----------------------------------------------------

  void reviewPending(String id) {
    state = state.copyWith(reviewingId: id, screen: ShellScreen.confirm);
  }

  Future<void> saveConfirm(String pendingId, ExpenseDraft editedDraft) async {
    try {
      await ref
          .read(receiptPipelineProvider)
          .commitConfirmed(pendingId, editedDraft);
      state = state.copyWith(
        reviewingId: null,
        screen: ShellScreen.ledger,
      );
      showToast('Very good, sir.');
    } catch (_) {
      showToast('Could not save the expense, sir.');
    }
  }

  Future<void> discardConfirm(String pendingId) async {
    try {
      final pending =
          await ref.read(pendingRepositoryProvider).getById(pendingId);
      await ref.read(receiptPipelineProvider).reject(pendingId);
      if (pending?.filePath != null) {
        await ref
            .read(receiptImageStoreProvider)
            .deleteReceipt(pending!.filePath!);
      }
      state = state.copyWith(reviewingId: null, screen: ShellScreen.ledger);
    } catch (_) {
      showToast('Could not discard that receipt, sir.');
    }
  }
}

/// Provider for [ShellViewModel].
final shellViewModelProvider =
    AutoDisposeNotifierProvider<ShellViewModel, ShellState>(ShellViewModel.new);
