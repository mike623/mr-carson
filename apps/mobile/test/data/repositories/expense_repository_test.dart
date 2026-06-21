import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/expense_repository.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/domain/models/expense_summary.dart';
import 'package:mr_carson/domain/models/monthly_summary.dart';
import 'package:mr_carson/domain/models/expense_detail.dart';

AppDatabase _makeDb() => AppDatabase(NativeDatabase.memory());

/// Polls [condition] every 20 ms until it returns true or [timeout] elapses.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) =>
    Future.doWhile(() async {
      if (condition()) return false;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return true;
    }).timeout(timeout);

void main() {
  group('ExpenseRepository', () {
    late AppDatabase db;
    late ExpenseRepository repo;

    setUp(() {
      db = _makeDb();
      repo = ExpenseRepository(db);
    });

    tearDown(() => db.close());

    // ── happy-path one-shot tests ────────────────────────────────────────────

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

    test('updateExpense amends merchant/total/date/categories, keeps items',
        () async {
      final id = await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Tesco',
          date: '2024-03-15',
          currency: 'GBP',
          total: 12.50,
          items: [
            ExpenseItemDraft(name: 'Milk', amount: 12.50, category: 'Groceries')
          ],
          categories: ['Groceries'],
        ),
      );

      await db.updateExpense(
        id,
        merchant: 'Waitrose',
        total: 20.00,
        date: '2024-04-01',
        categories: ['Groceries', 'Household'],
      );

      final detail = await db.watchExpenseById(id).first;
      expect(detail, isNotNull);
      expect(detail!.merchant, equals('Waitrose'));
      expect(detail.total, equals(20.00));
      expect(detail.date, equals('2024-04-01'));
      expect(detail.categories, equals(['Groceries', 'Household']));
      // Line items are left as filed.
      expect(detail.items, hasLength(1));
      expect(detail.items.first.name, equals('Milk'));
    });

    test('deleteExpense removes the expense and its items', () async {
      final id = await db.insertExpense(
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

      await db.deleteExpense(id);

      expect(await db.watchExpenseById(id).first, isNull);
      expect(await repo.watchRecentExpenses().first, isEmpty);
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
      // F2: expense-level categories derived from the distinct line-item set
      expect(detail.categories, containsAll(['Groceries', 'Dining']));
    });

    test('watchExpenseById unknown id emits null', () async {
      final detail = await repo.watchExpenseById('no-such-id').first;
      expect(detail, isNull);
    });

    // ── F3: MonthlySummary.total == Σ bucket amounts ─────────────────────────

    test(
        'F3: MonthlySummary.total equals sum of category-bucket amounts',
        () async {
      final month = DateTime(2024, 5);
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'ACME Grocers',
          date: '2024-05-03',
          currency: 'GBP',
          total: 45.0,
          items: [
            ExpenseItemDraft(
                name: 'Apples', amount: 15.0, category: 'Groceries'),
            ExpenseItemDraft(
                name: 'Chicken', amount: 30.0, category: 'Groceries'),
          ],
        ),
      );
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Gas Station',
          date: '2024-05-10',
          currency: 'GBP',
          total: 60.0,
          items: [
            ExpenseItemDraft(
                name: 'Fuel', amount: 60.0, category: 'Transport')
          ],
        ),
      );
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Cineworld',
          date: '2024-05-18',
          currency: 'GBP',
          total: 24.0,
          items: [
            ExpenseItemDraft(
                name: 'Tickets', amount: 24.0, category: 'Entertainment')
          ],
        ),
      );

      final summary = await repo.watchMonthlySummary(month).first;
      final bucketSum =
          summary.buckets.fold<double>(0.0, (acc, b) => acc + b.total);
      expect(summary.total, closeTo(bucketSum, 0.01),
          reason: 'total must equal the sum of all category-bucket amounts');
      expect(summary.total, closeTo(129.0, 0.01));
      expect(summary.buckets, hasLength(3));
    });

    // ── F4: stream-reactivity tests ──────────────────────────────────────────

    test('F4 watchRecentExpenses: emits new row after insert', () async {
      // Subscribe first and keep subscription open across both events.
      final emissions = <List<ExpenseSummary>>[];
      final sub = repo.watchRecentExpenses().listen(emissions.add);
      addTearDown(sub.cancel);

      // Await initial empty emission.
      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.first, isEmpty);

      // Insert after the subscription is live.
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Lidl',
          date: '2024-04-01',
          currency: 'GBP',
          total: 8.0,
          items: [
            ExpenseItemDraft(
                name: 'Yogurt', amount: 8.0, category: 'Groceries')
          ],
        ),
      );

      // Await a non-empty emission.
      await _waitUntil(() => emissions.any((e) => e.isNotEmpty));

      final second = emissions.lastWhere((e) => e.isNotEmpty);
      expect(second, hasLength(1));
      expect(second.first.merchant, equals('Lidl'));
    });

    test('F4 watchMonthlySummary: emits updated total after insert', () async {
      final month = DateTime(2024, 6);

      // Subscribe first and keep subscription open.
      final emissions = <MonthlySummary>[];
      final sub = repo.watchMonthlySummary(month).listen(emissions.add);
      addTearDown(sub.cancel);

      // Await initial zero-total emission.
      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.first.total, equals(0.0));

      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Boots',
          date: '2024-06-15',
          currency: 'GBP',
          total: 22.0,
          items: [
            ExpenseItemDraft(
                name: 'Vitamins', amount: 22.0, category: 'Health')
          ],
        ),
      );

      // Await a non-zero emission.
      await _waitUntil(() => emissions.any((s) => s.total > 0));

      final second = emissions.lastWhere((s) => s.total > 0);
      expect(second.total, closeTo(22.0, 0.01));
      expect(second.buckets, hasLength(1));
    });

    test('F4 watchExpenseById: emits again after a table write', () async {
      // Insert the expense first so we have an id to watch.
      final id = await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Pret',
          date: '2024-06-20',
          currency: 'GBP',
          total: 7.5,
          items: [
            ExpenseItemDraft(
                name: 'Sandwich', amount: 7.5, category: 'Dining')
          ],
        ),
      );

      // Subscribe and collect emissions — keep the subscription alive.
      final emissions = <ExpenseDetail?>[];
      final sub = repo.watchExpenseById(id).listen(emissions.add);
      addTearDown(sub.cancel);

      // Await initial emission.
      await _waitUntil(() => emissions.isNotEmpty);
      expect(emissions.first, isNotNull);
      expect(emissions.first!.items, hasLength(1));

      final countBefore = emissions.length;

      // Write to a tracked table (expenses + expense_items) — drift must
      // re-run the query and emit a second event even though the watched row
      // hasn't changed (proves it's a live watch, not a one-shot get()).
      await db.insertExpense(
        const ExpenseDraft(
          merchant: 'Pret2',
          date: '2024-06-21',
          currency: 'GBP',
          total: 5.0,
          items: [
            ExpenseItemDraft(name: 'Coffee', amount: 5.0, category: 'Dining')
          ],
        ),
      );

      // Await the second (reactive) emission.
      await _waitUntil(() => emissions.length > countBefore);

      final second = emissions.last;
      expect(second, isNotNull);
      expect(second!.merchant, equals('Pret'));
      expect(second.items, hasLength(1));
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
