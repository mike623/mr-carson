# Mr. Carson — Telegram AI Expense Assistant

A local-first, privacy-respecting Telegram bot that turns receipt photos into structured expenses
and answers natural-language questions about your spending. All LLM inference runs locally via Ollama — no data leaves your machine.

```
Telegram → Telegraf bot → Hono API → Mastra Agent → Tools → DuckDB
                                                  ↘ Ollama
                                                      ├── glm-ocr        (receipt OCR)
                                                      └── mistral-small  (chat + extraction)
```

## Features

- **Receipt scanning** — send a photo; the bot OCRs it, extracts line items and totals, then asks you to confirm before saving
- **Natural-language queries** — ask "How much did I spend on groceries last week?" and get a direct answer
- **Spending charts** — `/chart` renders a category breakdown chart via QuickChart
- **Conversation memory** — chat history is retained per user across sessions; `/new` starts a fresh thread
- **Allow-list access control** — only configured Telegram user IDs can interact with the bot
- **Fully local** — Ollama runs everything; no OpenAI key, no cloud LLM

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Node.js](https://nodejs.org) | ≥ 20.10.0 | Runtime |
| [pnpm](https://pnpm.io) | ≥ 9 | Package manager |
| [Docker](https://docs.docker.com/get-docker/) | any | Full local stack |
| [Ollama](https://ollama.com) | any | Local LLM runtime (Docker handles this) |

## Quick start

### Option A — Docker (recommended)

1. Copy `.env.example` to `.env` and fill in:
   ```bash
   TELEGRAM_BOT_TOKEN=...        # from @BotFather
   TELEGRAM_ALLOWED_USER_IDS=... # your Telegram numeric user ID
   ```

2. Boot the stack:
   ```bash
   pnpm install
   pnpm docker:up
   ```

3. Pull models into the Ollama container (first time only):
   ```bash
   docker compose -f infrastructure/docker/docker-compose.yml exec ollama \
     ollama pull glm-ocr
   docker compose -f infrastructure/docker/docker-compose.yml exec ollama \
     ollama pull mistral-small
   ```

4. Send `/start` to your bot in Telegram.

### Option B — Local dev

1. Install [Ollama](https://ollama.com) and pull the models:
   ```bash
   ollama pull glm-ocr
   ollama pull mistral-small
   ```

2. Copy and edit `.env`:
   ```bash
   cp .env.example .env
   ```

3. Install, migrate, and start:
   ```bash
   pnpm install
   pnpm db:migrate
   pnpm db:seed
   pnpm dev
   ```

> [!NOTE]
> On first start, Ollama downloads models and compiles them. Receipt processing may take 30–60 seconds on a cold start — the bot's Telegram timeout is extended to 5 minutes to accommodate this.

## Commands

### Development

```bash
pnpm dev                # run all apps in watch mode
pnpm build              # build all packages and apps
pnpm typecheck          # tsc --noEmit across the workspace
pnpm test               # vitest across the workspace
```

### Database

```bash
pnpm db:migrate         # apply DuckDB schema
pnpm db:seed            # seed default category taxonomy
pnpm db:backup          # copy full DB to ./data/backups/mr-carson-YYYY-MM-DD.duckdb
pnpm db:export-csv      # export all tables to ./data/exports/YYYY-MM-DD/*.csv
```

`BACKUP_DIR` and `EXPORT_DIR` environment variables override the default output paths.

### Mastra Studio

```bash
pnpm --filter @mr-carson/api studio   # open agent playground at localhost:4111
```

### Docker

```bash
pnpm docker:up          # start full stack (api + bot + ollama)
pnpm docker:down        # stop and remove containers
```

## Bot commands

| Command | Description |
|---------|-------------|
| `/start` | Introduction message |
| `/help` | List available commands |
| `/new` | Start a fresh chat thread (history is retained, context is cleared) |
| `/summary` | Spending summary for the current month |
| `/chart` | Category breakdown chart for the last 30 days |
| `/categories` | List all expense categories |
| *any text* | Natural-language spending query |
| *photo* | Ingest a receipt |

## Receipt flow

1. User sends a receipt photo via Telegram.
2. Bot uploads it to the API as a file.
3. API runs `glm-ocr` with a `"Text Recognition:"` prompt → raw receipt text.
4. `mistral-small` runs `extractReceipt` → structured `Expense` JSON with normalized categories.
5. Bot replies with an itemized preview and inline **Confirm / Reject** buttons.
6. On confirm, the expense and its line items are written to DuckDB.

The `pending_receipts` table tracks in-flight receipts across the `PENDING → INSERTED | REJECTED | FAILED`
lifecycle so a restart never loses an unconfirmed receipt.

## Architecture

```
apps/
  api/              Hono server + Mastra agent + all AI tools
  telegram-bot/     Telegraf bot — allow-list, photo and text handlers
packages/
  shared-types/     Zod schemas shared by bot and api
  database/         DuckDB client, schema, typed repositories, seed data
infrastructure/
  docker/           docker-compose.yml + Dockerfiles
```

**Two storage layers:**
- **DuckDB** (`DUCKDB_PATH`) — expenses, items, categories, pending receipts
- **LibSQL** (`MEMORY_DB_PATH`) — Mastra conversation memory (per user/thread)

The API runs as a single Mastra dev process that owns the DuckDB writer — running separate processes against the same DuckDB file will cause locking errors.

## Required models

| Model | Size | Purpose |
|-------|------|---------|
| `glm-ocr` | ~2.2 GB | [Z.ai GLM-OCR](https://ollama.com/library/glm-ocr) — purpose-built document OCR, #1 on OmniDocBench V1.5 |
| `mistral-small` | ~5 GB | Chat + structured expense extraction |

## Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | — | yes | Token from @BotFather |
| `TELEGRAM_ALLOWED_USER_IDS` | — | yes | Comma-separated Telegram numeric user IDs |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | — | Ollama endpoint |
| `OLLAMA_MODEL` | `mistral-small` | — | Chat and extraction model |
| `OLLAMA_OCR_MODEL` | `glm-ocr` | — | OCR vision model |
| `DUCKDB_PATH` | `./data/mr-carson.duckdb` | — | Expense database file path |
| `MEMORY_DB_PATH` | `./data/memory.db` | — | Mastra memory (LibSQL) file path |
| `API_PORT` | `47821` | — | API server port |
| `API_URL` | — | yes (bot) | Bot → API base URL |
| `DEFAULT_CURRENCY` | — | — | Currency shown in replies |
| `LOG_LEVEL` | `info` | — | `debug` / `info` / `warn` / `error` / `silent` |
| `QUICKCHART_URL` | `https://quickchart.io/chart` | — | Chart render endpoint |
| `UPLOADS_DIR` | `./data/uploads` | — | Receipt upload directory |
| `BACKUP_DIR` | `./data/backups` | — | `db:backup` output directory |
| `EXPORT_DIR` | `./data/exports/<date>` | — | `db:export-csv` output directory |

## Security

- **Allow-list** is enforced at the bot edge — requests from unlisted user IDs are silently dropped before reaching the API.
- **No raw SQL from the LLM** — the agent produces structured tool arguments; repositories compile them into parameterized queries.
- **Local inference only** — receipt images and financial data never leave the machine.

> [!WARNING]
> Do not expose the API port publicly. The API has no authentication of its own and relies entirely on the bot's allow-list guard.
