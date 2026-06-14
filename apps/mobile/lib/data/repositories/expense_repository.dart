import 'dart:async';

import '../../domain/models/ai_models.dart';
import '../../domain/models/ui_models.dart';
import '../db/app_database.dart';

/// Read-side repository for the reactive UI data layer (spec §1).
///
/// Wraps [AppDatabase] and exposes streaming projections shaped for the ledger,
/// monthly donut, and detail surfaces, plus a one-shot chart pass-through. All
/// money is already rounded to 2dp by the database layer.
class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  /// Streams the most recent expenses, newest first. Emits on every write to
  /// `expenses` / `expense_items`.
  Stream<List<ExpenseSummary>> watchRecentExpenses({int limit = 50}) {
    return _db.watchRecentExpenses(limit: limit);
  }

  /// Streams the spending rollup for the calendar month containing [month]
  /// (only year+month are used). Combines the expense-level total/count with the
  /// per-category line-item breakdown for the donut. Re-emits whenever either
  /// underlying query changes.
  Stream<MonthlySummary> watchMonthlySummary(DateTime month) {
    final bounds = _monthBounds(month);
    final monthKey = bounds.start.substring(0, 7); // YYYY-MM

    final totals = _db.watchMonthlyTotals(start: bounds.start, end: bounds.end);
    final byCategory =
        _db.watchMonthlyByCategory(start: bounds.start, end: bounds.end);

    return _combineLatest2(
      totals,
      byCategory,
      (t, cats) => MonthlySummary(
        month: monthKey,
        total: t.total,
        currency: t.currency,
        expenseCount: t.count,
        byCategory: cats,
      ),
    );
  }

  /// Streams a single expense plus its line items, or null if [id] is unknown.
  /// Re-emits when the header or any of its items change.
  Stream<ExpenseDetail?> watchExpenseById(String id) {
    final header = _db.watchExpenseRow(id);
    final items = _db.watchExpenseItems(id);

    return _combineLatest2(header, items, (Expense? row, List<ExpenseItem> its) {
      if (row == null) return null;
      return ExpenseDetail(
        id: row.id,
        merchant: row.merchant,
        date: row.date,
        currency: row.currency,
        total: row.total,
        vat: row.vat,
        sourceFile: row.sourceFile,
        items: its
            .map((i) => ExpenseLineItem(
                  id: i.id,
                  name: i.name,
                  category: i.category,
                  amount: i.amount,
                ))
            .toList(),
      );
    });
  }

  /// Thin pass-through to [AppDatabase.byCategoryOverTime] for the chart tool.
  /// One-shot (charts are rendered on demand, not streamed).
  Future<ChartData> categorySpending(
    QueryExpensesArgs args, {
    Granularity granularity = Granularity.week,
  }) async {
    final result =
        await _db.byCategoryOverTime(args, granularity: granularity);
    return ChartData(
      buckets: result.rows,
      granularity: result.granularity,
      currency: result.currency,
    );
  }

  /// Inclusive 'YYYY-MM-DD' bounds for the calendar month of [month].
  static ({String start, String end}) _monthBounds(DateTime month) {
    final start = DateTime.utc(month.year, month.month, 1);
    final end = DateTime.utc(month.year, month.month + 1, 0); // last day
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    return (start: iso(start), end: iso(end));
  }
}

/// Combines the latest values of two streams. Emits only once both streams have
/// produced at least one value, then on every subsequent value from either.
/// Mirrors rxdart's `combineLatest2` without adding the dependency.
Stream<R> _combineLatest2<A, B, R>(
  Stream<A> streamA,
  Stream<B> streamB,
  R Function(A a, B b) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;

  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;
  var doneA = false;
  var doneB = false;

  void emit() {
    if (hasA && hasB) {
      controller.add(combine(latestA as A, latestB as B));
    }
  }

  void maybeClose() {
    if (doneA && doneB) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subA = streamA.listen(
        (a) {
          latestA = a;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          maybeClose();
        },
      );
      subB = streamB.listen(
        (b) {
          latestB = b;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          maybeClose();
        },
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );

  return controller.stream;
}
