import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mr_carson/ai/gemma_service.dart';
import 'package:mr_carson/ai/receipt_ocr_engine.dart';
import 'package:mr_carson/ai/receipt_pipeline.dart';
import 'package:mr_carson/data/db/app_database.dart';
import 'package:mr_carson/data/providers.dart';
import 'package:mr_carson/data/receipt_image_store.dart';
import 'package:mr_carson/data/repositories/pending_repository.dart';
import 'package:mr_carson/domain/models/ai_models.dart';
import 'package:mr_carson/features/shell/shell_view_model.dart';

// ---------------------------------------------------------------------------
// Fake receipt image store — copies nothing, returns a fixed stable path
// ---------------------------------------------------------------------------

class _FakeReceiptImageStore extends ReceiptImageStore {
  const _FakeReceiptImageStore(this.stablePath);
  final String stablePath;

  @override
  Future<ReceiptImageCopy> copyReceipt(String sourcePath) async {
    return ReceiptImageCopy(path: stablePath, imageHash: 'fake-hash');
  }

  @override
  Future<void> deleteReceipt(String filePath) async {}
}

// ---------------------------------------------------------------------------
// Recording receipt image store — tracks deleteReceipt calls for F-B test
// ---------------------------------------------------------------------------

class _RecordingReceiptImageStore extends ReceiptImageStore {
  final List<String> deletedPaths = [];

  @override
  Future<ReceiptImageCopy> copyReceipt(String sourcePath) async {
    return ReceiptImageCopy(path: sourcePath, imageHash: 'fake-hash');
  }

  @override
  Future<void> deleteReceipt(String filePath) async {
    deletedPaths.add(filePath);
  }
}

// ---------------------------------------------------------------------------
// Recording pipeline — tracks reject calls for F-B test
// ---------------------------------------------------------------------------

class _RecordingPipeline extends ReceiptPipelineService {
  _RecordingPipeline({required AppDatabase db, required PendingRepository repo})
      : super(GemmaOcrEngine(GemmaService()), db, repo);

  final List<String> rejectedIds = [];

  @override
  Future<void> reject(String pendingId) async {
    rejectedIds.add(pendingId);
  }

  @override
  Future<ReceiptResult> processReceipt(String imagePath) async {
    return ReceiptResult.failure('pid', 'not used');
  }

  @override
  Future<String> commitConfirmed(String pendingId, ExpenseDraft draft) async {
    return 'fake-expense-id';
  }
}

// ---------------------------------------------------------------------------
// Fake pipeline — records calls, returns a fixed result immediately
// ---------------------------------------------------------------------------

class _FakePipeline extends ReceiptPipelineService {
  _FakePipeline({
    required AppDatabase db,
    required PendingRepository repo,
    required this.processResult,
  }) : super(GemmaOcrEngine(GemmaService()), db, repo);

  final ReceiptResult processResult;

  int processCallCount = 0;
  String? lastProcessedPath;

  @override
  Future<ReceiptResult> processReceipt(String imagePath) async {
    processCallCount++;
    lastProcessedPath = imagePath;
    return processResult;
  }

  @override
  Future<String> commitConfirmed(String pendingId, ExpenseDraft draft) async {
    return 'fake-expense-id';
  }

  @override
  Future<void> reject(String pendingId) async {}
}

// ---------------------------------------------------------------------------
// Pipeline that blocks processReceipt until a Completer fires
// ---------------------------------------------------------------------------

class _CompleterPipeline extends ReceiptPipelineService {
  _CompleterPipeline({
    required AppDatabase db,
    required PendingRepository repo,
    required this.completer,
  }) : super(GemmaOcrEngine(GemmaService()), db, repo);

  final Completer<ReceiptResult> completer;
  int processCallCount = 0;

  @override
  Future<ReceiptResult> processReceipt(String imagePath) {
    processCallCount++;
    return completer.future;
  }

  @override
  Future<String> commitConfirmed(String pendingId, ExpenseDraft draft) async =>
      'fake-id';

  @override
  Future<void> reject(String pendingId) async {}
}

// ---------------------------------------------------------------------------
// Fake pipeline that throws on reject — for F4 test
// ---------------------------------------------------------------------------

class _FailingRejectPipeline extends ReceiptPipelineService {
  _FailingRejectPipeline({required AppDatabase db, required PendingRepository repo})
      : super(GemmaOcrEngine(GemmaService()), db, repo);

  @override
  Future<void> reject(String pendingId) async {
    throw Exception('DB error during reject');
  }

  @override
  Future<ReceiptResult> processReceipt(String imagePath) async {
    return ReceiptResult.failure('pid', 'not used');
  }
}

// ---------------------------------------------------------------------------
// Helper — builds a container AND subscribes a listener so the AutoDispose
// shellViewModelProvider stays alive throughout the test body.
// Returns both container and the subscription (caller adds tearDowns).
// ---------------------------------------------------------------------------

({ProviderContainer container, ProviderSubscription<ShellState> sub})
    buildContainer({
  required ReceiptPipelineService pipeline,
  XFile? pickedFile,
  bool pickerThrows = false,
  AppDatabase? db,
  PendingRepository? repo,
}) {
  // db/repo are positional only to avoid capturing late vars from outer scope;
  // callers pass them explicitly.
  final container = ProviderContainer(
    overrides: [
      if (db != null) appDatabaseProvider.overrideWithValue(db),
      if (repo != null) pendingRepositoryProvider.overrideWithValue(repo),
      receiptPipelineProvider.overrideWithValue(pipeline),
      receiptImageStoreProvider.overrideWithValue(
        const _FakeReceiptImageStore('/stable/receipt.jpg'),
      ),
      imagePickerFnProvider.overrideWithValue((source) async {
        if (pickerThrows) throw Exception('picker error');
        return pickedFile;
      }),
    ],
  );
  // Subscribe a listener so AutoDispose does NOT tear down the provider
  // between async gaps in the test.
  final sub = container.listen<ShellState>(
    shellViewModelProvider,
    (_, __) {},
  );
  return (container: container, sub: sub);
}

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

  test('F1 — after picking, navigates to ledger immediately (no await on process)',
      () async {
    // A Completer lets us control when processReceipt finishes, proving that
    // navigation happens BEFORE it completes (i.e. it's truly detached).
    final completer = Completer<ReceiptResult>();
    final pipeline = _CompleterPipeline(
      db: db,
      repo: pendingRepo,
      completer: completer,
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);

    // capturePhoto() returns once it has: picked, copied, navigated, and
    // launched the unawaited background work. The Completer is not resolved
    // yet, so processReceipt is still in-flight.
    await vm.capturePhoto();

    // Must already be on ledger — even though processReceipt has not completed.
    expect(
      container.read(shellViewModelProvider).screen,
      equals(ShellScreen.ledger),
    );
    expect(container.read(shellViewModelProvider).reviewingId, isNull);
    expect(pipeline.processCallCount, equals(1));

    // Complete the background work so no dangling futures leak out of the test.
    completer.complete(ReceiptResult.failure('pid', 'done'));
    await Future<void>.delayed(Duration.zero); // drain
  });

  test('F1 — processReceipt success does NOT auto-navigate to confirm', () async {
    final createdPendingId =
        await pendingRepo.create(filePath: '/stable/receipt.jpg');

    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.success(
        createdPendingId,
        const ExpenseDraft(
          merchant: 'Nero',
          date: '2026-06-17',
          currency: 'GBP',
          total: 5.0,
          items: [],
        ),
      ),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();
    await Future<void>.delayed(Duration.zero); // drain unawaited work

    // Even on success: stays on ledger, no auto-nav to confirm
    final state = container.read(shellViewModelProvider);
    expect(state.screen, equals(ShellScreen.ledger));
    expect(state.screen, isNot(equals(ShellScreen.confirm)));
    expect(state.reviewingId, isNull);
  });

  test('F1 — processReceipt failure shows toast, stays on ledger', () async {
    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.failure('pid', 'OCR failed'),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();
    // Pump the event loop so the unawaited processReceipt future completes
    // and the failure toast fires.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shellViewModelProvider);
    expect(state.screen, equals(ShellScreen.ledger));
    expect(state.toast, isNotNull);
    expect(state.toast, contains('could not read'));
  });

  test('F1 — "model is not loaded" failure maps to a setup-needed toast',
      () async {
    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.failure(
        'pid',
        'Bad state: GemmaService: model is not loaded. Call loadModel()…',
      ),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shellViewModelProvider);
    expect(state.toast, contains('not ready yet'));
    expect(state.toast, isNot(contains('could not read')));
  });

  test('F1 — generic failure surfaces the real error in the toast', () async {
    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.failure('pid', 'FormatException: bad JSON'),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shellViewModelProvider);
    expect(state.toast, contains('could not read'));
    expect(state.toast, contains('FormatException'));
  });

  test('F1 — user cancel (null file) does nothing', () async {
    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.failure('pid', 'not used'),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: null, // user cancelled
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();

    final state = container.read(shellViewModelProvider);
    // Screen unchanged (still ask — the initial default)
    expect(state.screen, equals(ShellScreen.ask));
    expect(pipeline.processCallCount, equals(0));
  });

  test('F-D — duplicate image (matching hash) is blocked: no OCR, dedup toast',
      () async {
    // Seed an expense carrying the same hash the fake store returns ('fake-hash').
    await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Nero',
        date: '2026-06-20',
        currency: 'GBP',
        total: 4.5,
        items: [],
      ),
      imageHash: 'fake-hash',
    );

    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.failure('pid', 'not used'),
    );

    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFile: XFile('/tmp/photo.jpg'),
      db: db,
      repo: pendingRepo,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.capturePhoto();
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shellViewModelProvider);
    expect(pipeline.processCallCount, equals(0)); // OCR skipped
    expect(state.toast, contains('already have'));
  });

  test('F-B — discardConfirm calls deleteReceipt with stored path and rejects the row',
      () async {
    const storedPath = '/stable/receipt_fb.jpg';
    final recordingStore = _RecordingReceiptImageStore();
    final recordingPipeline = _RecordingPipeline(db: db, repo: pendingRepo);

    // Seed a pending row that has a filePath stored in the DB — this is what
    // discardConfirm must look up to know which file to delete.
    final pendingId = await pendingRepo.create(filePath: storedPath);
    await pendingRepo.setStatus(
      pendingId,
      PendingStatus.awaitingConfirmation,
      extractedJson: '{}',
    );

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        pendingRepositoryProvider.overrideWithValue(pendingRepo),
        receiptPipelineProvider.overrideWithValue(recordingPipeline),
        receiptImageStoreProvider.overrideWithValue(recordingStore),
        imagePickerFnProvider.overrideWithValue((_) async => null),
      ],
    );
    final sub = container.listen<ShellState>(shellViewModelProvider, (_, __) {});
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.discardConfirm(pendingId);

    // reject must have been called with the correct pending id
    expect(recordingPipeline.rejectedIds, contains(pendingId));

    // deleteReceipt must have been called with the file path from the DB row
    expect(recordingStore.deletedPaths, contains(storedPath));
  });

  test('F4 — discardConfirm wraps errors and shows toast', () async {
    final pipeline = _FailingRejectPipeline(db: db, repo: pendingRepo);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        pendingRepositoryProvider.overrideWithValue(pendingRepo),
        receiptPipelineProvider.overrideWithValue(pipeline),
        receiptImageStoreProvider.overrideWithValue(
          const _FakeReceiptImageStore('/stable/receipt.jpg'),
        ),
      ],
    );
    // Keep alive via listener
    final sub = container.listen<ShellState>(
      shellViewModelProvider,
      (_, __) {},
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    // Should not throw — error is caught and shown as toast
    await vm.discardConfirm('any-pending-id');

    final state = container.read(shellViewModelProvider);
    expect(state.toast, isNotNull);
    expect(state.toast, contains('discard'));
    // Screen should not have navigated away (still ask, the default)
    expect(state.screen, equals(ShellScreen.ask));
  });
}
