import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/receipt_image_store.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';

/// A [ReceiptImageStore] that never touches the filesystem — returns a fixed
/// stable path + hash so the capture pipeline can be exercised without a real
/// picker or app-documents directory.
class _FakeImageStore extends ReceiptImageStore {
  _FakeImageStore({required this.hash});

  final String hash;
  String? persistedFrom;
  final List<String> cleaned = [];

  @override
  Future<StoredReceiptImage> persist(String sourcePath) async {
    persistedFrom = sourcePath;
    return StoredReceiptImage(path: '/stable/receipts/x.jpg', imageHash: hash);
  }

  @override
  Future<void> cleanup(String path) async {
    cleaned.add(path);
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer(_FakeImageStore store) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        receiptImageStoreProvider.overrideWithValue(store),
      ],
    );
    // Keep the autoDispose shell notifier alive for the duration of the test —
    // otherwise it is disposed after each `read` and re-reads reset to build().
    container.listen(shellViewModelProvider, (_, __) {}, fireImmediately: true);
    addTearDown(container.dispose);
    return container;
  }

  test(
      'startUpload with an injected path persists via the store and creates a '
      'pending row (no live picker needed)', () async {
    final store = _FakeImageStore(hash: 'hash-abc');
    final container = makeContainer(store);
    final vm = container.read(shellViewModelProvider.notifier);

    await vm.startUpload(imagePath: '/picker/tmp/photo.jpg');

    // The store was asked to copy the picked file.
    expect(store.persistedFrom, '/picker/tmp/photo.jpg');

    // A pending row now exists for the stored image (OCR may have failed since
    // there is no real Gemma model, but the row lifecycle was driven for real).
    final rows = await db.select(db.pendingExpenses).get();
    expect(rows, hasLength(1));
    expect(rows.first.filePath, '/stable/receipts/x.jpg');

    // Navigation moved to the ledger.
    expect(container.read(shellViewModelProvider).screen, ShellScreen.ledger);
  });

  test('startUpload skips processing for a duplicate image hash', () async {
    // Pre-insert an expense carrying the same image hash.
    await db.into(db.expenses).insert(
          ExpensesCompanion.insert(
            id: 'e1',
            merchant: 'Tesco',
            date: '2026-06-10',
            currency: 'GBP',
            total: 9.99,
            imageHash: const Value('dup-hash'),
          ),
        );

    final store = _FakeImageStore(hash: 'dup-hash');
    final container = makeContainer(store);
    final vm = container.read(shellViewModelProvider.notifier);

    await vm.startUpload(imagePath: '/picker/tmp/dup.jpg');

    // The duplicate was cleaned up and no pending row was created.
    expect(store.cleaned, contains('/stable/receipts/x.jpg'));
    final pending = await db.select(db.pendingExpenses).get();
    expect(pending, isEmpty);
  });
}
