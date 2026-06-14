import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/ui_models.dart';
import 'db/app_database.dart';
import 'repositories/expense_repository.dart';
import 'repositories/pending_repository.dart';

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

/// Riverpod provider for [ExpenseRepository] (read-side / UI data layer).
final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(ref.watch(appDatabaseProvider));
});

/// Streams the most recent expenses for the ledger list.
final recentExpensesProvider = StreamProvider<List<ExpenseSummary>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchRecentExpenses();
});

/// Streams the spending summary for the current calendar month (donut + total).
final monthlySummaryProvider = StreamProvider<MonthlySummary>((ref) {
  return ref.watch(expenseRepositoryProvider).watchMonthlySummary(DateTime.now());
});

/// Streams a single expense + its line items, keyed by expense id.
final expenseDetailProvider =
    StreamProvider.family<ExpenseDetail?, String>((ref, id) {
  return ref.watch(expenseRepositoryProvider).watchExpenseById(id);
});

/// Streams the active (in-flight) pending receipts — processing or awaiting
/// confirmation.
final pendingReceiptsProvider =
    StreamProvider<List<PendingExpense>>((ref) {
  return ref.watch(pendingRepositoryProvider).watchActive();
});

/// Streams a single active pending receipt by id, or null if it is no longer
/// active (inserted / rejected / failed / not found). Derived from
/// [pendingReceiptsProvider] so the confirm screen reacts to the same stream
/// that drives the ledger's pending list.
final pendingReceiptByIdProvider =
    Provider.family<AsyncValue<PendingExpense?>, String>((ref, id) {
  return ref.watch(pendingReceiptsProvider).whenData((rows) {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  });
});
