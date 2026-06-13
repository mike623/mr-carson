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
  });

  /// 0 — welcome, 1 — privacy, 2 — download.
  final int step;

  /// Download progress, 0–100. Kept as a double so the fabricated download
  /// stats (MB / speed / ETA) ramp exactly as the original prototype did.
  final double downloadPct;

  /// Whether the (mock or real) download is paused.
  final bool paused;

  /// Whether the download has completed.
  final bool done;

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
    );
  }
}

/// Drives the three-step onboarding flow.
///
/// Real path: pipes [GemmaService.downloadModel]'s `Stream<int>` into
/// [OnboardingState.downloadPct]. Because [kDefaultModelUrl] is a placeholder
/// (no real multi-GB model is hosted), the download is wrapped in try/catch and
/// falls back to the original mock `Timer` ramp (~8s, +1.2/tick) when the URL is
/// the placeholder or the stream errors — so the demo runs offline exactly as
/// the prototype did.
class OnboardingViewModel extends AutoDisposeNotifier<OnboardingState> {
  Timer? _mockTimer;
  StreamSubscription<int>? _downloadSub;

  @override
  OnboardingState build() {
    ref.onDispose(() {
      _mockTimer?.cancel();
      _downloadSub?.cancel();
    });
    return const OnboardingState();
  }

  /// Welcome → Privacy.
  void begin() {
    state = state.copyWith(step: 1);
  }

  /// Privacy → Download. Starts the download (real or mock fallback).
  void allowAndStartDownload() {
    state = state.copyWith(step: 2, downloadPct: 0, paused: false, done: false);
    _startDownload();
  }

  /// Pause / resume the download ramp.
  void togglePause() {
    state = state.copyWith(paused: !state.paused);
  }

  // --- download ------------------------------------------------------------

  void _startDownload() {
    _mockTimer?.cancel();
    _downloadSub?.cancel();

    // The model URL is a placeholder until a real Gemma 3n .litertlm is hosted,
    // so there is nothing to actually download. Use the mock ramp directly.
    if (kDefaultModelUrl.contains('example.com')) {
      _startMockRamp();
      return;
    }

    try {
      final stream = ref.read(gemmaServiceProvider).downloadModel();
      _downloadSub = stream.listen(
        (pct) {
          if (state.paused) return;
          final clamped = pct.toDouble().clamp(0.0, 100.0);
          state = state.copyWith(
            downloadPct: clamped,
            done: clamped >= 100,
          );
        },
        onError: (_) => _startMockRamp(),
        onDone: () {
          if (!state.done) {
            state = state.copyWith(downloadPct: 100, done: true);
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      _startMockRamp();
    }
  }

  void _startMockRamp() {
    _mockTimer?.cancel();
    // Mirror the original prototype ramp exactly: +1.2 every 110ms on a double.
    _mockTimer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      if (state.paused) return;
      final next = (state.downloadPct + 1.2).clamp(0.0, 100.0);
      if (next >= 100) {
        t.cancel();
        state = state.copyWith(downloadPct: 100, done: true);
      } else {
        state = state.copyWith(downloadPct: next);
      }
    });
  }
}

/// Provider for [OnboardingViewModel].
final onboardingViewModelProvider =
    AutoDisposeNotifierProvider<OnboardingViewModel, OnboardingState>(
  OnboardingViewModel.new,
);
