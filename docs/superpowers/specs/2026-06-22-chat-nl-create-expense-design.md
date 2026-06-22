# Create expense by natural language from chat

**Date:** 2026-06-22
**Status:** Approved — ready for implementation plan

## Goal

Let the user record a new expense by typing it in plain language on the chat
(Ask) screen — e.g. "spent £12 on lunch at Wagamama yesterday" — instead of only
uploading a receipt photo or using Manual Entry. Mr. Carson extracts the
expense and either files it directly or opens a prefilled review sheet,
depending on how complete the extraction is.

## Background

The chat agent (`apps/mobile/lib/ai/chat_service.dart`) runs a bounded native
function-calling loop over three **read-only** tools (`queryExpenses`,
`topMerchants`, `chartSpending`). It has no way to *write* an expense.

The expense write path already exists and is reused wholesale:

- `ExpenseDraft` (`domain/models/ai_models.dart`) — the structured expense.
- `AppDatabase.insertExpense(draft)` — persists an expense + line items.
- Pending lifecycle: `PendingRepository.create()` → `setStatus(awaitingConfirmation, extractedJson)`
  → **Confirm screen** loads the draft from the pending row → `saveConfirm`
  → `ReceiptPipelineService.commitConfirmed` → `insertExpense`.
- `commitConfirmed` already tolerates a **null `filePath`** (`_hashOf(null)` → null),
  so a chat-created draft with no image flows through unchanged.

The `ChartReady` event is the established precedent for surfacing a tool's
output from inside the `send` stream up to the UI.

## Decisions

1. **Review surface for the low-confidence path: reuse the Confirm screen.**
   It already takes an `ExpenseDraft` and renders editable merchant / total /
   all 11 categories / line items with Save / Discard. No new screen.
2. **Routing rule: deterministic field completeness** (not model self-rating —
   Gemma 4 E2B is unreliable at judging its own certainty):

   ```
   merchant non-empty AND total > 0  →  insert directly
   otherwise                         →  open Confirm screen prefilled
   ```

## Flow

```
User: "spent £12 on lunch at Wagamama yesterday"
  → model calls addExpense(merchant:"Wagamama", total:12, category:"Dining", date:"yesterday")
  → _runTool builds ExpenseDraft (coerced)
     ├─ confident (merchant + total>0):
     │     insertExpense(draft); return {saved:true, summary}
     │     → model narrates "Filed, sir — £12 at Wagamama, Dining."
     │     → reactive ledger shows the row (no extra wiring)
     └─ low confidence:
           pendingRepo.create() + setStatus(awaitingConfirmation, extractedJson)
           return {needsReview:true}; emit DraftReady(pendingId)
           → AskViewModel: shell.reviewPending(pendingId) → Confirm screen, prefilled
```

## Components (all in existing files — no new screens)

### 1. `chat_service.dart` — new native FC tool `addExpense`

Added to the `_tools` list. Schema:

| field | type | notes |
|---|---|---|
| `merchant` | string | required-ish; empty ⇒ low confidence |
| `total` | number | required-ish; ≤0 or missing ⇒ low confidence |
| `category` | string (enum `kDefaultCategories`) | unknown ⇒ coerced to `Other` |
| `date` | string, optional | `YYYY-MM-DD` \| `today` \| `yesterday` |
| `currency` | string, optional | default `kDefaultCurrency` |
| `items` | array `[{name, amount, category}]`, optional | synthesized when absent |

Description instructs the model to call it when the user states/logs a
purchase ("I spent", "I bought", "paid", "add", "log…") and to never invent an
amount.

### 2. `_runTool` → `addExpense` case

Builds an `ExpenseDraft` with light, tolerant coercion (reuse the spirit of
`ReceiptPipelineService.coerceDraftJson` — loose num/string handling):

- `date`: map `today`/`yesterday` to ISO; pass through `YYYY-MM-DD`; default today.
- `category`: if not in `kDefaultCategories`, use `Other`.
- `currency`: default `kDefaultCurrency`; uppercase; 3-char guard.
- `items`: if none given, synthesize one `{name: merchant (or "Expense"), amount: total, category}`
  so the ledger's top-item category renders (mirrors Manual Entry).

Branch on `merchant.trim().isNotEmpty && total > 0`:

- **confident** → `_db.insertExpense(draft)`; return `{'_tool':'addExpense', 'saved': true, 'merchant':…, 'total':…, 'currency':…, 'category':…}`.
- **low** → `pendingRepo.create()` then `setStatus(id, awaitingConfirmation, extractedJson: jsonEncode(draft.toJson()))`;
  return `{'_tool':'addExpense', 'needsReview': true}`; the loop emits `DraftReady(id)`.

Never throws — failures return `{'error': …}` like the other tools.

### 3. New `ChatEvent` `DraftReady(pendingId)`

Mirror of `ChartReady`. Emitted from `send` only on the low-confidence branch
(yielded alongside the `ToolCallStarted` / tool-response handling, same as
`ChartReady`).

### 4. `ChatService` gains a `PendingRepository` dependency

Constructor `ChatService(this._gemma, this._db, this._pending)`; the
`chatServiceProvider` wires `ref.watch(pendingRepositoryProvider)` (already
exists).

### 5. `AskViewModel` handles `DraftReady`

In the `send().listen` switch, add a `DraftReady(:final pendingId)` case that
calls `ref.read(shellViewModelProvider.notifier).reviewPending(pendingId)`.
That swaps the shell to the Confirm screen (the autoDispose Ask VM tears down
its stream subscription on navigation — fine, the draft is already persisted).
No new event is needed for the confident path: model narration + the reactive
ledger are sufficient.

### 6. `prompts.dart` — persona guidance + today's date

- Add an `addExpense` section to `kChatSystemPersona`: when to call it, the
  hard rule never to invent an amount, prefer a category from the taxonomy.
- Inject today's date so the model can resolve relative dates beyond
  today/yesterday. `kChatSystemPersona` is `const`; supply today via a small
  extra chunk in `ChatService.start()` (a second `addQueryChunk`) rather than
  making the whole persona a builder.

### 7. `pending_repository.dart` — optional `filePath`

`create({String? filePath})` (currently `{required String filePath}`). The
column is already a nullable `Value`; the receipt caller
`create(filePath: imagePath)` is unaffected.

## Tradeoffs / notes

- A low-confidence draft is a genuine `awaitingConfirmation` pending row, so it
  also surfaces as a **resumable pending card** in the ledger
  (`PendingRepository.watchActive`). With `filePath == null` the card's image is
  skipped (`existsSync` guard). Acceptable, arguably a feature: the user can
  resume an abandoned draft from the ledger.
- **No "undo"** on direct insert. Carson's narrated confirmation is the
  acknowledgement; the existing edit/delete flow covers mistakes. Add an undo
  toast later only if wanted.
- Intent detection (log-an-expense vs ask-a-question) relies on the on-device
  model. Mitigated by an explicit persona rule; misfires are recoverable
  (a wrong direct insert is editable/deletable; a wrong review sheet is
  discardable).

## Testing

- **Tool routing** (`chat_service` test):
  - confident input → an expense row exists in the DB after the call.
  - low-confidence input (empty merchant or total ≤ 0) → a pending row in
    `awaitingConfirmation` with the expected `extractedJson`, and `DraftReady`
    is emitted (no expense row written).
- **Coercion**: `today`/`yesterday`/ISO date resolution; unknown category →
  `Other`; missing currency → `kDefaultCurrency`; missing items → one
  synthesized item equal to the total.
- **`AskViewModel`**: a `DraftReady` event triggers `reviewPending` with the
  pending id (shell screen becomes `confirm`).

## Out of scope

- Editing an *existing* expense via chat (only creation here).
- Multi-expense extraction from one message.
- Undo toast on direct insert.
