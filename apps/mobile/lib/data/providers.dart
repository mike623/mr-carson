import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';
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
