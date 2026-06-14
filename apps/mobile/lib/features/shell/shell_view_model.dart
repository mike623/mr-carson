import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/image_picker_provider.dart';
import '../../data/providers.dart';
import '../../data/receipt_image_store.dart';
import '../../ai/receipt_pipeline.dart';

/// Which screen the shell is currently presenting.
enum ShellScreen { ask, ledger, detail, confirm }

/// Immutable state for the in-app shell.
///
/// The pending-receipt list is no longer held here — it is streamed from
/// [pendingReceiptsProvider] (the §1 reactive data layer) straight into the
/// ledger. This view-model owns navigation, the butler toast, and which pending
/// id is currently under review.
@immutable
class ShellState {
  const ShellState({
    this.screen = ShellScreen.ask,
    this.reviewingId,
    this.toast,
  });

  final ShellScreen screen;

  /// The pending id currently being reviewed on the confirm screen, if any.
  final String? reviewingId;

  /// Active butler toast message, or null when none is shown.
  final String? toast;

  bool get navVisible =>
      screen == ShellScreen.ask || screen == ShellScreen.ledger;

  ShellState copyWith({
    ShellScreen? screen,
    Object? reviewingId = _unset,
    Object? toast = _unset,
  }) {
    return ShellState(
      screen: screen ?? this.screen,
      reviewingId: identical(reviewingId, _unset)
          ? this.reviewingId
          : reviewingId as String?,
      toast: identical(toast, _unset) ? this.toast : toast as String?,
    );
  }

  static const _unset = Object();
}

/// Drives the in-app shell: navigation, the butler toast, and kicking off the
/// real capture → process pipeline.
///
/// Capture flow: a receipt is picked via [ImagePicker], copied into durable
/// storage by [ReceiptImageStore], then run through
/// [ReceiptPipelineService.processReceipt]. The pipeline writes a row into
/// `pending_expenses`, which streams back to the ledger via
/// [pendingReceiptsProvider] — there is no in-memory pending list here.
class ShellViewModel extends AutoDisposeNotifier<ShellState> {
  Timer? _toastTimer;

  @override
  ShellState build() {
    ref.onDispose(() {
      _toastTimer?.cancel();
    });
    return const ShellState();
  }

  // --- navigation ----------------------------------------------------------

  void go(ShellScreen s) => state = state.copyWith(screen: s);

  void showToast(String msg) {
    state = state.copyWith(toast: msg);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      state = state.copyWith(toast: null);
    });
  }

  // --- add sheet outcomes --------------------------------------------------

  /// "Take a photograph" — open the camera, then process the captured receipt.
  ///
  /// [imagePath] may be supplied directly (tests) to bypass the live picker.
  Future<void> capturePhoto({String? imagePath}) =>
      _pickAndProcess(ImageSource.camera, imagePath: imagePath);

  /// "Upload from library" — pick from the gallery, then process the receipt.
  ///
  /// [imagePath] may be supplied directly (tests) to bypass the live picker.
  Future<void> startUpload({String? imagePath}) =>
      _pickAndProcess(ImageSource.gallery, imagePath: imagePath);

  // --- real capture → process pipeline -------------------------------------

  Future<void> _pickAndProcess(
    ImageSource source, {
    String? imagePath,
  }) async {
    // 1. Obtain a source path — from the injected value (tests) or the picker.
    String? pickedPath = imagePath;
    if (pickedPath == null) {
      final XFile? file =
          await ref.read(imagePickerProvider).pickImage(source: source);
      if (file == null) return; // user cancelled
      pickedPath = file.path;
    }

    // 2. Copy into durable storage + hash for dedup.
    final StoredReceiptImage stored;
    try {
      stored = await ref.read(receiptImageStoreProvider).persist(pickedPath);
    } catch (e) {
      showToast('I could not save that image, sir.');
      return;
    }

    // 3. Dedup: skip an image we have already filed.
    final existing =
        await ref.read(appDatabaseProvider).findByImageHash(stored.imageHash);
    if (existing != null) {
      await ref.read(receiptImageStoreProvider).cleanup(stored.path);
      showToast('I have already filed this receipt, sir.');
      go(ShellScreen.ledger);
      return;
    }

    // 4. Hand off to the real pipeline. It writes the pending row (which
    //    streams to the ledger) and runs OCR + extraction.
    go(ShellScreen.ledger);
    showToast('Very good, sir. Reading it in the background.');

    final result =
        await ref.read(receiptPipelineProvider).processReceipt(stored.path);
    if (!result.ok) {
      showToast('I struggled with that receipt, sir.');
    }
  }

  // --- review / confirm ----------------------------------------------------

  void reviewPending(String id) {
    state = state.copyWith(reviewingId: id, screen: ShellScreen.confirm);
  }

  /// Called by the confirm screen once a draft has been committed or rejected;
  /// returns to the ledger. The ledger's pending list updates itself from the
  /// stream — nothing to remove here.
  void closeConfirm({String? toast}) {
    state = state.copyWith(reviewingId: null, screen: ShellScreen.ledger);
    if (toast != null) showToast(toast);
  }
}

/// Provider for [ShellViewModel].
final shellViewModelProvider =
    AutoDisposeNotifierProvider<ShellViewModel, ShellState>(ShellViewModel.new);
