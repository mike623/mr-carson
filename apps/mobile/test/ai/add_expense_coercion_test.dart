import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/chat_service.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  const today = '2026-06-22';

  Map<String, dynamic> build(Map<String, dynamic> args) =>
      ChatService.buildExpenseDraftJson(args, today);

  test('full args round-trip into a valid ExpenseDraft', () {
    final d = ExpenseDraft.fromJson(build({
      'merchant': 'Wagamama',
      'total': 12.0,
      'category': 'Dining',
      'date': '2026-06-20',
      'currency': 'gbp',
    }));
    expect(d.merchant, 'Wagamama');
    expect(d.total, 12.0);
    expect(d.currency, 'GBP'); // uppercased
    expect(d.date, '2026-06-20');
    expect(d.categories, ['Dining']);
  });

  test('date "today" / "yesterday" resolve relative to the passed today', () {
    expect(build({'date': 'today'})['date'], '2026-06-22');
    expect(build({'date': 'yesterday'})['date'], '2026-06-21');
  });

  test('missing date defaults to today', () {
    expect(build({'merchant': 'X'})['date'], '2026-06-22');
  });

  test('unknown category falls back to Other', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X', 'category': 'Spaceship'}));
    expect(d.categories, ['Other']);
    expect(d.items.single.category, 'Other');
  });

  test('missing currency defaults to kDefaultCurrency', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X'}));
    expect(d.currency, kDefaultCurrency);
  });

  test('no items: synthesizes one item equal to the total', () {
    final d = ExpenseDraft.fromJson(build({
      'merchant': 'Tesco',
      'total': 9.5,
      'category': 'Groceries',
    }));
    expect(d.items, hasLength(1));
    expect(d.items.single.name, 'Tesco');
    expect(d.items.single.amount, 9.5);
    expect(d.items.single.category, 'Groceries');
  });

  test('empty merchant + zero total still produce a parseable draft', () {
    final d = ExpenseDraft.fromJson(build({}));
    expect(d.merchant, '');
    expect(d.total, 0);
    expect(d.items.single.name, 'Expense'); // fallback name when no merchant
  });

  test('loose total string is parsed', () {
    final d = ExpenseDraft.fromJson(build({'merchant': 'X', 'total': '12.30'}));
    expect(d.total, 12.30);
  });
}
