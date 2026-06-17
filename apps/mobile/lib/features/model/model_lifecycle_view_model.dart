import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/gemma_service.dart';

/// Immutable lifecycle state for in-app model surfaces (Ask locked-state,
/// Settings, Model Management, Add-sheet gating). This is a VM-owned mirror of
/// [GemmaService]'s state plus download progress / pause / error, so several
/// screens can react to a single source of truth.
@immutable
class ModelLifecycleState {
  const ModelLifecycleState({
    this.phase = GemmaState.notDownloaded,
    this.downloadPct = 0,
    this.paused = false,
    this.error,
  });

  /// VM-owned lifecycle phase. Mirrors [GemmaState] but is advanced by the VM
  /// (so the offline mock ramp can reach [GemmaState.ready] without a real
  /// model) and synced upward from real service transitions.
  final GemmaState phase;

  /// Download progress, 0–100. Kept as a double so fabricated download stats
  /// ramp smoothly (mirrors onboarding).
  final double downloadPct;

  /// Whether the (mock or real) download is paused.
  final bool paused;

  /// The last error message, populated when [phase] == [GemmaState.error].
  final String? error;

  bool get isAbsent => phase == GemmaState.notDownloaded;
  bool get isDownloading =>
      phase == GemmaState.downloading || phase == GemmaState.loading;
  bool get isReady => phase == GemmaState.ready;
  bool get isError => phase == GemmaState.error;

  ModelLifecycleState copyWith({
    GemmaState? phase,
    double? downloadPct,
    bool? paused,
    String? error,
  }) {
    return ModelLifecycleState(
      phase: phase ?? this.phase,
      downloadPct: downloadPct ?? this.downloadPct,
      paused: paused ?? this.paused,
      error: error ?? this.error,
    );
  }
}

/// Reactive, VM-owned model lifecycle shared across in-app surfaces.
///
/// Mirrors the onboarding download pattern: real download via
/// [GemmaService.downloadModel] when the model is hosted on R2 (and the URL is
/// not a placeholder), otherwise a mock `Timer` ramp so the demo runs offline.
/// On the mock path the VM advances [ModelLifecycleState.phase] to
/// [GemmaState.ready] itself (no real model exists to fire the service's `ready`
/// transition) — this is what powers the deferred-model UX. On the real path
/// `ready` arrives via the service's [GemmaService.stateListenable].
class ModelLifecycleViewModel extends AutoDisposeNotifier<ModelLifecycleState> {
  Timer? _mockTimer;
  StreamSubscription<int>? _downloadSub;
  VoidCallback? _serviceListener;
  bool _loadStarted = false;

  @override
  ModelLifecycleState build() {
    final service = ref.read(gemmaServiceProvider);

    // Sync real service transitions upward: ready / error only — downloading and
    // loading are driven by the VM itself (engage / mock ramp).
    void listener() {
      final s = service.state;
      if (s == GemmaState.ready) {
        state = state.copyWith(phase: GemmaState.ready, downloadPct: 100);
      } else if (s == GemmaState.error) {
        state = state.copyWith(
          phase: GemmaState.error,
          error: service.lastError,
        );
      }
    }

    service.stateListenable.addListener(listener);
    _serviceListener = listener;

    ref.onDispose(() {
      _mockTimer?.cancel();
      _downloadSub?.cancel();
      if (_serviceListener != null) {
        service.stateListenable.removeListener(_serviceListener!);
      }
    });

    // Seed phase from the service's current state.
    return ModelLifecycleState(phase: service.state);
  }

  /// Begin setup (download → load). Used by the locked-state CTA.
  void engage() {
    _loadStarted = false;
    state = state.copyWith(
      phase: GemmaState.downloading,
      downloadPct: 0,
      paused: false,
      error: null,
    );
    _startDownload();
  }

  /// Pause / resume the download ramp (only meaningful mid-download).
  void togglePause() {
    state = state.copyWith(paused: !state.paused);
  }

  /// Remove the on-disk/loaded model and return to the absent state.
  Future<void> remove() async {
    _mockTimer?.cancel();
    _downloadSub?.cancel();
    _loadStarted = false;
    await ref.read(gemmaServiceProvider).removeModel();
    state = const ModelLifecycleState(
      phase: GemmaState.notDownloaded,
      downloadPct: 0,
    );
  }

  /// Retry after an error — identical to [engage].
  void retry() => engage();

  // --- download ------------------------------------------------------------

  void _startDownload() {
    _mockTimer?.cancel();
    _downloadSub?.cancel();

    // No real model is reachable when it isn't hosted on R2 or the URL is the
    // legacy example.com placeholder — skip the doomed request and ramp the mock
    // progress directly (mirrors onboarding's _startDownload).
    if (!kModelHostedOnR2 || kDefaultModelUrl.contains('example.com')) {
      _startMockRamp();
      return;
    }

    try {
      final stream = ref.read(gemmaServiceProvider).downloadModel();
      _downloadSub = stream.listen(
        (pct) {
          if (state.paused) return;
          final clamped = pct.toDouble().clamp(0.0, 100.0);
          state = state.copyWith(downloadPct: clamped);
          if (clamped >= 100) _loadModel();
        },
        onError: (_) => _startMockRamp(),
        onDone: () {
          if (state.downloadPct < 100) {
            state = state.copyWith(downloadPct: 100);
          }
          _loadModel();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _startMockRamp();
    }
  }

  /// Loads the downloaded model into the inference engine. Best-effort: a
  /// failure leaves the service in [GemmaState.error] (synced upward by the
  /// listener); the rest of the app degrades gracefully.
  Future<void> _loadModel() async {
    if (_loadStarted) return;
    _loadStarted = true;
    try {
      await ref.read(gemmaServiceProvider).loadModel();
    } catch (_) {
      // Swallowed by design — GemmaService records the error in its own state,
      // and the listener mirrors it into ModelLifecycleState.error.
    }
  }

  void _startMockRamp() {
    _mockTimer?.cancel();
    // Mirror onboarding's mock ramp exactly: +1.2 every 110ms on a double.
    _mockTimer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      if (state.paused) return;
      final next = (state.downloadPct + 1.2).clamp(0.0, 100.0);
      if (next >= 100) {
        t.cancel();
        // Demo-ready: no real model exists to fire the service's `ready`
        // transition, so the VM advances to ready itself when the mock ramp
        // completes — this is what makes the deferred-model UX work offline.
        state = state.copyWith(downloadPct: 100, phase: GemmaState.ready);
      } else {
        state = state.copyWith(downloadPct: next);
      }
    });
  }
}

/// Provider for [ModelLifecycleViewModel] — the shared model-lifecycle source of
/// truth for in-app surfaces.
final modelLifecycleProvider =
    AutoDisposeNotifierProvider<ModelLifecycleViewModel, ModelLifecycleState>(
  ModelLifecycleViewModel.new,
);
