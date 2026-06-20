# Changelog

All notable changes to Mr. Carson are documented here.

## [0.0.4.0] - 2026-06-17

### Added

- Manual expense entry now persists. The "Enter manually" path (no model needed) writes the expense to the local DB and the DB-reactive Ledger shows it immediately — previously Save was a no-op mock that only toasted.
- On-sim end-to-end test (`integration_test/manual_entry_e2e_test.dart`): Begin → + → Enter manually → fill → Save → assert the row renders in the Ledger.

### Fixed

- Receipt upload failing with a silent "I could not read that receipt, sir." On-device Gemma now lazy-loads an already-installed model on first use, so receipts work after an app restart (previously the model only loaded at the end of a fresh download, leaving `createVisionSession` to throw `model is not loaded`).
- Receipt-processing errors are now surfaced in the toast instead of a generic message; "model not loaded" maps to a clear "not ready yet, finish setup" line.
- Add-expense sheet overflowed by 75px when the "needs model" note was shown — the sheet body is now scrollable.

## [0.0.3.0] - 2026-06-17

### Added

- Opt-in transcript detail in Ask (Settings → "His workings"): toggle "Show his reasoning" to reveal the model's private thinking as a collapsible block, and "Show his workings" to list the ledger lookups (tool calls) behind each reply. Both default off — the chat shows only the narrated answer.

### Fixed

- Raw tool-call JSON (`{"role":"assistant","tool_calls":[…]}`) no longer leaks into Carson's chat answers. A streaming filter strips the leading envelope some models emit as text and surfaces the calls it carried for the opt-in "workings" view instead.

## [0.0.2.0] - 2026-05-15

### Added

- OpenRouter support as a remote LLM gateway — set `OPENROUTER_API_KEY` to route all inference (chat, OCR, agent) through OpenRouter instead of local Ollama. Defaults: `mistralai/mistral-small-3.1-24b-instruct` for chat, `google/gemma-3n-e4b-it:free` for OCR.
- Fly.io deployment config (`infrastructure/fly/`) — single-app setup running API and bot in one container with a shared `/data` volume, targeting ~$2–4/mo on a 512 MB shared-CPU machine.

## [0.0.1.0] - 2026-05-15

### Changed

- Receipt images are now only returned when you explicitly ask to see a receipt or photo. General spending queries (totals, lists, breakdowns) return text only, keeping the chat clean.
- Charts are now only generated when you explicitly request a visual (e.g. "show me a chart", "graph my spending"). Plain questions like "how much did I spend?" use text responses instead.
