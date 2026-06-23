import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/prompts.dart';

void main() {
  test('persona instructs the model to use addExpense for logging a purchase', () {
    expect(kChatSystemPersona, contains('addExpense'));
    // Never fabricate an amount.
    expect(kChatSystemPersona.toLowerCase(), contains('never invent'));
  });
}
