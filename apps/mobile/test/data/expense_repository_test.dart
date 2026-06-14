import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  ExpenseDraft draft({
    String merchant = 'Tesco',
    String date = '2026-06-10',
    String currency = 'GBP',
    double total = 12.50,
    double? vat,
    List<ExpenseItemDraft> items = const [
      ExpenseItemDraft(name: 'Milk', amount: 2.5, category: 'Groceries'),
      ExpenseItemDraft(name: 'Bread', amount: 10.0, category: 'Groceries'),
    ],
  }) =>
      ExpenseDraft(
        merchant: merchant,
        date: date,
        currency: currency,
        total: total,
        vat: vat,
        items: items,
      );

  test('watchRecentExpenses emits empty then updates on insert', () async {
    final stream = repo.watchRecentExpenses();
    final first = await stream.first;
    expect(first, isEmpty);

    await db.insertExpense(draft());

    final next = await stream.firstWhere((rows) => rows.isNotEmpty);
    expect(next, hasLength(1));
    expect(next.first.merchant, 'Tesco');
    expect(next.first.itemCount, 2);
    expect(next.first.total, 12.50);
  });

  test('watchRecentExpenses orders newest date first', () async {
    await db.insertExpense(draft(merchant: 'Old', date: '2026-01-01'));
    await db.insertExpense(draft(merchant: 'New', date: '2026-06-01'));

    final rows = await repo.watchRecentExpenses().firstWhere((r) => r.length == 2);
    expect(rows.map((e) => e.merchant).toList(), ['New', 'Old']);
  });

  test('watchMonthlySummary totals and category buckets for the month',
      () async {
    // In June 2026 — counted.
    await db.insertExpense(draft(
      merchant: 'A',
      date: '2026-06-05',
      total: 30,
      items: const [
        ExpenseItemDraft(name: 'X', amount: 20, category: 'Groceries'),
        ExpenseItemDraft(name: 'Y', amount: 10, category: 'Dining'),
      ],
    ));
    // In May 2026 — excluded.
    await db.insertExpense(draft(merchant: 'B', date: '2026-05-30', total: 99));

    final summary = await repo
        .watchMonthlySummary(DateTime.utc(2026, 6, 15))
        .firstWhere((s) => s.expenseCount > 0);

    expect(summary.month, '2026-06');
    expect(summary.total, 30);
    expect(summary.expenseCount, 1);
    expect(summary.currency, 'GBP');
    // Groceries (20) before Dining (10), descending.
    expect(summary.byCategory.map((c) => c.category).toList(),
        ['Groceries', 'Dining']);
    expect(summary.byCategory.first.total, 20);
  });

  test('watchMonthlySummary emits empty summary for a month with no data',
      () async {
    final summary =
        await repo.watchMonthlySummary(DateTime.utc(2026, 6, 15)).first;
    expect(summary.total, 0);
    expect(summary.expenseCount, 0);
    expect(summary.byCategory, isEmpty);
    expect(summary.currency, kDefaultCurrency);
  });

  test('watchExpenseById emits expense with line items, then null for unknown',
      () async {
    final id = await db.insertExpense(draft(merchant: 'Cafe', total: 7.5));

    final detail = await repo.watchExpenseById(id).firstWhere((d) => d != null);
    expect(detail!.merchant, 'Cafe');
    expect(detail.items, hasLength(2));
    expect(detail.items.map((i) => i.name), containsAll(['Milk', 'Bread']));

    final missing = await repo.watchExpenseById('nope').first;
    expect(missing, isNull);
  });

  test('categorySpending passes through byCategoryOverTime', () async {
    await db.insertExpense(draft(date: '2026-06-10'));
    final chart = await repo.categorySpending(
      const QueryExpensesArgs(
        startDate: '2026-06-01',
        endDate: '2026-06-30',
      ),
      granularity: Granularity.month,
    );
    expect(chart.granularity, Granularity.month);
    expect(chart.currency, 'GBP');
    expect(chart.buckets, isNotEmpty);
    expect(chart.buckets.first.category, 'Groceries');
  });
}
