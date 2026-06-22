import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';

void main() {
  test('create with no filePath inserts a received row with null filePath', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = PendingRepository(db);

    final id = await repo.create();

    final row = await repo.getById(id);
    expect(row, isNotNull);
    expect(row!.status, PendingStatus.received.name);
    expect(row.filePath, isNull);
  });
}
