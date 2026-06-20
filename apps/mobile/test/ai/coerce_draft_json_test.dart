import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/receipt_pipeline.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

// Guards the receipt parse path: a model response with null / missing required
// fields must NOT throw "type 'Null' is not a subtype of type 'String'"
// (the failure seen in the field). It should yield an editable draft instead.
void main() {
  const today = '2026-06-20';

  ExpenseDraft parse(Map<String, dynamic> json) =>
      ExpenseDraft.fromJson(ReceiptPipelineService.coerceDraftJson(json, today));

  test('null merchant/total/currency coerce to safe defaults', () {
    final d = parse({
      'merchant': null,
      'date': null,
      'currency': null,
      'total': null,
      'items': null,
    });
    expect(d.merchant, 'Unknown merchant');
    expect(d.date, today);
    expect(d.currency, 'GBP');
    expect(d.total, 0.0);
    expect(d.items, isEmpty);
  });

  test('numeric strings and junk currency are normalised', () {
    final d = parse({
      'merchant': '  Blue Bottle  ',
      'currency': 'pounds', // not 3 chars -> default
      'total': '13.59', // string number -> double
      'items': [
        {'name': null, 'amount': '4.50', 'category': null},
        'garbage', // non-map entry dropped
      ],
    });
    expect(d.merchant, 'Blue Bottle');
    expect(d.currency, 'GBP');
    expect(d.total, 13.59);
    expect(d.items, hasLength(1));
    expect(d.items.first.name, 'Item');
    expect(d.items.first.amount, 4.50);
    expect(d.items.first.category, 'Other');
  });

  test('alternate model keys are mapped (the empty-items bug)', () {
    // Model returned items with description/price instead of name/amount —
    // previously rendered as 7x "Item / 0.00".
    final d = parse({
      'store': 'Waitrose',
      'transaction_date': '2026-05-26',
      'currency_code': 'GBP',
      'grand_total': '£17.25',
      'tax': '1.20',
      'line_items': [
        {'description': 'Bananas', 'price': '2.50', 'type': 'Groceries'},
        {'title': 'Milk', 'cost': 1.75},
      ],
    });
    expect(d.merchant, 'Waitrose');
    expect(d.date, '2026-05-26');
    expect(d.total, 17.25);
    expect(d.vat, 1.20);
    expect(d.items, hasLength(2));
    expect(d.items[0].name, 'Bananas');
    expect(d.items[0].amount, 2.50);
    expect(d.items[0].category, 'Groceries');
    expect(d.items[1].name, 'Milk');
    expect(d.items[1].amount, 1.75);
  });

  test('valid payload passes through unchanged', () {
    final d = parse({
      'merchant': 'Tesco',
      'date': '2026-06-19',
      'currency': 'usd',
      'total': 9.99,
      'vat': 1.50,
      'items': [
        {'name': 'Milk', 'amount': 9.99, 'category': 'Groceries'},
      ],
    });
    expect(d.merchant, 'Tesco');
    expect(d.date, '2026-06-19');
    expect(d.currency, 'USD');
    expect(d.vat, 1.50);
    expect(d.items.single.category, 'Groceries');
  });
}
