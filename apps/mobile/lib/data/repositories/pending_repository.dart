import 'package:drift/drift.dart' hide QueryRow;
import 'package:uuid/uuid.dart';

import '../../domain/models/ai_models.dart';
import '../db/app_database.dart';

// Convenience alias so callers can reference the drift-generated row type
// without importing tables.dart directly.
typedef PendingRow = PendingExpense;

const _uuid = Uuid();

/// Repository for the pending-receipt confirmation lifecycle.
///
/// Wraps [AppDatabase] with typed methods that mirror the TypeScript
/// `pendingRepo` in `apps/api/src/pipeline.ts`.
///
/// State machine: received → awaitingConfirmation → inserted | rejected
///                                                └→ failed
class PendingRepository {
  PendingRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new pending receipt row with status [PendingStatus.received].
  ///
  /// Returns the generated UUID for the new row.
  Future<String> create({required String filePath}) async {
    final id = _uuid.v4();
    await _db.into(_db.pendingExpenses).insert(
          PendingExpensesCompanion.insert(
            id: id,
            status: PendingStatus.received.name,
            filePath: Value(filePath),
          ),
        );
    return id;
  }

  /// Updates the status of an existing pending receipt row.
  ///
  /// Only non-null optional fields are written; omitted fields are left
  /// unchanged.
  Future<void> setStatus(
    String id,
    PendingStatus status, {
    String? rawOcr,
    String? extractedJson,
    String? errorMessage,
  }) async {
    await (_db.update(_db.pendingExpenses)
          ..where((t) => t.id.equals(id)))
        .write(
      PendingExpensesCompanion(
        status: Value(status.name),
        rawOcr: rawOcr != null ? Value(rawOcr) : const Value.absent(),
        extractedJson:
            extractedJson != null ? Value(extractedJson) : const Value.absent(),
        errorMessage:
            errorMessage != null ? Value(errorMessage) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Returns the [PendingRow] for [id], or `null` if not found.
  Future<PendingRow?> getById(String id) {
    return (_db.select(_db.pendingExpenses)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Streams pending receipts the user still needs to act on:
  /// in-flight ([received], [ocrComplete]), ready ([awaitingConfirmation]),
  /// or [failed] — failed rows stay so the user can retry without re-uploading.
  /// Terminal states ([inserted], [rejected]) are excluded.
  Stream<List<PendingRow>> watchActive() {
    return (_db.select(_db.pendingExpenses)
          ..where((t) => t.status.isIn([
                PendingStatus.received.name,
                PendingStatus.ocrComplete.name,
                PendingStatus.awaitingConfirmation.name,
                PendingStatus.failed.name,
              ]))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }
}
