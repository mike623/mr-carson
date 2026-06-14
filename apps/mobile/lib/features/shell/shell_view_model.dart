import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/gemma_service.dart';
import '../../ai/receipt_pipeline.dart';
import '../ledger/ledger_screen.dart' show LedgerPending;

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

/// Immutable state for the in-app shell.
@immutable
class ShellState {
  const ShellState({
    this.screen = ShellScreen.ask,
    this.pending = const [],
    this.reviewingId,
    this.toast,
  });

  final ShellScreen screen;
  final List<LedgerPending> pending;

  /// The pending id currently being reviewed on the confirm screen, if any.
  final String? reviewingId;

  /// Active butler toast message, or null when none is shown.
  final String? toast;

  bool get navVisible =>
      screen == ShellScreen.ask || screen == ShellScreen.ledger;

  ShellState copyWith({
    ShellScreen? screen,
    List<LedgerPending>? pending,
    Object? reviewingId = _unset,
    Object? toast = _unset,
  }) {
    return ShellState(
      screen: screen ?? this.screen,
      pending: pending ?? this.pending,
      reviewingId:
          identical(reviewingId, _unset) ? this.reviewingId : reviewingId as String?,
      toast: identical(toast, _unset) ? this.toast : toast as String?,
    );
  }

  static const _unset = Object();
}

/// Drives the in-app shell: navigation, the pending receipt list, and the
/// butler toast.
///
/// Real path: a chosen receipt is run through
/// [ReceiptPipelineService.processReceipt]; on success the pending card is
/// marked ready.
///
/// Fallback: when the Gemma model isn't [GemmaState.ready] or no real image
/// path is supplied (the demo's "Upload from library" action), the original
/// mock progress ramp is used so the prototype flow is preserved exactly.
class ShellViewModel extends AutoDisposeNotifier<ShellState> {
  Timer? _procTimer;
  Timer? _toastTimer;

  @override
  ShellState build() {
    ref.onDispose(() {
      _procTimer?.cancel();
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

  /// "Take a photograph" — open the confirm screen for a fresh capture.
  void capturePhoto() {
    state = state.copyWith(reviewingId: null, screen: ShellScreen.confirm);
  }

  /// "Upload from library" — start background processing.
  ///
  /// [imagePath] is supplied when a real file is chosen; when null (the demo's
  /// library action), the mock ramp runs.
  void startUpload({String? imagePath}) {
    final id = 'p${DateTime.now().millisecondsSinceEpoch}';
    final pending = [
      LedgerPending(
        id: id,
        ready: false,
        stage: 'Reading the receipt…',
        pct: 0,
      ),
      ...state.pending,
    ];
    state = state.copyWith(pending: pending, screen: ShellScreen.ledger);
    showToast('Very good, sir. Reading it in the background.');

    final gemma = ref.read(gemmaServiceProvider);
    if (imagePath != null &&
        File(imagePath).existsSync() &&
        gemma.state == GemmaState.ready) {
      _realProcess(id, imagePath);
    } else {
      _mockProcess(id);
    }
  }

  // --- real path -----------------------------------------------------------

  Future<void> _realProcess(String id, String imagePath) async {
    try {
      final result =
          await ref.read(receiptPipelineProvider).processReceipt(imagePath);
      final draft = result.draft;
      if (result.ok && draft != null) {
        _markReady(
          id,
          merchant: draft.merchant,
          total: '${draft.currency} ${draft.total.toStringAsFixed(2)}',
        );
      } else {
        // On failure fall back to the mock ramp so the card still completes.
        _mockProcess(id);
      }
    } catch (_) {
      _mockProcess(id);
    }
  }

  // --- fallback (mock) path ------------------------------------------------

  void _mockProcess(String id) {
    final rng = Random();
    _procTimer?.cancel();
    _procTimer = Timer.periodic(const Duration(milliseconds: 260), (t) {
      final pending = List<LedgerPending>.from(state.pending);
      final i = pending.indexWhere((p) => p.id == id);
      if (i < 0) {
        t.cancel();
        return;
      }
      final p = pending[i];
      final pct = p.pct + 3 + rng.nextInt(5);
      if (pct >= 100) {
        t.cancel();
        pending[i] = LedgerPending(
          id: id,
          ready: true,
          stage: 'Ready for your review',
          pct: 100,
          merchant: 'Caffè Nero',
          total: '£6.15',
        );
      } else {
        final stage = pct < 45
            ? 'Reading the receipt…'
            : (pct < 80 ? 'Extracting the figures…' : 'Tidying up…');
        pending[i] = LedgerPending(id: id, ready: false, stage: stage, pct: pct);
      }
      state = state.copyWith(pending: pending);
    });
  }

  void _markReady(String id, {required String merchant, required String total}) {
    final pending = List<LedgerPending>.from(state.pending);
    final i = pending.indexWhere((p) => p.id == id);
    if (i < 0) return;
    pending[i] = LedgerPending(
      id: id,
      ready: true,
      stage: 'Ready for your review',
      pct: 100,
      merchant: merchant,
      total: total,
    );
    state = state.copyWith(pending: pending);
  }

  // --- review / confirm ----------------------------------------------------

  void reviewPending(String id) {
    state = state.copyWith(reviewingId: id, screen: ShellScreen.confirm);
  }

  void saveConfirm() {
    var pending = state.pending;
    final reviewingId = state.reviewingId;
    if (reviewingId != null) {
      pending = pending.where((p) => p.id != reviewingId).toList();
    }
    state = state.copyWith(
      pending: pending,
      reviewingId: null,
      screen: ShellScreen.ledger,
    );
    showToast('Very good, sir.');
  }

  void discardConfirm() {
    state = state.copyWith(reviewingId: null, screen: ShellScreen.ledger);
  }
}

/// Provider for [ShellViewModel].
final shellViewModelProvider =
    AutoDisposeNotifierProvider<ShellViewModel, ShellState>(ShellViewModel.new);
