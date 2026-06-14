import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/ai/receipt_pipeline.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/receipt_image_store.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  late AppDatabase db;
  late PendingRepository pending;
  late ReceiptPipelineService pipeline;
  late Directory tmpDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    pending = PendingRepository(db);
    // commitConfirmed never touches the model, so a bare GemmaService is fine.
    // A real ReceiptImageStore is used so its hashFile reads the temp file the
    // same way the up-front dedup pre-check does.
    pipeline =
        ReceiptPipelineService(GemmaService(), db, pending, ReceiptImageStore());
    tmpDir = await Directory.systemTemp.createTemp('receipt_pipeline_test');
  });

  tearDown(() async {
    await db.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  ExpenseDraft draft() => const ExpenseDraft(
        merchant: 'Tesco',
        date: '2026-06-10',
        currency: 'GBP',
        total: 12.50,
        vat: null,
        items: [
          ExpenseItemDraft(name: 'Milk', amount: 2.5, category: 'Groceries'),
          ExpenseItemDraft(name: 'Bread', amount: 10.0, category: 'Groceries'),
        ],
      );

  /// Writes [bytes] to a fresh temp file and returns its path.
  Future<String> writeImage(List<int> bytes) async {
    final file = File('${tmpDir.path}/receipt_${bytes.hashCode}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Creates a pending row and advances it to awaitingConfirmation so that
  /// commitConfirmed accepts it.
  Future<String> makeAwaitingPending(String filePath) async {
    final id = await pending.create(filePath: filePath);
    await pending.setStatus(id, PendingStatus.awaitingConfirmation);
    return id;
  }

  test(
    'commitConfirmed persists image_hash matching ReceiptImageStore format, '
    'making findByImageHash detect a re-upload',
    () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      final imagePath = await writeImage(bytes);

      // Hash exactly as ReceiptImageStore.persist does (hex digest).
      final expectedHash = sha256.convert(bytes).toString();

      final pendingId = await makeAwaitingPending(imagePath);
      final expenseId = await pipeline.commitConfirmed(pendingId, draft());

      // The expense row carries the recomputed hash...
      final stored = await (db.select(db.expenses)
            ..where((t) => t.id.equals(expenseId)))
          .getSingle();
      expect(stored.imageHash, expectedHash);

      // ...and the pre-check used by the capture flow now finds it.
      final found = await db.findByImageHash(expectedHash);
      expect(found, expenseId);
    },
  );

  test('commitConfirmed succeeds even when the image file is missing', () async {
    final missingPath = '${tmpDir.path}/does_not_exist.jpg';
    final pendingId = await makeAwaitingPending(missingPath);

    // Must not throw; hash is simply left null.
    final expenseId = await pipeline.commitConfirmed(pendingId, draft());

    final stored = await (db.select(db.expenses)
          ..where((t) => t.id.equals(expenseId)))
        .getSingle();
    expect(stored.imageHash, isNull);
  });
}
