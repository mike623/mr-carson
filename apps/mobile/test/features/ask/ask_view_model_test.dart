import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/ask/ask_view_model.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';

/// A gemma fake whose [state] is fixed — lets us drive the Ask VM down the
/// model-unavailable branch without any inference wiring.
class _FakeGemmaService extends GemmaService {
  _FakeGemmaService(this._state);
  final GemmaState _state;

  @override
  GemmaState get state => _state;
}

/// A [ChatService] fake that replays a fixed sequence of [ChatEvent]s (or an
/// error) when [send] is called. [start] is a no-op.
///
/// We pass a no-executor [AppDatabase] to satisfy the super constructor; since
/// [start] and [send] are fully overridden the DB is never opened or used.
class _FakeChatService extends ChatService {
  _FakeChatService(this._events)
      : super(_NullGemmaService(), AppDatabase(NativeDatabase.memory()), PendingRepository(AppDatabase(NativeDatabase.memory())));

  /// Events (or a [_StreamError]) to emit on [send].
  final List<Object> _events; // ChatEvent | _StreamError

  @override
  Future<void> start() async {}

  @override
  Stream<ChatEvent> send(String userMessage) async* {
    for (final e in _events) {
      if (e is ChatEvent) {
        yield e;
      } else if (e is _StreamError) {
        throw e.error;
      }
    }
  }
}

/// Sentinel for injecting a stream error into [_FakeChatService].
class _StreamError {
  const _StreamError(this.error);
  final Object error;
}

/// Minimal GemmaService stub (never called; just satisfies the constructor).
class _NullGemmaService extends GemmaService {
  @override
  GemmaState get state => GemmaState.ready;
}

void main() {
  /// Container wired with a fixed [GemmaState] and no chat override (existing
  /// unavailable-path tests).
  ProviderContainer makeContainer(GemmaState gemmaState) {
    final container = ProviderContainer(
      overrides: [
        gemmaServiceProvider
            .overrideWithValue(_FakeGemmaService(gemmaState)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(askViewModelProvider, (_, __) {}, fireImmediately: true);
    return container;
  }

  /// Container wired with [GemmaState.ready] and a fake chat that replays
  /// [events] (a mix of [ChatEvent]s and [_StreamError]s).
  ProviderContainer makeContainerWithChat(List<Object> events) {
    final container = ProviderContainer(
      overrides: [
        gemmaServiceProvider
            .overrideWithValue(_FakeGemmaService(GemmaState.ready)),
        chatServiceProvider.overrideWithValue(_FakeChatService(events)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(askViewModelProvider, (_, __) {}, fireImmediately: true);
    return container;
  }

  /// Polls until [predicate] is true or the timeout (3 s) elapses.
  Future<void> pumpUntil(
    ProviderContainer container,
    bool Function(AskState) predicate,
  ) async {
    for (var i = 0; i < 120; i++) {
      if (predicate(container.read(askViewModelProvider))) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  // ---------------------------------------------------------------------------
  // F1 — onError must not clobber a partially-streamed answer
  // ---------------------------------------------------------------------------

  group('F1: stream error handling', () {
    test(
        'error AFTER TextDelta — partial text is preserved, not replaced by '
        'unavailable copy', () async {
      final container = makeContainerWithChat([
        const TextDelta('Hello'),
        const TextDelta(', sir.'),
        const _StreamError('network gone'),
      ]);
      final vm = container.read(askViewModelProvider.notifier);

      vm.send('How much this month?');

      await pumpUntil(
        container,
        (s) => !s.streaming && s.messages.length >= 2,
      );

      final state = container.read(askViewModelProvider);
      final carson = state.messages.last;
      expect(carson.isUser, isFalse);
      expect(carson.streaming, isFalse);
      expect(carson.thinking, isFalse);

      // Partial text must be preserved — not overwritten by unavailable copy.
      expect(
        carson.text,
        contains('Hello'),
        reason: 'partial streamed text should be kept on mid-flight error',
      );
      expect(
        carson.text,
        isNot(contains('not yet ready')),
        reason: 'unavailable copy must not replace partial answer',
      );
      // Butler-tone apology is appended.
      expect(
        carson.text.toLowerCase(),
        contains('forgive'),
        reason: 'butler-tone apology should be appended',
      );
    });

    test(
        'error with NO prior TextDelta — shows the honest unavailable message',
        () async {
      final container = makeContainerWithChat([
        const _StreamError('model crashed before any token'),
      ]);
      final vm = container.read(askViewModelProvider.notifier);

      vm.send('How much this month?');

      await pumpUntil(
        container,
        (s) => !s.streaming && s.messages.length >= 2,
      );

      final state = container.read(askViewModelProvider);
      final carson = state.messages.last;
      expect(carson.isUser, isFalse);
      expect(carson.streaming, isFalse);

      // Must show honest unavailable message when no text had arrived.
      final lower = carson.text.toLowerCase();
      expect(
        lower.contains('not') ||
            lower.contains("can't") ||
            lower.contains('unable') ||
            lower.contains('set up') ||
            lower.contains('mind') ||
            lower.contains('forgive'),
        isTrue,
        reason: 'expected honest unavailable message, got: ${carson.text}',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // F2 — ChatMessage.copyWith can clear chart to null
  // ---------------------------------------------------------------------------

  group('F2: ChatMessage.copyWith sentinel', () {
    test('copyWith(chart: null) clears an existing chart', () {
      const ChartData chart = (
        rows: [
          CategoryBucket(bucket: '2026-06', category: 'Dining', total: 42)
        ],
        granularity: Granularity.month,
        currency: 'GBP',
      );
      const msg = ChatMessage(isUser: false, chart: chart);
      final cleared = msg.copyWith(chart: null);
      expect(cleared.chart, isNull,
          reason: 'copyWith(chart: null) should clear the chart');
    });

    test('copyWith() without chart argument preserves existing chart', () {
      const ChartData chart = (
        rows: [
          CategoryBucket(bucket: '2026-06', category: 'Dining', total: 42)
        ],
        granularity: Granularity.month,
        currency: 'GBP',
      );
      const msg = ChatMessage(isUser: false, chart: chart);
      final copied = msg.copyWith(text: 'updated');
      expect(copied.chart, equals(chart),
          reason: 'omitting chart from copyWith should preserve it');
    });
  });

  // ---------------------------------------------------------------------------
  // Existing tests
  // ---------------------------------------------------------------------------

  test('ChatMessage carries a ChartData payload (no hasChart bool)', () {
    const ChartData chart = (
      rows: [CategoryBucket(bucket: '2026-06', category: 'Dining', total: 42)],
      granularity: Granularity.month,
      currency: 'GBP',
    );
    const msg = ChatMessage(isUser: false, chart: chart);
    expect(msg.chart, isNotNull);
    expect(msg.chart!.rows.single.category, 'Dining');

    const plain = ChatMessage(isUser: false, text: 'hello');
    expect(plain.chart, isNull);
  });

  group('DraftReady navigation', () {
    test('a DraftReady event opens the Confirm screen for that pending id', () async {
      final container = makeContainerWithChat([
        const DraftReady('pending-123'),
      ]);
      // Observe the shell so its notifier is alive.
      container.listen(shellViewModelProvider, (_, __) {}, fireImmediately: true);

      final vm = container.read(askViewModelProvider.notifier);
      vm.send('add lunch');

      await pumpUntil(
        container,
        (_) => container.read(shellViewModelProvider).screen == ShellScreen.confirm,
      );

      final shell = container.read(shellViewModelProvider);
      expect(shell.screen, ShellScreen.confirm);
      expect(shell.reviewingId, 'pending-123');
    });
  });

  test('model unavailable → honest "AI unavailable" message, not a canned reply',
      () async {
    final container = makeContainer(GemmaState.notDownloaded);
    final vm = container.read(askViewModelProvider.notifier);

    vm.send('How much have I spent this month?');

    // Let the thinking/stream timers run to completion.
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = container.read(askViewModelProvider);
      if (!s.streaming && s.messages.length >= 2) break;
    }

    final state = container.read(askViewModelProvider);
    final carson = state.messages.last;
    expect(carson.isUser, isFalse);
    expect(carson.streaming, isFalse);
    expect(carson.chart, isNull);

    // The honest unavailable message — never the fabricated spend figures.
    final lower = carson.text.toLowerCase();
    expect(
      lower.contains('not') ||
          lower.contains("can't") ||
          lower.contains('unable') ||
          lower.contains('set up') ||
          lower.contains('mind'),
      isTrue,
      reason: 'expected an honest unavailable message, got: ${carson.text}',
    );
    // Must NOT be one of the old canned figures.
    expect(carson.text, isNot(contains('1,284.60')));
    expect(carson.text, isNot(contains('Petersham')));
  });
}
