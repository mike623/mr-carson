import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/gemma_service.dart';

/// Immutable state for the onboarding flow.
@immutable
class OnboardingState {
  const OnboardingState({
    this.step = 0,
    this.downloadPct = 0,
    this.paused = false,
    this.done = false,
    this.error,
  });

  /// 0 — welcome, 1 — privacy, 2 — download.
  final int step;

  /// Real download progress, 0–100. Kept as a double so the derived download
  /// stats (MB / speed / ETA) interpolate smoothly between the stream's integer
  /// percentage ticks.
  final double downloadPct;

  /// Whether the download is paused.
  final bool paused;

  /// Whether the model is downloaded AND loaded — i.e. ready for the user to
  /// enter the app.
  final bool done;

  /// Human-readable failure message when the real download or load throws.
  /// Non-null only while the download step is in its error arm; cleared on
  /// [OnboardingViewModel.retry].
  final String? error;

  /// Convenience flag for the error arm of the download step.
  bool get hasError => error != null;

  OnboardingState copyWith({
    int? step,
    double? downloadPct,
    bool? paused,
    bool? done,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      downloadPct: downloadPct ?? this.downloadPct,
      paused: paused ?? this.paused,
      done: done ?? this.done,
      // error is intentionally not copied — every successful transition implies
      // no error. Use the dedicated error/clear paths below instead.
      error: null,
    );
  }

  /// Returns a copy carrying [message] as the failure reason. Separate from
  /// [copyWith] because [copyWith] always clears the error.
  OnboardingState withError(String message) {
    return OnboardingState(
      step: step,
      downloadPct: downloadPct,
      paused: paused,
      done: false,
      error: message,
    );
  }
}

/// Drives the three-step onboarding flow.
///
/// The download step is driven ENTIRELY by the real model lifecycle:
///   1. If [GemmaService.hasActiveModel] is already true (a returning user),
///      skip the multi-GB download and go straight to [GemmaService.loadModel].
///   2. Otherwise pipe [GemmaService.downloadModel]'s real `Stream<int>`
///      (0–100) into [OnboardingState.downloadPct], then [GemmaService.loadModel]
///      to bring the model to [GemmaState.ready].
///
/// Any download/load failure surfaces an honest error state with a retry — there
/// is no mock ramp and no fabricated progress.
class OnboardingViewModel extends AutoDisposeNotifier<OnboardingState> {
  StreamSubscription<int>? _downloadSub;
  bool _loadStarted = false;

  @override
  OnboardingState build() {
    ref.onDispose(() {
      _downloadSub?.cancel();
    });
    return const OnboardingState();
  }

  /// Welcome → Privacy.
  void begin() {
    state = state.copyWith(step: 1);
  }

  /// Privacy → Download. Starts the real download (or the already-installed
  /// fast-path).
  void allowAndStartDownload() {
    state = state.copyWith(step: 2, downloadPct: 0, paused: false, done: false);
    _startDownload();
  }

  /// Pause / resume the download. (flutter_gemma's installer cannot itself be
  /// paused mid-flight, so this only gates UI progress updates from the stream.)
  void togglePause() {
    state = state.copyWith(paused: !state.paused);
  }

  /// Re-attempts the real download after a failure. Clears the error and
  /// restarts from 0.
  void retry() {
    _loadStarted = false;
    state = state.copyWith(downloadPct: 0, paused: false, done: false);
    _startDownload();
  }

  // --- download ------------------------------------------------------------

  void _startDownload() {
    _downloadSub?.cancel();
    _downloadSub = null;
    _loadStarted = false;

    final gemma = ref.read(gemmaServiceProvider);

    // The model is only ever served from R2 now. The flag exists solely so the
    // flow can show an honest "not available yet" state if the object is ever
    // removed — it never falls back to a fake download.
    if (!kModelHostedOnR2) {
      state = state.withError(
        'The model is not available to download just yet. '
        'Please try again later, sir.',
      );
      return;
    }

    // Fast-path: a returning user already has the model installed — skip the
    // multi-GB download and load it directly.
    if (gemma.hasActiveModel()) {
      state = state.copyWith(downloadPct: 100, done: false);
      _loadModel();
      return;
    }

    final stream = gemma.downloadModel();
    _downloadSub = stream.listen(
      (pct) {
        if (state.paused) return;
        final clamped = pct.toDouble().clamp(0.0, 100.0);
        // Hold at 99% visually until loadModel completes; _loadModel flips done.
        state = state.copyWith(downloadPct: clamped);
        if (clamped >= 100) _loadModel();
      },
      onError: (Object e) => _failDownload(e),
      onDone: () {
        // Stream closed cleanly. Ensure the model is loaded even if the final
        // 100 tick never arrived.
        state = state.copyWith(downloadPct: 100);
        _loadModel();
      },
      cancelOnError: true,
    );
  }

  /// Loads the downloaded (or already-installed) model into the inference engine
  /// so the rest of the app sees [GemmaState.ready]. On failure, surfaces the
  /// error arm with retry rather than silently completing onboarding.
  Future<void> _loadModel() async {
    if (_loadStarted) return;
    _loadStarted = true;
    try {
      await ref.read(gemmaServiceProvider).loadModel();
      state = state.copyWith(downloadPct: 100, done: true);
    } catch (e) {
      _failDownload(e);
    }
  }

  void _failDownload(Object error) {
    _downloadSub?.cancel();
    _downloadSub = null;
    _loadStarted = false;
    state = state.withError(
      "I couldn't bring the model aboard. Check your connection and try again.",
    );
    debugPrint('Onboarding download/load failed: $error');
  }
}

/// Provider for [OnboardingViewModel].
final onboardingViewModelProvider =
    AutoDisposeNotifierProvider<OnboardingViewModel, OnboardingState>(
  OnboardingViewModel.new,
);
