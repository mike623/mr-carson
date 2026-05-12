# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Mr. Carson is a local-first Telegram bot that turns receipt photos into structured expenses and answers natural-language spending questions. All LLM inference runs locally via Ollama.

```
Telegram → Telegraf bot → Hono API → Mastra Agent → Tools → DuckDB
                                                  ↘ Ollama
                                                      ├── glm-ocr  (OCR)
                                                      └── mistral-small (chat + extraction)
```

## Commands

```bash
pnpm dev                          # run all apps in watch mode
pnpm build                        # build all packages + apps
pnpm typecheck                    # tsc --noEmit across workspace
pnpm test                         # vitest across workspace

# Scoped
pnpm --filter @mr-carson/api typecheck
pnpm --filter @mr-carson/api test
pnpm --filter @mr-carson/api test -- src/tools/chartSpending.test.ts

# Database
pnpm db:migrate                   # apply DuckDB schema
pnpm db:seed                      # seed default category taxonomy

# Docker (full local stack)
pnpm docker:up
pnpm docker:down
```

All apps require a `.env` file at repo root (copy `.env.example`). Dev scripts use `dotenv-cli` to load it automatically.

## Monorepo layout

```
apps/
  api/            Hono HTTP server + Mastra agent + all AI tools
  telegram-bot/   Telegraf bot; talks to api/ over HTTP only
packages/
  shared-types/   Zod schemas shared across apps (Expense, OcrResult, query args)
  database/       DuckDB client, schema.sql, typed repositories, seed data
infrastructure/
  docker/         docker-compose.yml + Dockerfiles
```

Note: `README.md` is outdated — it still references NestJS and `packages/ai-tools`, both of which have been removed. The API is now plain Hono.

## apps/api architecture

Everything lives flat in `apps/api/src/`:

| File | Role |
|------|------|
| `main.ts` | Hono server, all 7 routes, bootstrap (migrate + seed), error handler |
| `agent.ts` | `buildAgent()` + `runAgent()` — Mastra agent wiring + structured logging |
| `pipeline.ts` | `processReceipt()` + `commitConfirmed()` — OCR → extract → persist lifecycle |
| `logger.ts` | `JsonLogger` (subclass of MastraLogger) — one JSON line per event to stdout/stderr |
| `llm.ts` | Ollama provider via `@ai-sdk/openai-compatible` |
| `memory.ts` | LibSQL-backed Mastra Memory singleton (chat history) |
| `tools/` | One file per Mastra tool: ocr, extractReceipt, queryExpenses, analytics, chartSpending |

**Agent is built per-request** (`buildAgent(userId, opts)`), not a singleton. This is intentional — `userId` closes over each tool so all DB queries are tenant-scoped at construction time. Do not refactor this into a shared instance.

## Key design decisions

**Two storage layers:**
- DuckDB (`DUCKDB_PATH`) — expense rows, items, categories, `pending_receipts` table
- LibSQL (`MEMORY_DB_PATH`) — Mastra conversation memory (per user/thread)

**Receipt confirmation lifecycle** (`pendingRepo`): `PENDING` → OCR → extraction → user sees preview → `INSERTED` or `REJECTED` or `FAILED`. The `pending_receipts` table tracks state so a restart doesn't lose in-flight receipts.

**Thread management:** `chatSessionsRepo.getOrCreateActiveThread(userId)` returns a stable thread ID per user. `/agent/new` calls `rotateActiveThread` to give the agent a fresh context while keeping history in LibSQL.

**LLM never writes SQL.** The agent produces structured tool arguments; repositories compile them into parameterized queries.

**Chart images** go through QuickChart.io (`QUICKCHART_URL`, defaults to `https://quickchart.io/chart`). The base64 PNG travels through `ChartSink` → `runAgent` return value → API response → Telegram `replyWithPhoto`.

**Shared file volume:** Bot and API share `./data/uploads/` in Docker so receipt file paths are valid on both sides. `bot.ts` uses `existsSync` before `replyWithPhoto` to skip missing files silently.

**Allowlist** is enforced at the bot edge in `bot.ts` middleware — `TELEGRAM_ALLOWED_USER_IDS` is a comma-separated list of Telegram numeric user IDs.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TELEGRAM_BOT_TOKEN` | required | BotFather token |
| `TELEGRAM_ALLOWED_USER_IDS` | required | Comma-separated numeric IDs |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama endpoint |
| `OLLAMA_MODEL` | `mistral-small` | Chat + extraction model |
| `OLLAMA_OCR_MODEL` | `glm-ocr` | OCR vision model |
| `DUCKDB_PATH` | (in-memory) | Expense database file |
| `MEMORY_DB_PATH` | `./data/memory.db` | Mastra memory LibSQL file |
| `DEFAULT_CURRENCY` | — | Currency shown in replies |
| `PORT` | `3001` | API listen port |
| `LOG_LEVEL` | `info` | debug / info / warn / error / silent |
| `QUICKCHART_URL` | `https://quickchart.io/chart` | Chart render endpoint |
| `API_URL` | — | Bot → API base URL |
