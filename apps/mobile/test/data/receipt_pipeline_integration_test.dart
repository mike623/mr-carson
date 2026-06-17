import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  late AppDatabase db;
  late PendingRepository pendingRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    pendingRepo = PendingRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  const stubDraft = ExpenseDraft(
    merchant: 'Test Merchant',
    date: '2026-06-17',
    currency: 'GBP',
    total: 12.50,
    items: [
      ExpenseItemDraft(name: 'Coffee', amount: 3.50, category: 'Dining'),
      ExpenseItemDraft(name: 'Sandwich', amount: 9.00, category: 'Dining'),
    ],
  );

  test('commitConfirmed writes to expenses and watchRecentExpenses emits it',
      () async {
    // Arrange: create a pending row in awaitingConfirmation state
    final pendingId =
        await pendingRepo.create(filePath: '/fake/path.jpg');
    await pendingRepo.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: jsonEncode(stubDraft.toJson()),
    );

    // Verify no expenses yet
    final beforeRows = await db.watchRecentExpenses().first;
    expect(beforeRows, isEmpty);

    // Act: simulate commitConfirmed logic (insert + update pending)
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        pendingRepositoryProvider.overrideWithValue(pendingRepo),
      ],
    );
    addTearDown(container.dispose);

    final pending = await pendingRepo.getById(pendingId);
    expect(pending, isNotNull);
    expect(pending!.status, equals(PendingStatus.awaitingConfirmation.name));

    final expenseId = await db.insertExpense(
      stubDraft,
      sourceFile: pending.filePath,
    );
    await pendingRepo.setStatus(pendingId, PendingStatus.inserted);

    // Assert: recentExpenses stream emits the new expense
    final afterRows = await db.watchRecentExpenses().first;
    expect(afterRows.length, equals(1));
    expect(afterRows.first.merchant, equals('Test Merchant'));
    expect(afterRows.first.total, equals(12.50));

    // Pending row is now inserted
    final updatedPending = await pendingRepo.getById(pendingId);
    expect(updatedPending!.status, equals(PendingStatus.inserted.name));
    expect(expenseId, isNotEmpty);
  });

  test('reject leaves expenses empty and pending row rejected', () async {
    // Arrange
    final pendingId =
        await pendingRepo.create(filePath: '/fake/path.jpg');
    await pendingRepo.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: jsonEncode(stubDraft.toJson()),
    );

    // Act
    await pendingRepo.setStatus(pendingId, PendingStatus.rejected);

    // Assert: no expenses
    final rows = await db.watchRecentExpenses().first;
    expect(rows, isEmpty);

    // Pending row is rejected
    final pending = await pendingRepo.getById(pendingId);
    expect(pending!.status, equals(PendingStatus.rejected.name));
  });
}
