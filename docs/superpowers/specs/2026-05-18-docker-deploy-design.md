# Docker 24/7 Deploy — Mac mini

**Date:** 2026-05-18  
**Branch:** abundant-vegetarian

## Goal

Run mr-carson continuously on an Apple Silicon Mac mini using Docker Desktop.  
LLM inference via OpenRouter (remote). No local Ollama container.

## Architecture

Two Docker services:
- `api` — Hono server + Mastra agent + all tools
- `bot` — Telegraf Telegram bot

Both have `restart: unless-stopped`. Docker Desktop starts on login → containers recover automatically on reboot.

## Files Changed

### `infrastructure/docker/docker-compose.yml`

- Remove `ollama` service and `ollama_models` volume
- Remove all `OLLAMA_*` env vars from `api`
- Add `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `OPENROUTER_OCR_MODEL` to `api`
- Add `restart: unless-stopped` to `api` and `bot`
- Add `logging` (json-file, max-size 10m, max-file 3) to both services
- Add `healthcheck` to `api`: `curl -f http://localhost:47821/health`
- Update `bot.depends_on` to wait for `api` healthcheck (condition: service_healthy)

### `apps/api/src/main.ts`

Add one route before existing routes:
```ts
app.get('/health', (c) => c.json({ status: 'ok' }))
```

### `apps/telegram-bot/src/bot.ts`

Register `/health` command:
- Calls `GET /health` on the API
- Reports: API status, active model names (`OPENROUTER_MODEL`, `OPENROUTER_OCR_MODEL`), DuckDB path
- Reply format: plain text, one line per item

### `.env.example`

- Remove `OLLAMA_BASE_URL`, `OLLAMA_MODEL`, `OLLAMA_OCR_MODEL`
- Add `OPENROUTER_API_KEY=sk-or-...`, `OPENROUTER_MODEL`, `OPENROUTER_OCR_MODEL`
- Keep `OLLAMA_*` lines as comments (fallback if user switches back)

## Health Endpoint Detail

`GET /health` returns:
```json
{ "status": "ok" }
```
Always 200 as long as process is alive. Docker uses this for container readiness.

## `/health` Telegram Command Detail

Bot calls `GET {API_URL}/health`. On success, replies:
```
✅ Mr. Carson is running
Model: mistralai/mistral-small-3.1-24b-instruct
OCR model: google/gemma-3n-e4b-it:free
```
On failure (API unreachable):
```
❌ API unreachable
```

## One-Time Setup on Mac mini

1. Pull repo, copy `.env.example` → `.env`, fill in `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_IDS`, `OPENROUTER_API_KEY`
2. Docker Desktop → Settings → General → enable "Start Docker Desktop when you log in"
3. `docker compose -f infrastructure/docker/docker-compose.yml up -d --build`

## Out of Scope

- HTTPS / reverse proxy (not needed; bot talks to Telegram outbound only)
- Watchtower auto-updates (manual redeploy preferred for stability)
- Metrics dashboard
