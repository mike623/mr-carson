import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';
import 'repositories/expense_repository.dart';
import 'repositories/pending_repository.dart';
import '../domain/models/expense_summary.dart';
import '../domain/models/monthly_summary.dart';
import '../domain/models/expense_detail.dart';

/// Riverpod provider for [AppDatabase].
///
/// Registers [AppDatabase.close] so the native database handle is released
/// when the provider scope is torn down.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Riverpod provider for [PendingRepository].
final pendingRepositoryProvider = Provider<PendingRepository>((ref) {
  return PendingRepository(ref.watch(appDatabaseProvider));
});

/// Riverpod provider for [ExpenseRepository].
final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(appDatabaseProvider));
});

/// Stream of the 50 most recent expenses, ordered by date descending.
final recentExpensesProvider = StreamProvider<List<ExpenseSummary>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchRecentExpenses();
});

/// Stream of the monthly spending summary for the current calendar month.
// ponytail: current month captured at build; add autoDispose+midnight invalidation
// (e.g. a Timer.periodic that calls ref.invalidateSelf() at the next midnight)
// if month-rollover-without-restart matters.
final monthlySummaryProvider = StreamProvider<MonthlySummary>((ref) {
  final now = DateTime.now();
  return ref
      .watch(expenseRepositoryProvider)
      .watchMonthlySummary(DateTime(now.year, now.month));
});

/// Stream of a single expense with its line items.
/// Returns `null` when the id is not found.
final expenseDetailProvider =
    StreamProvider.family<ExpenseDetail?, String>((ref, id) {
  return ref.watch(expenseRepositoryProvider).watchExpenseById(id);
});

/// Stream of pending receipts that are still in-flight (non-terminal status).
final pendingReceiptsProvider = StreamProvider<List<PendingRow>>((ref) {
  return ref.watch(pendingRepositoryProvider).watchActive();
});
