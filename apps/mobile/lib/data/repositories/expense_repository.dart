import '../db/app_database.dart';
import '../../domain/models/ai_models.dart';
import '../../domain/models/expense_summary.dart';
import '../../domain/models/monthly_summary.dart';
import '../../domain/models/expense_detail.dart';

/// Thin wrapper around [AppDatabase] that exposes reactive streams for the UI.
///
/// All heavy lifting (SQL, mapping) lives in [AppDatabase]; this repository
/// is the Riverpod-visible seam for dependency injection and testing.
typedef ChartData = ({
  List<CategoryBucket> rows,
  Granularity granularity,
  String currency
});

class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  Stream<List<ExpenseSummary>> watchRecentExpenses({int limit = 50}) =>
      _db.watchRecentExpenses(limit: limit);

  Stream<MonthlySummary> watchMonthlySummary(DateTime month) =>
      _db.watchMonthlySummary(month);

  Stream<ExpenseDetail?> watchExpenseById(String id) =>
      _db.watchExpenseById(id);

  Future<ChartData> categorySpending(
    QueryExpensesArgs args, {
    Granularity granularity = Granularity.week,
  }) =>
      _db.byCategoryOverTime(args, granularity: granularity);
}
