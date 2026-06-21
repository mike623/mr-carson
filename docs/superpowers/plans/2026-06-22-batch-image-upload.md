# Batch Image Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick multiple photos from the library in one action; each becomes its own pending receipt card via the existing confirm flow.

**Architecture:** Add a gallery multi-pick provider. Refactor the single-image body of `ShellViewModel` into two pure helpers — `_copyAndCheckDuplicate` (copy + hash dedup) and `_runProcess` (awaitable OCR) — then drive both the camera path (single) and a new batch path (loop) off them. Camera keeps fire-and-forget OCR; batch serializes OCR in one background future and ends with a summary toast.

**Tech Stack:** Flutter, Riverpod (`AutoDisposeNotifier`), `image_picker` (`pickMultiImage`), drift (in-memory DB in tests), `flutter_test`.

## Global Constraints

- All butler toasts end with ", sir." and match the existing voice (e.g. "I already have that receipt, sir.").
- Camera path (`capturePhoto`) behaviour must not change — existing F-series tests stay green.
- Local Ollama OCR: batch OCR runs **sequentially** (await each `processReceipt`), never in parallel.
- Picker seam stays injectable via providers so tests never touch the platform picker.
- File touched: `apps/mobile/lib/features/shell/shell_view_model.dart` and its test. No pipeline/DB/UI-widget changes.

---

## File Structure

- `apps/mobile/lib/features/shell/shell_view_model.dart` — add `MultiImagePickerFn` typedef + `multiImagePickerFnProvider`; refactor `_pickAndProcess` into `_copyAndCheckDuplicate` / `_runProcess`; add `startUpload` batch path + `_processBatch` + `_batchSummary`.
- `apps/mobile/test/features/shell/shell_view_model_test.dart` — add `_PerPathReceiptImageStore`; extend `buildContainer` with `pickedFiles`; add two batch tests.

All commands run from `apps/mobile/`.

---

### Task 1: Multi-pick provider + helper refactor (behaviour-preserving)

Refactor the camera/single path onto two reusable helpers and add the gallery multi-pick provider. Camera behaviour is unchanged; existing tests are the regression guard.

**Files:**
- Modify: `apps/mobile/lib/features/shell/shell_view_model.dart`

**Interfaces:**
- Produces:
  - `typedef MultiImagePickerFn = Future<List<XFile>> Function();`
  - `final multiImagePickerFnProvider = Provider<MultiImagePickerFn>(...)`
  - `enum _PrepOutcome { ready, duplicate, error }`
  - `class _Prep { final _PrepOutcome outcome; final String? stablePath; }`
  - `Future<_Prep> _copyAndCheckDuplicate(XFile file)` — copies to the receipt store and hash-dedups; no toast, no navigation, no OCR.
  - `Future<void> _runProcess(String stablePath)` — awaits `processReceipt`; on `!ok` calls `_showReceiptError`. Camera calls it `unawaited`; batch `await`s it.

- [ ] **Step 1: Add the multi-pick typedef + provider**

After the existing `imagePickerFnProvider` block (ends line 26), add:

```dart
/// Signature for a multi-image gallery pick.
typedef MultiImagePickerFn = Future<List<XFile>> Function();

/// Provider for the [MultiImagePickerFn] used by [ShellViewModel.startUpload].
///
/// Override this in tests to supply fake files without the platform picker.
final multiImagePickerFnProvider = Provider<MultiImagePickerFn>((_) {
  final picker = ImagePicker();
  return () => picker.pickMultiImage();
});
```

- [ ] **Step 2: Add the prep result types**

Add near the bottom of the file, just before the closing of the library (top-level, after the `ShellViewModel` class is fine, or above it):

```dart
/// Outcome of preparing one picked file for processing.
enum _PrepOutcome { ready, duplicate, error }

/// Result of [_copyAndCheckDuplicate]: an outcome plus the stable copy path
/// (non-null only when [outcome] is [_PrepOutcome.ready]).
class _Prep {
  const _Prep(this.outcome, [this.stablePath]);
  final _PrepOutcome outcome;
  final String? stablePath;
}
```

- [ ] **Step 3: Extract `_copyAndCheckDuplicate` and `_runProcess`, rewrite `_pickAndProcess`**

Replace the entire current `_pickAndProcess` method (lines ~198-250) with the three methods below. Logic is identical to today's single-file path, just split so the batch path can reuse it.

```dart
  Future<void> _pickAndProcess(ImageSource source) async {
    final pick = ref.read(imagePickerFnProvider);
    XFile? file;
    try {
      file = await pick(source);
    } catch (_) {
      showToast('Could not access the image, sir.');
      return;
    }
    if (file == null) return; // user cancelled

    final prep = await _copyAndCheckDuplicate(file);
    switch (prep.outcome) {
      case _PrepOutcome.error:
        showToast('Could not save the image, sir.');
        return;
      case _PrepOutcome.duplicate:
        showToast('I already have that receipt, sir.');
        go(ShellScreen.ledger);
        return;
      case _PrepOutcome.ready:
        // Navigate + toast immediately; OCR runs detached (fire-and-forget).
        showToast('Very good, sir. Reading it in the background.');
        go(ShellScreen.ledger);
        unawaited(_runProcess(prep.stablePath!));
        return;
    }
  }

  /// Copies a picked file into the receipt store and hash-dedups it against
  /// committed expenses. No toast, no navigation, no OCR — pure prep so both
  /// the single and batch paths can reuse it.
  Future<_Prep> _copyAndCheckDuplicate(XFile file) async {
    final store = ref.read(receiptImageStoreProvider);
    try {
      final copy = await store.copyReceipt(file.path);
      final existing =
          await ref.read(appDatabaseProvider).findByImageHash(copy.imageHash);
      if (existing != null) {
        await store.deleteReceipt(copy.path);
        return const _Prep(_PrepOutcome.duplicate);
      }
      return _Prep(_PrepOutcome.ready, copy.path);
    } catch (_) {
      return const _Prep(_PrepOutcome.error);
    }
  }

  /// Runs OCR for a prepared receipt. Surfaces failures via [_showReceiptError].
  /// Camera path calls this `unawaited`; the batch loop `await`s it to keep
  /// OCR sequential.
  Future<void> _runProcess(String stablePath) async {
    try {
      final result =
          await ref.read(receiptPipelineProvider).processReceipt(stablePath);
      if (!result.ok) _showReceiptError(result.error);
    } catch (e) {
      _showReceiptError(e.toString());
    }
  }
```

- [ ] **Step 4: Run existing tests to verify behaviour is preserved**

Run: `flutter test test/features/shell/shell_view_model_test.dart`
Expected: PASS — all existing F-series tests green (the camera path is unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/features/shell/shell_view_model.dart
git commit -m "refactor(mobile): extract reusable receipt prep/process helpers"
```

---

### Task 2: Batch gallery path

Wire `startUpload` to multi-pick and process each file sequentially, ending with a summary toast.

**Files:**
- Modify: `apps/mobile/lib/features/shell/shell_view_model.dart`
- Test: `apps/mobile/test/features/shell/shell_view_model_test.dart`

**Interfaces:**
- Consumes: `multiImagePickerFnProvider`, `_copyAndCheckDuplicate`, `_runProcess` (Task 1).
- Produces:
  - `Future<void> startUpload()` (replaces the old `_pickAndProcess(gallery)` binding)
  - `Future<void> _processBatch(List<XFile> files)`
  - `String _batchSummary(int read, int dup, int err)`

- [ ] **Step 1: Add `_PerPathReceiptImageStore` to the test file**

In `test/features/shell/shell_view_model_test.dart`, after `_RecordingReceiptImageStore` (line ~50), add a store that yields a distinct hash/path per source so dedup can distinguish files:

```dart
// ---------------------------------------------------------------------------
// Per-path store — hash == path, so each picked file dedups independently
// ---------------------------------------------------------------------------

class _PerPathReceiptImageStore extends ReceiptImageStore {
  final List<String> deletedPaths = [];

  @override
  Future<ReceiptImageCopy> copyReceipt(String sourcePath) async {
    return ReceiptImageCopy(path: sourcePath, imageHash: sourcePath);
  }

  @override
  Future<void> deleteReceipt(String filePath) async {
    deletedPaths.add(filePath);
  }
}
```

- [ ] **Step 2: Extend `buildContainer` to override the multi-picker**

In `buildContainer` (signature at line ~163), add an optional param and override. Add to the parameter list:

```dart
  List<XFile>? pickedFiles,
  ReceiptImageStore? imageStore,
```

Replace the `receiptImageStoreProvider` override with one that honours an injected store, and add the multi-picker override inside the `overrides: [ ... ]` list:

```dart
      receiptImageStoreProvider.overrideWithValue(
        imageStore ?? const _FakeReceiptImageStore('/stable/receipt.jpg'),
      ),
      imagePickerFnProvider.overrideWithValue((source) async {
        if (pickerThrows) throw Exception('picker error');
        return pickedFile;
      }),
      multiImagePickerFnProvider.overrideWithValue(() async {
        if (pickerThrows) throw Exception('picker error');
        return pickedFiles ?? const <XFile>[];
      }),
```

- [ ] **Step 3: Write the failing batch tests**

Add these two tests inside `main()` (after the existing tests). They drive `startUpload`, then drain the unawaited background loop by pumping the event loop.

```dart
  // Drains N sequential awaits in the detached batch loop.
  Future<void> pumpSettled() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('BATCH — 3 picked, 1 duplicate: processes 2, summary toast', () async {
    // Seed an existing expense whose imageHash == '/tmp/b.jpg' (the dup).
    await db.insertExpense(
      const ExpenseDraft(
        merchant: 'Old',
        date: '2026-01-01',
        currency: 'EUR',
        total: 1,
        items: [],
      ),
      imageHash: '/tmp/b.jpg',
    );

    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.success(
        'pid',
        const ExpenseDraft(
          merchant: 'X',
          date: '2026-01-01',
          currency: 'EUR',
          total: 1,
          items: [],
        ),
      ),
    );
    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFiles: [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg'), XFile('/tmp/c.jpg')],
      db: db,
      repo: pendingRepo,
      imageStore: _PerPathReceiptImageStore(),
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.startUpload();
    await pumpSettled();

    expect(pipeline.processCallCount, 2); // a + c, b skipped
    expect(container.read(shellViewModelProvider).screen, ShellScreen.ledger);
    expect(
      container.read(shellViewModelProvider).toast,
      contains('skipped 1 duplicate'),
    );
  });

  test('BATCH — 2 picked, all new: processes 2, "read 2" summary', () async {
    final pipeline = _FakePipeline(
      db: db,
      repo: pendingRepo,
      processResult: ReceiptResult.success(
        'pid',
        const ExpenseDraft(
          merchant: 'X',
          date: '2026-01-01',
          currency: 'EUR',
          total: 1,
          items: [],
        ),
      ),
    );
    final (:container, :sub) = buildContainer(
      pipeline: pipeline,
      pickedFiles: [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg')],
      db: db,
      repo: pendingRepo,
      imageStore: _PerPathReceiptImageStore(),
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final vm = container.read(shellViewModelProvider.notifier);
    await vm.startUpload();
    await pumpSettled();

    expect(pipeline.processCallCount, 2);
    expect(container.read(shellViewModelProvider).toast, contains('read 2'));
  });
```

> `ReceiptResult.success(String pendingId, ExpenseDraft draft)` and `_FakePipeline(processResult:)` are confirmed against the codebase.

- [ ] **Step 4: Run the tests to verify they fail**

Run: `flutter test test/features/shell/shell_view_model_test.dart --plain-name BATCH`
Expected: FAIL — `startUpload` still calls the old single-pick path (no `processCallCount == 2`), `multiImagePickerFnProvider` unused.

- [ ] **Step 5: Implement `startUpload` + `_processBatch` + `_batchSummary`**

In `shell_view_model.dart`, replace the existing `startUpload` one-liner (line ~194):

```dart
  /// "Upload from library" — pick one OR many via gallery; each picked image
  /// becomes its own pending card via the existing confirm flow.
  Future<void> startUpload() async {
    final pick = ref.read(multiImagePickerFnProvider);
    List<XFile> files;
    try {
      files = await pick();
    } catch (_) {
      showToast('Could not access the image, sir.');
      return;
    }
    if (files.isEmpty) return; // user cancelled

    // Navigate + optimistic toast immediately; processing runs detached.
    showToast('Very good, sir. Reading ${files.length} in the background.');
    go(ShellScreen.ledger);
    unawaited(_processBatch(files));
  }

  /// Sequentially preps + OCRs each picked file (sequential to avoid thrashing
  /// local Ollama), then shows one summary toast. Per-file OCR failures are
  /// surfaced per-row by [_runProcess]; the summary only tallies prep outcomes.
  // ponytail: sequential; parallelize if throughput ever matters.
  Future<void> _processBatch(List<XFile> files) async {
    var read = 0, dup = 0, err = 0;
    for (final file in files) {
      final prep = await _copyAndCheckDuplicate(file);
      switch (prep.outcome) {
        case _PrepOutcome.ready:
          read++;
          await _runProcess(prep.stablePath!); // await → sequential OCR
        case _PrepOutcome.duplicate:
          dup++;
        case _PrepOutcome.error:
          err++;
      }
    }
    showToast(_batchSummary(read, dup, err));
  }

  /// Builds the end-of-batch summary toast from prep tallies.
  String _batchSummary(int read, int dup, int err) {
    final parts = <String>[];
    if (read > 0) parts.add('read $read');
    if (dup > 0) parts.add('skipped $dup ${dup == 1 ? 'duplicate' : 'duplicates'}');
    if (err > 0) parts.add('$err could not be saved');
    return 'Done, sir — ${parts.join(', ')}.';
  }
```

- [ ] **Step 6: Run the batch tests to verify they pass**

Run: `flutter test test/features/shell/shell_view_model_test.dart --plain-name BATCH`
Expected: PASS — both batch tests green.

- [ ] **Step 7: Run the full shell suite + analyzer**

Run: `flutter test test/features/shell/shell_view_model_test.dart && flutter analyze lib/features/shell/shell_view_model.dart`
Expected: All tests PASS, analyzer reports no issues.

- [ ] **Step 8: Commit**

```bash
git add lib/features/shell/shell_view_model.dart test/features/shell/shell_view_model_test.dart
git commit -m "feat(mobile): batch-pick gallery images, process as independent receipts"
```

---

## Self-Review

- **Spec coverage:** gallery-only multi-pick ✅ (Task 1 provider, Task 2 `startUpload`); camera single-shot unchanged ✅ (Task 1 preserves `_pickAndProcess`); N independent pending cards via existing flow ✅ (`_runProcess` → `processReceipt` per file, no new review UI); sequential OCR ✅ (`await _runProcess` in loop + ponytail comment); summary toast replacing per-file spam ✅ (`_batchSummary`); error handling — picker throw, per-file copy error, per-row OCR failure ✅. Test (3 files/1 dup → 2 process calls + summary) ✅.
- **Placeholder scan:** none — all steps carry real code/commands.
- **Type consistency:** `_Prep`/`_PrepOutcome`, `_copyAndCheckDuplicate`, `_runProcess`, `_processBatch`, `_batchSummary`, `multiImagePickerFnProvider`, `MultiImagePickerFn` used consistently across both tasks. `ReceiptResult.success(pendingId, draft)` confirmed against `lib/ai/receipt_pipeline.dart`.
