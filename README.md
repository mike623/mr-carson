# Mr. Carson — Telegram AI Expense Assistant

A local-first, privacy-respecting Telegram bot that turns receipt photos into structured
expenses and answers natural-language questions about your spending.

```
Telegram → Telegraf bot → Hono API → Mastra Agent → Tools → DuckDB
                                                  ↘ Ollama
                                                      ├── glm-ocr (OCR)
                                                      └── mistral-small (chat + extraction)
```

## Stack

| Layer        | Choice                                                |
| ------------ | ----------------------------------------------------- |
| Bot          | Telegraf (Node.js)                                    |
| API          | Hono + Mastra                                         |
| LLM runtime  | Ollama — `mistral-small` for chat, `glm-ocr` for OCR  |
| Storage      | DuckDB (expenses) + LibSQL (conversation memory)      |
| Monorepo     | pnpm workspaces + Turborepo                           |
| Local deploy | Docker Compose                                        |

## Layout

```
apps/
  telegram-bot/   Telegraf entry, allow-list, photo + text handlers
  api/            Hono server + Mastra agent + all AI tools
packages/
  shared-types/   Zod schemas shared by bot and api
  database/       DuckDB client, schema, repositories, seed data
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
4. Pull the models inside the Ollama container (first time only):
   ```bash
   docker compose -f infrastructure/docker/docker-compose.yml exec ollama \
     ollama pull glm-ocr
   docker compose -f infrastructure/docker/docker-compose.yml exec ollama \
     ollama pull mistral-small
   ```
5. In Telegram, send `/start` to your bot.
6. Send a receipt photo. The bot OCRs it, extracts items, and asks you to confirm.

## Common commands

```bash
pnpm dev               # run all apps in dev mode
pnpm build             # build all packages + apps
pnpm typecheck         # tsc --noEmit across the workspace
pnpm db:migrate        # apply DuckDB schema
pnpm db:seed           # seed default category taxonomy
pnpm docker:up         # full local stack (api + bot + ocr + ollama)
```

## Required models

Run inside the `ollama` container:

```bash
ollama pull glm-ocr           # 0.9B vision model — receipt OCR
ollama pull mistral-small     # text model — chat + structured extraction
```

`glm-ocr` is [Z.ai's GLM-OCR](https://ollama.com/library/glm-ocr) — purpose-built
for document OCR (#1 on OmniDocBench V1.5). About 2.2 GB quantized.

## Conversation flow

1. User sends a receipt photo.
2. Bot uploads it to the API.
3. API → Ollama `glm-ocr` ("Text Recognition:") → raw receipt text.
4. API → Ollama `mistral-small` (`extractReceipt` tool) → strict Expense JSON
   with categories normalized against the seeded taxonomy.
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
