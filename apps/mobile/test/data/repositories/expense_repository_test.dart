import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

void main() {
  group('ExpenseRepository', () {
    late AppDatabase db;
    late ExpenseRepository repo;

    setUp(() {
      db = _makeDb();
      repo = ExpenseRepository(db);
    });

    tearDown(() => db.close());

    test('empty DB → watchRecentExpenses emits []', () async {
      final result = await repo.watchRecentExpenses().first;
      expect(result, isEmpty);
    });

    test('insert expense → watchRecentExpenses emits it as ExpenseSummary',
        () async {
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Tesco',
          date: '2024-03-15',
          currency: 'GBP',
          total: 12.50,
          items: [
            ExpenseItemDraft(name: 'Milk', amount: 12.50, category: 'Groceries')
          ],
        ),
      );

      final list = await repo.watchRecentExpenses().first;
      expect(list, hasLength(1));
      expect(list.first.merchant, equals('Tesco'));
      expect(list.first.currency, equals('GBP'));
      expect(list.first.total, equals(12.50));
      expect(list.first.date, equals('2024-03-15'));
    });

    test(
        'two expenses in different categories → watchMonthlySummary has correct total and buckets',
        () async {
      final month = DateTime(2024, 3);
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Tesco',
          date: '2024-03-10',
          currency: 'GBP',
          total: 20.0,
          items: [
            ExpenseItemDraft(
                name: 'Bread', amount: 20.0, category: 'Groceries')
          ],
        ),
      );
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Costa',
          date: '2024-03-15',
          currency: 'GBP',
          total: 10.0,
          items: [
            ExpenseItemDraft(name: 'Coffee', amount: 10.0, category: 'Dining')
          ],
        ),
      );

      final summary = await repo.watchMonthlySummary(month).first;
      expect(summary.total, closeTo(30.0, 0.01));
      expect(summary.buckets, hasLength(2));
      final categories = summary.buckets.map((b) => b.category).toSet();
      expect(categories, containsAll(['Groceries', 'Dining']));
    });

    test('empty DB → watchMonthlySummary emits zero total', () async {
      final summary = await repo.watchMonthlySummary(DateTime(2024, 3)).first;
      expect(summary.total, equals(0.0));
      expect(summary.buckets, isEmpty);
    });

    test('watchExpenseById emits ExpenseDetail with items', () async {
      final id = await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Sainsbury',
          date: '2024-03-20',
          currency: 'GBP',
          total: 35.0,
          items: [
            ExpenseItemDraft(
                name: 'Eggs', amount: 15.0, category: 'Groceries'),
            ExpenseItemDraft(
                name: 'Wine', amount: 20.0, category: 'Dining'),
          ],
        ),
      );

      final detail = await repo.watchExpenseById(id).first;
      expect(detail, isNotNull);
      expect(detail!.merchant, equals('Sainsbury'));
      expect(detail.items, hasLength(2));
    });

    test('watchExpenseById unknown id emits null', () async {
      final detail = await repo.watchExpenseById('no-such-id').first;
      expect(detail, isNull);
    });
  });

  group('PendingRepository.watchActive', () {
    late AppDatabase db;
    late PendingRepository repo;

    setUp(() {
      db = _makeDb();
      repo = PendingRepository(db);
    });

    tearDown(() => db.close());

    test('empty DB → watchActive emits []', () async {
      final list = await repo.watchActive().first;
      expect(list, isEmpty);
    });

    test('after create → status is received → included in watchActive',
        () async {
      await repo.create(filePath: '/tmp/receipt.jpg');
      final list = await repo.watchActive().first;
      expect(list, hasLength(1));
      expect(list.first.status, equals(PendingStatus.received.name));
    });

    test('terminal status (inserted) is excluded from watchActive', () async {
      final id = await repo.create(filePath: '/tmp/receipt.jpg');
      await repo.setStatus(id, PendingStatus.inserted);
      final list = await repo.watchActive().first;
      expect(list, isEmpty);
    });

    test('awaitingConfirmation is included in watchActive', () async {
      final id = await repo.create(filePath: '/tmp/receipt.jpg');
      await repo.setStatus(id, PendingStatus.awaitingConfirmation);
      final list = await repo.watchActive().first;
      expect(list, hasLength(1));
      expect(list.first.status,
          equals(PendingStatus.awaitingConfirmation.name));
    });
  });
}
