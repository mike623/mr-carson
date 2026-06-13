# Mr. Carson — Design Implementation Tracking

Source design: Claude Design handoff bundle, fetched 2026-06-12.
Bundle extracted to `designs/mr-carson/`. Primary file:
`designs/mr-carson/project/Mr Carson.dc.html`.

**Locked direction** (from `chats/chat1.md`): **Brass & Ink** theme, dark-first,
iOS-first. Type: Cormorant Garamond (display/numerals) + Hanken Grotesk (UI).
Butler persona, high-whimsy copy ("Very good, sir."). The exploratory "Livery"
theme switcher was removed — locked to Brass & Ink.

Target: the Flutter app at `apps/mobile/`. The design HTML is a prototype; we
recreate it faithfully in Flutter widgets and wire to the existing data/AI layer
(drift + flutter_gemma services) where a real backend exists.

## Status

| Design screen (.dc.html) | Flutter target | Status |
|---|---|---|
| Design system (brass palette + type) | `lib/theme/app_theme.dart` | ✅ done |
| Onboarding: welcome / privacy / download | `lib/features/onboarding/onboarding_screen.dart` | ✅ done |
| Ask / chat (hero) | `lib/features/ask/ask_screen.dart` | ✅ done |
| Ledger (donut + pending + recent) | `lib/features/ledger/ledger_screen.dart` | ✅ done |
| Expense detail | `lib/features/detail/detail_screen.dart` | ✅ done |
| Confirm expense | `lib/features/confirm/confirm_screen.dart` | ✅ done |
| Bottom nav + add sheet + toast | `lib/features/shell/app_shell.dart` | ✅ done |
| App shell / routing / main.dart | `lib/main.dart` | ✅ done |

All screens built (4 in parallel via subagents) + integrated. `flutter analyze lib/`
→ **No issues found**. Each screen is a self-contained widget on the shared theme.

### Verified on simulator (iPhone 16 Pro)
Ran all 9 screens live (idb-driven). All match the design. iOS scaffolding added
(`flutter create`), deployment target 16.0, MediaPipe static linkage — builds + runs.

### Architecture refactor (flutter-apply-architecture-best-practices skill)
- MVVM: screens are dumb Consumer views; logic moved into riverpod `Notifier`
  ViewModels — `onboarding_view_model.dart`, `ask_view_model.dart`,
  `shell_view_model.dart`.
- Shared `CarsonMonogram` extracted to `lib/ui/core/widgets/`.
- ViewModels wired to the real providers (`gemmaServiceProvider`,
  `chatServiceProvider`, `receiptPipelineProvider`) with a mock fallback so the
  app still demos without the 3 GB model. Visuals byte-identical (re-verified).

### Tests (flutter-add-widget-test skill)
- `test/features/{onboarding,ledger,confirm}/…` + smoke test. `flutter test` →
  **+8 all pass**. `GoogleFonts.allowRuntimeFetching=false`, no timer leaks.

### Still mock / not yet done
- **Real model**: `kDefaultModelUrl` is a placeholder. Download/streaming/pending
  run on the mock fallback until a real Gemma 3n `.litertlm` URL is set + hosted.
- Ledger/detail/confirm still render prototype mock data (no live query yet).

## Design tokens (Brass & Ink) — see `lib/theme/app_theme.dart`

```
bg #15120D  surface #1F1B14  surface-2 #2A2419  line C9A86A@16%
ink #F3ECDD  ink-2 #F3ECDD@62%  ink-3 #F3ECDD@34%
accent #C9A86A  accent-soft C9A86A@14%  accent-ink #191510
warn #D8A45E  grocery #9DB58C  transport #8FA9C2  house #C98F6A
```

## Wiring notes

- Chat hero → `chatServiceProvider` (streaming tokens, suggested prompts).
- Confirm → `receiptPipelineProvider.commitConfirmed` / `reject`.
- Ledger pending cards → pending lifecycle (`pendingRepositoryProvider`).
- Onboarding download → `gemmaServiceProvider.downloadModel` progress stream.
- Charts → `AppDatabase.byCategoryOverTime` / `queryExpenses`.
- Mock data from the prototype (The Wolseley, Caffè Nero, etc.) is used as
  seed/placeholder where the live query isn't wired yet — flagged in code.
