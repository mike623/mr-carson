# Batch image upload & processing — design

**Date:** 2026-06-22
**App:** `apps/mobile` (Flutter)
**Status:** approved, pre-implementation

## Goal

Let the user pick multiple images from the photo library in one action and have
each processed into its own pending receipt, instead of repeating the
one-photo-at-a-time upload flow.

## Scope

- **In:** gallery / "Upload from library" path (`startUpload`).
- **Out:** camera capture (`capturePhoto`) stays single-shot — `image_picker`'s
  multi-pick is gallery-only.
- **Out:** combined batch-review screen. Each image becomes its own pending card,
  reviewed/confirmed one at a time via the **existing** confirm flow. No new
  review UI.
- **Out:** parallel OCR, camera multi-capture. Deferred until asked.

## Current flow (single image)

`_pickAndProcess(source)` in `lib/features/shell/shell_view_model.dart`:

1. pick one file via `imagePickerFnProvider`
2. copy to receipt store, hash-dedup against committed expenses
   (`findByImageHash`) — on hit, delete copy + toast "I already have that"
3. navigate to ledger, toast "Reading it in the background"
4. fire-and-forget `receiptPipelineProvider.processReceipt(stablePath)` →
   creates a pending row that surfaces as a ledger card via
   `pendingReceiptsProvider`

The pipeline already supports N independent pending receipts. Batch upload is
therefore a loop over the existing per-file logic — no pipeline changes.

## Design

### 1. Multi-pick provider

Add a multi-image pick function alongside the existing single-pick one:

```dart
typedef MultiImagePickerFn = Future<List<XFile>> Function();
// provider returns: () => picker.pickMultiImage()
```

Keep `imagePickerFnProvider` (single) for the camera path. Add
`multiImagePickerFnProvider` for gallery. Both overridable in tests.

### 2. Extract `_processOneFile`

Pull the copy + hash-dedup + `processReceipt` body out of `_pickAndProcess`
into a reusable helper that reports its outcome so a batch can tally:

```dart
enum _FileOutcome { ok, duplicate, error }

Future<_FileOutcome> _processOneFile(XFile file) async { ... }
```

- `ok`     — copied, not a duplicate, `processReceipt` fired
- `duplicate` — byte-identical to an existing committed expense; copy deleted
- `error`  — copy/save failed

The fire-and-forget `processReceipt` stays inside the helper (per-file pending
row + failed-status surfacing unchanged).

### 3. Camera path (unchanged behaviour)

`capturePhoto` → pick one → `_processOneFile` → toast as today
(single-file toasts: "Reading it in the background" / "I already have that" /
error).

### 4. Gallery batch path

`startUpload` → `_pickAndProcessBatch`:

1. `multiImagePickerFnProvider()` → `List<XFile>`; empty ⇒ cancelled, return.
2. `go(ShellScreen.ledger)` once; toast `"Very good, sir. Reading N in the background."`
3. Sequentially `await _processOneFile(f)` for each file, tallying outcomes.
   - **Sequential**, not parallel — local Ollama OCR; concurrent calls would
     thrash. `// ponytail: sequential; parallelize if throughput matters`.
4. Summary toast from the tally, e.g.
   `"Read 3, skipped 2 duplicates, sir."` (only mention non-zero buckets;
   include errors if any).

Per-file dedup/error toasts are suppressed in batch mode — the summary replaces
them so N images don't spam N toasts.

## Data flow

```
startUpload
  └─ multiImagePickerFnProvider()  → List<XFile>
       └─ for each (sequential): _processOneFile(file)
            ├─ store.copyReceipt + findByImageHash  → ok | duplicate | error
            └─ unawaited processReceipt(path)        → pending row → ledger card
       └─ summary toast from tally
```

## Error handling

- Picker throws → "Could not access the image, sir.", return (whole batch).
- Per-file copy/save failure → counted as `error`, loop continues.
- `processReceipt` failure → surfaced per-row exactly as today (failed pending
  card + `_showReceiptError`), independent of the batch summary.

## Testing

`shell_view_model` test (override providers):

- multi-pick returns 3 files, one byte-identical to an existing expense
  (`findByImageHash` returns non-null for it).
- assert: `processReceipt` called exactly 2×, screen == ledger, summary toast
  reflects "Read 2, skipped 1 duplicate".
- camera path test unchanged (regression guard on `_processOneFile` reuse).

## Files touched

- `lib/features/shell/shell_view_model.dart` — providers, `_processOneFile`
  extraction, `_pickAndProcessBatch`.
- `lib/features/shell/` add-sheet wiring — `startUpload` already bound to the
  "Upload from library" action; no UI change needed.
- `test/features/shell/shell_view_model_test.dart` — batch test.
