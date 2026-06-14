import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/domain/models/ui_models.dart';
import 'package:mr_carson/features/ask/ask_view_model.dart';

/// A [GemmaService] whose lifecycle state is fixed — lets the Ask VM be driven
/// without loading a real model.
class _FakeGemmaService extends GemmaService {
  _FakeGemmaService(this._state);

  final GemmaState _state;

  @override
  GemmaState get state => _state;
}

/// A [ChatService] that replays a scripted list of [ChatEvent]s, so the VM can
/// be exercised end-to-end with no on-device model.
class _FakeChatService implements ChatService {
  _FakeChatService(this._events);

  final List<ChatEvent> _events;
  int startCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
  }

  @override
  Stream<ChatEvent> send(String userMessage) async* {
    for (final e in _events) {
      yield e;
    }
  }

  @override
  Future<void> dispose() async {}
}

/// A [ChatService] whose stream errors — exercises the honest-failure path.
class _ErroringChatService implements ChatService {
  @override
  Future<void> start() async {}

  @override
  Stream<ChatEvent> send(String userMessage) async* {
    throw StateError('boom');
  }

  @override
  Future<void> dispose() async {}
}

ProviderContainer _container({
  required GemmaState gemmaState,
  required ChatService chat,
}) {
  final container = ProviderContainer(
    overrides: [
      gemmaServiceProvider.overrideWithValue(_FakeGemmaService(gemmaState)),
      chatServiceProvider.overrideWithValue(chat),
    ],
  );
  // Keep the autoDispose VM alive for the test's duration.
  container.listen(askViewModelProvider, (_, __) {}, fireImmediately: true);
  addTearDown(container.dispose);
  return container;
}

void main() {
  const chartData = ChartData(
    buckets: [
      CategoryBucket(bucket: '2026-21', category: 'Dining', total: 42.0),
      CategoryBucket(bucket: '2026-22', category: 'Dining', total: 30.0),
    ],
    granularity: Granularity.week,
    currency: 'GBP',
  );

  test('model-not-ready surfaces an honest "AI unavailable" message — no '
      'fabricated answer', () async {
    final chat = _FakeChatService([const TextChunk('should not be used')]);
    final container = _container(
      gemmaState: GemmaState.notDownloaded,
      chat: chat,
    );
    final vm = container.read(askViewModelProvider.notifier);

    vm.send('How much did I spend?');
    // No async streaming on this path — the failure is set synchronously.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(askViewModelProvider);
    expect(state.streaming, isFalse);
    expect(state.messages.last.isUser, isFalse);
    expect(state.messages.last.text, AskViewModel.unavailableMessage);
    expect(state.messages.last.chart, isNull);
    // The real chat service was never started.
    expect(chat.startCalls, 0);
  });

  test('ready model: streamed text + a ChartReady event attach text AND '
      'ChartData to the assistant message', () async {
    final chat = _FakeChatService([
      const TextChunk('Quite so, sir. '),
      const TextChunk('Dining leads the field. '),
      const ChartReady(chartData),
      const TextChunk('The trend is gently downward.'),
    ]);
    final container = _container(gemmaState: GemmaState.ready, chat: chat);
    final vm = container.read(askViewModelProvider.notifier);

    vm.send('Chart my spending');
    // Let the async stream drain.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(askViewModelProvider);
    expect(chat.startCalls, 1);
    expect(state.streaming, isFalse);

    final reply = state.messages.last;
    expect(reply.isUser, isFalse);
    expect(reply.thinking, isFalse);
    expect(reply.streaming, isFalse);
    expect(
      reply.text,
      'Quite so, sir. Dining leads the field. The trend is gently downward.',
    );
    expect(reply.chart, isNotNull);
    expect(reply.hasChart, isTrue);
    expect(reply.chart!.granularity, Granularity.week);
    expect(reply.chart!.buckets, hasLength(2));
  });

  test('send error falls back to the honest unavailable message', () async {
    final container = _container(
      gemmaState: GemmaState.ready,
      chat: _ErroringChatService(),
    );
    final vm = container.read(askViewModelProvider.notifier);

    vm.send('Anything');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(askViewModelProvider);
    expect(state.streaming, isFalse);
    expect(state.messages.last.text, AskViewModel.unavailableMessage);
    expect(state.messages.last.chart, isNull);
  });
}
