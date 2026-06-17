import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';

/// Runs [chunks] through a fresh [ToolCallEnvelopeFilter] and returns the
/// concatenated cleaned text plus the extracted tool calls.
({String text, List<ToolCallStarted> calls}) run(List<String> chunks) {
  final f = ToolCallEnvelopeFilter();
  final events = <ChatEvent>[];
  for (final c in chunks) {
    events.addAll(f.add(c));
  }
  events.addAll(f.flush());

  final text = events.whereType<TextDelta>().map((e) => e.token).join();
  final calls = events.whereType<ToolCallStarted>().toList();
  return (text: text, calls: calls);
}

void main() {
  group('ToolCallEnvelopeFilter', () {
    test('strips a leaked tool_call envelope and keeps only the answer', () {
      // The exact shape seen leaking into the bubble (double-nested array).
      const leak =
          '{"role":"assistant","tool_calls":[[{"type":"function","function":'
          '{"name":"queryExpenses","arguments":{"dateRange":"thisMonth"}}}]]}'
          'You have spent zero pounds this month.';

      final r = run([leak]);

      expect(r.text, 'You have spent zero pounds this month.');
      expect(r.calls, hasLength(1));
      expect(r.calls.single.name, 'queryExpenses');
      expect(r.calls.single.args['dateRange'], 'thisMonth');
    });

    test('reassembles an envelope split across streamed chunks', () {
      final r = run([
        '{"role":"assistant","tool_ca',
        'lls":[{"type":"function","function":{"name":"topMerchants",',
        '"arguments":{"topN":3}}}]}',
        'Your top merchant was Waitrose.',
      ]);

      expect(r.text, 'Your top merchant was Waitrose.');
      expect(r.calls.single.name, 'topMerchants');
      expect(r.calls.single.args['topN'], 3);
    });

    test('plain text with no envelope passes straight through, streaming', () {
      final r = run(['Good ', 'evening, ', 'sir.']);
      expect(r.text, 'Good evening, sir.');
      expect(r.calls, isEmpty);
    });

    test('a leading JSON object that is not an envelope is left untouched', () {
      final r = run(['{"amount": 42} is the figure.']);
      expect(r.text, '{"amount": 42} is the figure.');
      expect(r.calls, isEmpty);
    });

    test('handles string-encoded arguments', () {
      const leak =
          '{"role":"assistant","tool_calls":[{"function":{"name":"chartSpending",'
          '"arguments":"{\\"granularity\\":\\"week\\"}"}}]}Here is the trend.';
      final r = run([leak]);
      expect(r.text, 'Here is the trend.');
      expect(r.calls.single.name, 'chartSpending');
      expect(r.calls.single.args['granularity'], 'week');
    });
  });
}
