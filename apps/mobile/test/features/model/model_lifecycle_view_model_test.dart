import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/features/model/model_lifecycle_view_model.dart';

/// Controllable fake so tests never hit the network or load a real model.
class _FakeGemmaService extends GemmaService {
  _FakeGemmaService({this.emitError = false});

  /// When true, [downloadModel] emits a stream error so the VM falls back to
  /// the mock ramp (used to exercise the offline-ready path).
  final bool emitError;

  final ValueNotifier<GemmaState> _notifier =
      ValueNotifier(GemmaState.notDownloaded);

  StreamController<int>? controller;
  bool loadCalled = false;
  bool removeCalled = false;

  @override
  GemmaState get state => _notifier.value;

  @override
  ValueListenable<GemmaState> get stateListenable => _notifier;

  @override
  Stream<int> downloadModel([String? url]) {
    final c = StreamController<int>();
    controller = c;
    if (emitError) {
      // Defer the error so the VM has subscribed first.
      scheduleMicrotask(() {
        if (!c.isClosed) {
          c.addError(StateError('no model hosted'));
          c.close();
        }
      });
    }
    return c.stream;
  }

  @override
  Future<void> loadModel() async {
    loadCalled = true;
    _notifier.value = GemmaState.ready;
  }

  @override
  Future<void> removeModel() async {
    removeCalled = true;
    _notifier.value = GemmaState.notDownloaded;
  }
}

void main() {
  ProviderContainer makeContainer(_FakeGemmaService fake) {
    final container = ProviderContainer(
      overrides: [gemmaServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose provider alive across reads (without a listener it
    // would be torn down between microtasks, losing VM state).
    container.listen(modelLifecycleProvider, (_, __) {}, fireImmediately: true);
    return container;
  }

  test('engage() moves phase to downloading and downloadPct rises with stream',
      () async {
    final fake = _FakeGemmaService();
    final container = makeContainer(fake);
    final notifier = container.read(modelLifecycleProvider.notifier);

    notifier.engage();
    expect(container.read(modelLifecycleProvider).phase,
        GemmaState.downloading);
    expect(container.read(modelLifecycleProvider).downloadPct, 0);

    // Let the VM subscribe, then push progress through the real download path.
    await Future<void>.delayed(Duration.zero);
    fake.controller!.add(42);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(modelLifecycleProvider).downloadPct, 42);
    expect(container.read(modelLifecycleProvider).isDownloading, isTrue);
  });

  test('reaching 100% on the real path loads the model and phase becomes ready',
      () async {
    final fake = _FakeGemmaService();
    final container = makeContainer(fake);
    final notifier = container.read(modelLifecycleProvider.notifier);

    notifier.engage();
    await Future<void>.delayed(Duration.zero);
    fake.controller!.add(100);
    // Allow the listen callback + loadModel() microtasks to settle.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(fake.loadCalled, isTrue);
    expect(container.read(modelLifecycleProvider).phase, GemmaState.ready);
    expect(container.read(modelLifecycleProvider).isReady, isTrue);
    expect(container.read(modelLifecycleProvider).downloadPct, 100);
  });

  test('mock ramp (stream error fallback) reaches 100% and phase becomes ready',
      () {
    fakeAsync((async) {
      final fake = _FakeGemmaService(emitError: true);
      final container = ProviderContainer(
        overrides: [gemmaServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      container.listen(modelLifecycleProvider, (_, __) {},
          fireImmediately: true);
      final notifier = container.read(modelLifecycleProvider.notifier);

      notifier.engage();
      // Flush the deferred stream error so the VM falls back to the mock ramp.
      async.flushMicrotasks();
      expect(container.read(modelLifecycleProvider).phase,
          GemmaState.downloading);

      // Advance well past the ~9.2s the +1.2/110ms ramp needs to hit 100.
      async.elapse(const Duration(seconds: 15));

      expect(container.read(modelLifecycleProvider).downloadPct, 100);
      expect(container.read(modelLifecycleProvider).phase, GemmaState.ready);
    });
  });

  test('togglePause() halts mock-ramp progression', () {
    fakeAsync((async) {
      final fake = _FakeGemmaService(emitError: true);
      final container = ProviderContainer(
        overrides: [gemmaServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      container.listen(modelLifecycleProvider, (_, __) {},
          fireImmediately: true);
      final notifier = container.read(modelLifecycleProvider.notifier);

      notifier.engage();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      final pctBeforePause = container.read(modelLifecycleProvider).downloadPct;
      expect(pctBeforePause, greaterThan(0));
      expect(pctBeforePause, lessThan(100));

      notifier.togglePause();
      expect(container.read(modelLifecycleProvider).paused, isTrue);

      async.elapse(const Duration(seconds: 3));
      expect(container.read(modelLifecycleProvider).downloadPct,
          pctBeforePause);
    });
  });

  test('remove() resets phase to notDownloaded and downloadPct to 0', () async {
    final fake = _FakeGemmaService();
    final container = makeContainer(fake);
    final notifier = container.read(modelLifecycleProvider.notifier);

    notifier.engage();
    await Future<void>.delayed(Duration.zero);
    fake.controller!.add(55);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(modelLifecycleProvider).downloadPct, 55);

    await notifier.remove();

    expect(fake.removeCalled, isTrue);
    expect(container.read(modelLifecycleProvider).phase,
        GemmaState.notDownloaded);
    expect(container.read(modelLifecycleProvider).downloadPct, 0);
    expect(container.read(modelLifecycleProvider).isAbsent, isTrue);
  });

  test('build() seeds phase from the service state', () {
    final fake = _FakeGemmaService();
    fake._notifier.value = GemmaState.ready;
    final container = makeContainer(fake);

    expect(container.read(modelLifecycleProvider).phase, GemmaState.ready);
  });
}
