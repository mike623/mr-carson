# Docker 24/7 Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure mr-carson for 24/7 Docker deployment on Mac mini using OpenRouter for LLM inference, with auto-restart on reboot and a `/health` Telegram command.

**Architecture:** Two Docker services (`api`, `bot`) with `restart: unless-stopped`, log rotation, and a health check on `api`. No Ollama container — LLM calls go to OpenRouter. The `/health` HTTP endpoint is enhanced to report active model names; the Telegram bot exposes `/health` as a command that shows live status.

**Tech Stack:** Docker Compose, Mastra/Hono (API), Telegraf (bot), TypeScript

---

### Task 1: Enhance `/health` API endpoint to return model info

**Files:**
- Modify: `apps/api/src/mastra.ts:77-80`

The `/health` route already exists at line 77. Enhance its response to include active model names read from env vars. This powers the Telegram `/health` command.

- [ ] **Step 1: Update the health handler**

In `apps/api/src/mastra.ts`, change lines 77–80 from:
```ts
registerApiRoute('/health', {
  method: 'GET',
  handler: (c) => c.json({ ok: true }),
}),
```
To:
```ts
registerApiRoute('/health', {
  method: 'GET',
  handler: (c) =>
    c.json({
      ok: true,
      model:
        process.env.OPENROUTER_MODEL ??
        process.env.OLLAMA_MODEL ??
        'unknown',
      ocrModel:
        process.env.OPENROUTER_OCR_MODEL ??
        process.env.OLLAMA_OCR_MODEL ??
        'unknown',
    }),
}),
```

- [ ] **Step 2: Typecheck**
```bash
pnpm --filter @mr-carson/api typecheck
```
Expected: no errors.

- [ ] **Step 3: Commit**
```bash
git add apps/api/src/mastra.ts
git commit -m "feat: return model info from /health endpoint"
```

---

### Task 2: Add `checkHealth()` to bot API client

**Files:**
- Modify: `apps/telegram-bot/src/api.ts`

- [ ] **Step 1: Append `HealthResponse` type and `checkHealth()` to `apps/telegram-bot/src/api.ts`**

Add at the end of the file:
```ts
export interface HealthResponse {
  ok: boolean;
  model: string;
  ocrModel: string;
}

export async function checkHealth(): Promise<HealthResponse> {
  return fetchJson<HealthResponse>('/health');
}
```

- [ ] **Step 2: Typecheck**
```bash
pnpm --filter @mr-carson/telegram-bot typecheck
```
Expected: no errors.

- [ ] **Step 3: Commit**
```bash
git add apps/telegram-bot/src/api.ts
git commit -m "feat: add checkHealth() to bot API client"
```

---

### Task 3: Add `/health` command to Telegram bot

**Files:**
- Modify: `apps/telegram-bot/src/bot.ts`

- [ ] **Step 1: Add `checkHealth` to the import from `./api.js`**

In `apps/telegram-bot/src/bot.ts`, update the import (currently lines 5–13) to:
```ts
import {
  ask,
  checkHealth,
  confirmPending,
  getPending,
  ingestReceipt,
  newSession,
  rejectPending,
  type AskResponse,
} from './api.js';
```

- [ ] **Step 2: Update `/help` command to list `/health`**

Replace the `bot.command('help', ...)` handler with:
```ts
bot.command('help', async (ctx) => {
  await ctx.reply(
    [
      'Commands:',
      '/start  — say hello',
      '/help   — this message',
      '/new    — start a fresh chat (forget prior turns)',
      '/summary — recent spend summary',
      '/chart   — spending chart, last month by category',
      '/categories — list categories',
      '/health — check bot and model status',
      '',
      'Or just send a receipt photo, or ask in plain English.',
    ].join('\n'),
  );
});
```

- [ ] **Step 3: Add `/health` command handler**

After the `bot.command('chart', ...)` block and before the `// Photo / document handlers` comment, insert:
```ts
bot.command('health', async (ctx) => {
  try {
    const h = await checkHealth();
    await ctx.reply(
      `✅ Mr. Carson is running\nModel: ${h.model}\nOCR model: ${h.ocrModel}`,
    );
  } catch {
    await ctx.reply('❌ API unreachable');
  }
});
```

- [ ] **Step 4: Typecheck**
```bash
pnpm --filter @mr-carson/telegram-bot typecheck
```
Expected: no errors.

- [ ] **Step 5: Commit**
```bash
git add apps/telegram-bot/src/bot.ts
git commit -m "feat: add /health Telegram command"
```

---

### Task 4: Update docker-compose.yml for 24/7 deploy

**Files:**
- Modify: `infrastructure/docker/docker-compose.yml`

- [ ] **Step 1: Rewrite `infrastructure/docker/docker-compose.yml`**

Replace the entire file with:
```yaml
name: mr-carson

services:
  api:
    build:
      context: ../..
      dockerfile: infrastructure/docker/Dockerfile.node
      args:
        APP: api
    command: ["node", "apps/api/dist/main.js"]
    restart: unless-stopped
    environment:
      API_PORT: 47821
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY}
      OPENROUTER_MODEL: ${OPENROUTER_MODEL:-mistralai/mistral-small-3.1-24b-instruct}
      OPENROUTER_OCR_MODEL: ${OPENROUTER_OCR_MODEL:-google/gemma-3n-e4b-it:free}
      DUCKDB_PATH: /data/db/mr-carson.duckdb
      MEMORY_DB_PATH: /data/db/memory.db
      DEFAULT_CURRENCY: ${DEFAULT_CURRENCY:-GBP}
    ports:
      - "47821:47821"
    volumes:
      - duckdb_data:/data/db
      - uploads:/data/uploads
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://localhost:47821/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  bot:
    build:
      context: ../..
      dockerfile: infrastructure/docker/Dockerfile.node
      args:
        APP: telegram-bot
    command: ["node", "apps/telegram-bot/dist/main.js"]
    restart: unless-stopped
    environment:
      TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN}
      TELEGRAM_ALLOWED_USER_IDS: ${TELEGRAM_ALLOWED_USER_IDS}
      API_URL: http://api:47821
      UPLOADS_DIR: /data/uploads
      DEFAULT_CURRENCY: ${DEFAULT_CURRENCY:-GBP}
    volumes:
      - uploads:/data/uploads
    depends_on:
      api:
        condition: service_healthy
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  uploads:
  duckdb_data:
```

- [ ] **Step 2: Validate compose file syntax**
```bash
docker compose -f infrastructure/docker/docker-compose.yml config --quiet
```
Expected: no output (silent = valid).

- [ ] **Step 3: Commit**
```bash
git add infrastructure/docker/docker-compose.yml
git commit -m "feat: 24/7 compose — OpenRouter, restart policy, healthcheck, log rotation"
```

---

### Task 5: Update .env.example

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Rewrite `.env.example`**

Replace the entire file with:
```
# --- Telegram ---
TELEGRAM_BOT_TOKEN=replace-with-token-from-botfather
# Comma-separated list of Telegram numeric user IDs allowed to use the bot.
TELEGRAM_ALLOWED_USER_IDS=123456789

# --- LLM provider ---
# Remote (default for Docker deploy): set OPENROUTER_API_KEY to use OpenRouter.
OPENROUTER_API_KEY=sk-or-...
OPENROUTER_MODEL=mistralai/mistral-small-3.1-24b-instruct
OPENROUTER_OCR_MODEL=google/gemma-3n-e4b-it:free

# Local fallback: leave OPENROUTER_API_KEY unset to use Ollama instead.
# OLLAMA_BASE_URL=http://localhost:11434
# OLLAMA_MODEL=mistral-small
# OLLAMA_OCR_MODEL=glm-ocr

# --- API ---
API_PORT=47821
PORT=47821
API_URL=http://localhost:47821

# --- Storage ---
DUCKDB_PATH=./data/mr-carson.duckdb
MEMORY_DB_PATH=./data/memory.db
UPLOADS_DIR=./data/uploads

# --- Defaults ---
DEFAULT_CURRENCY=GBP
LOG_LEVEL=info
```

- [ ] **Step 2: Commit**
```bash
git add .env.example
git commit -m "chore: update .env.example — OpenRouter as primary LLM provider"
```

---

## One-Time Setup on Mac mini (not a task — run manually after deploying)

1. Pull repo onto Mac mini
2. Copy `.env.example` → `.env`, fill in `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_IDS`, `OPENROUTER_API_KEY`
3. Docker Desktop → Settings → General → enable **"Start Docker Desktop when you log in"**
4. From the repo root:
   ```bash
   docker compose -f infrastructure/docker/docker-compose.yml up -d --build
   ```
5. Verify:
   ```bash
   docker compose -f infrastructure/docker/docker-compose.yml ps
   # api and bot should show "running (healthy)" / "running"
   docker compose -f infrastructure/docker/docker-compose.yml exec api node -e "fetch('http://localhost:47821/health').then(r=>r.json()).then(console.log)"
   # {"ok":true,"model":"mistralai/...","ocrModel":"google/..."}
   ```
6. Send `/health` in Telegram — should show model names.
