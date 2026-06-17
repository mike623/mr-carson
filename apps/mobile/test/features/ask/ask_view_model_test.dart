import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/ask/ask_view_model.dart';

/// A gemma fake whose [state] is fixed — lets us drive the Ask VM down the
/// model-unavailable branch without any inference wiring.
class _FakeGemmaService extends GemmaService {
  _FakeGemmaService(this._state);
  final GemmaState _state;

  @override
  GemmaState get state => _state;
}

void main() {
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
