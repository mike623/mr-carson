# Mr. Carson — Telegram AI Expense Assistant

A local-first, privacy-respecting Telegram bot that turns receipt photos into structured
expenses and answers natural-language questions about your spending.

```
Telegram → Telegraf bot → NestJS API → Mastra Agent → Tools → DuckDB
                                                   ↘ GLM-OCR sidecar
                                                   ↘ Ollama (local LLM)
```

## Stack

| Layer        | Choice                                                |
| ------------ | ----------------------------------------------------- |
| Bot          | Telegraf (Node.js)                                    |
| API          | NestJS + Mastra                                       |
| LLM runtime  | Ollama (`mistral-small` by default, env-overridable)  |
| OCR          | GLM-OCR via Python FastAPI sidecar                    |
| Storage      | DuckDB (single embedded file)                         |
| Monorepo     | pnpm workspaces + Turborepo                           |
| Local deploy | Docker Compose                                        |

## Layout

```
apps/
  telegram-bot/   Telegraf entry, allow-list, photo + text handlers
  api/            NestJS app, hosts the Mastra agent over HTTP
  ocr-service/    Python FastAPI wrapping GLM-OCR
packages/
  shared-types/   zod schemas shared by bot, api, tools
  database/       DuckDB client, schema, repositories, seed data
  ai-tools/       Mastra agent + tools (ocr, extract, insert, query, analytics)
infrastructure/
  docker/         docker-compose.yml + Dockerfiles
```

## Quick start (local)

1. Install [pnpm](https://pnpm.io) and [Docker](https://docs.docker.com/get-docker/).
2. Copy `.env.example` to `.env` and fill in:
   - `TELEGRAM_BOT_TOKEN` from [@BotFather](https://t.me/BotFather)
   - `TELEGRAM_ALLOWED_USER_IDS` with your Telegram numeric user id
3. Boot the stack:
   ```bash
   pnpm install
   pnpm db:migrate
   pnpm docker:up
   ```
4. In Telegram, send `/start` to your bot.
5. Send a receipt photo. The bot OCRs it, extracts items, and asks you to confirm.

## Common commands

```bash
pnpm dev               # run all apps in dev mode
pnpm build             # build all packages + apps
pnpm typecheck         # tsc --noEmit across the workspace
pnpm db:migrate        # apply DuckDB schema
pnpm db:seed           # seed default category taxonomy
pnpm docker:up         # full local stack (api + bot + ocr + ollama)
```

## Required services

- **Ollama** running with `mistral-small` (or whatever `OLLAMA_MODEL` is set to)
  pulled: `ollama pull mistral-small`
- **OCR sidecar** loads GLM-OCR weights from
  [`zai-org/GLM-OCR`](https://huggingface.co/zai-org/GLM-OCR) on first start
  (allow several GB and a few minutes the first time).

## Conversation flow

1. User sends a photo / PDF.
2. Bot uploads it to the API.
3. API → GLM-OCR sidecar → structured (or raw) text.
4. Mastra agent normalizes into expense JSON with category mapping.
5. Bot replies with itemized preview + inline Confirm / Edit / Reject buttons.
6. On Confirm, the API inserts into DuckDB (`expenses` + `expense_items`).
7. User can ask follow-up questions ("How much on Pets last week?"); the agent
   plans a structured `queryExpenses` call rather than ingesting the database.

## Security notes

- Allow-list enforced at the bot edge (`TELEGRAM_ALLOWED_USER_IDS`).
- All SQL goes through parameterized repositories — the LLM only produces tool
  arguments, never raw SQL.
- Uploaded receipt files live in `./data/uploads/` and can be auto-deleted after
  successful insert (off by default).
