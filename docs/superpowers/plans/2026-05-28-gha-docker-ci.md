# GHA Docker CI/CD + E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build multi-arch Docker images for `api` and `telegram-bot` via GitHub Actions on push to `development`, gate on unit tests + e2e integration tests, push to GHCR.

**Architecture:** Three GHA jobs in sequence: `unit-test` → `e2e` (spin up real API container, run HTTP tests) → `build-push` (two parallel matrix jobs, multi-arch). E2E tests live in a new `e2e/` workspace package and require no LLM keys.

**Tech Stack:** GitHub Actions, GHCR, `docker/build-push-action@v6`, QEMU for arm64, vitest, Node 20 `fetch` (no extra HTTP library), pnpm workspaces.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `.github/workflows/ci.yml` | Full CI workflow (unit-test → e2e → build-push) |
| Create | `e2e/package.json` | New workspace package for e2e tests |
| Create | `e2e/vitest.config.ts` | Vitest config (30s timeout, globals) |
| Create | `e2e/api.test.ts` | 3 HTTP tests: /health, /model, /agent/new |
| Modify | `pnpm-workspace.yaml` | Add `e2e` to workspace packages |
| Modify | `infrastructure/docker/docker-compose.yml` | Fix api command (dist→.mastra/output) + add `image:` fields for GHCR pull |

---

## Task 1: Fix docker-compose api command + add GHCR image fields

The `api` service command currently points to `apps/api/dist/main.js` which does not exist — `mastra build` outputs to `apps/api/.mastra/output/index.mjs`. Fix this and add `image:` fields so the home server can `docker compose pull`.

**Files:**
- Modify: `infrastructure/docker/docker-compose.yml`

- [ ] **Step 1: Update docker-compose.yml**

Replace the full file contents with:

```yaml
name: mr-carson

services:
  api:
    image: ghcr.io/mike623/mr-carson-api:latest
    build:
      context: ../..
      dockerfile: infrastructure/docker/Dockerfile.node
      args:
        APP: api
    command: ["node", "apps/api/.mastra/output/index.mjs"]
    restart: unless-stopped
    environment:
      API_PORT: 47821
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY}
      OPENROUTER_MODEL: ${OPENROUTER_MODEL:-mistralai/mistral-small-3.1-24b-instruct}
      OPENROUTER_OCR_MODEL: ${OPENROUTER_OCR_MODEL:-google/gemma-3n-e4b-it:free}
      DUCKDB_PATH: /data/db/mr-carson.duckdb
      MEMORY_DB_PATH: /data/db/memory.db
      MASTRA_DB_PATH: /data/db/mastra.db
      DEFAULT_CURRENCY: ${DEFAULT_CURRENCY:-GBP}
      LOG_LEVEL: ${LOG_LEVEL:-info}
      QUICKCHART_URL: ${QUICKCHART_URL:-https://quickchart.io/chart}
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
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  bot:
    image: ghcr.io/mike623/mr-carson-bot:latest
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

- [ ] **Step 2: Commit**

```bash
git add infrastructure/docker/docker-compose.yml
git commit -m "fix: correct api command path and add GHCR image references to compose"
```

---

## Task 2: E2E workspace package scaffold

Create the `e2e/` package and register it in the pnpm workspace.

**Files:**
- Modify: `pnpm-workspace.yaml`
- Create: `e2e/package.json`
- Create: `e2e/vitest.config.ts`

- [ ] **Step 1: Add e2e to pnpm-workspace.yaml**

```yaml
packages:
  - "apps/*"
  - "packages/*"
  - "e2e"
```

- [ ] **Step 2: Create e2e/package.json**

```json
{
  "name": "@mr-carson/e2e",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "^4.1.6"
  }
}
```

- [ ] **Step 3: Create e2e/vitest.config.ts**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    testTimeout: 30000,
  },
});
```

- [ ] **Step 4: Install workspace deps**

```bash
pnpm install
```

Expected: `@mr-carson/e2e` appears in lockfile, no errors.

- [ ] **Step 5: Commit**

```bash
git add pnpm-workspace.yaml e2e/package.json e2e/vitest.config.ts pnpm-lock.yaml
git commit -m "chore: add e2e workspace package scaffold"
```

---

## Task 3: Write e2e test suite

Three HTTP tests that hit the live API. No LLM keys needed — all three routes return without calling Ollama/OpenRouter.

**Files:**
- Create: `e2e/api.test.ts`

- [ ] **Step 1: Create e2e/api.test.ts**

```ts
const BASE = process.env.API_BASE_URL ?? 'http://localhost:47821';

describe('API e2e', () => {
  test('GET /health returns ok', async () => {
    const res = await fetch(`${BASE}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(typeof body.model).toBe('string');
    expect(typeof body.ocrModel).toBe('string');
  });

  test('GET /model returns provider info', async () => {
    const res = await fetch(`${BASE}/model`);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(typeof body.provider).toBe('string');
    expect(typeof body.agentModel).toBe('string');
    expect(typeof body.ocrModel).toBe('string');
  });

  test('POST /agent/new creates a thread', async () => {
    const res = await fetch(`${BASE}/agent/new`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userId: 'e2e-test' }),
    });
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(typeof body.threadId).toBe('string');
    expect((body.threadId as string).length).toBeGreaterThan(0);
  });
});
```

- [ ] **Step 2: Verify test fails with no server**

```bash
pnpm --filter @mr-carson/e2e test
```

Expected: all 3 tests fail with a network connection error (`ECONNREFUSED` or similar). This confirms the tests actually reach out over HTTP.

- [ ] **Step 3: Commit**

```bash
git add e2e/api.test.ts
git commit -m "test: add e2e HTTP tests for /health, /model, /agent/new"
```

---

## Task 4: GitHub Actions CI workflow

Create the workflow file. Three jobs: `unit-test` → `e2e` → `build-push` (matrix × 2).

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create .github/workflows/ci.yml**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Write the workflow**

```yaml
name: CI

on:
  push:
    branches: [development]

jobs:
  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9.12.0

      - uses: actions/setup-node@v4
        with:
          node-version: '20.10.0'
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile=false

      - run: pnpm test

  e2e:
    needs: unit-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: pnpm/action-setup@v4
        with:
          version: 9.12.0

      - uses: actions/setup-node@v4
        with:
          node-version: '20.10.0'
          cache: 'pnpm'

      - run: pnpm install --frozen-lockfile=false

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build API image (amd64, no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: infrastructure/docker/Dockerfile.node
          build-args: APP=api
          platforms: linux/amd64
          load: true
          tags: mr-carson-api:e2e
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Start API container
        run: |
          docker run -d \
            --name mr-carson-api-e2e \
            -p 47821:47821 \
            -e API_PORT=47821 \
            -e MEMORY_DB_PATH=/tmp/memory.db \
            -e MASTRA_DB_PATH=/tmp/mastra.db \
            -e NODE_ENV=production \
            mr-carson-api:e2e \
            node apps/api/.mastra/output/index.mjs

      - name: Wait for /health (60s timeout)
        run: |
          for i in $(seq 1 30); do
            if curl -sf http://localhost:47821/health > /dev/null; then
              echo "API ready after $((i * 2))s"
              exit 0
            fi
            echo "Attempt $i/30, waiting 2s..."
            sleep 2
          done
          echo "API failed to start within 60s"
          docker logs mr-carson-api-e2e
          exit 1

      - name: Run e2e tests
        run: pnpm --filter @mr-carson/e2e test
        env:
          API_BASE_URL: http://localhost:47821

      - name: Stop API container
        if: always()
        run: docker rm -f mr-carson-api-e2e || true

  build-push:
    needs: e2e
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app: [api, telegram-bot]
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Get short SHA
        id: sha
        run: echo "sha7=$(echo $GITHUB_SHA | cut -c1-7)" >> $GITHUB_OUTPUT

      - name: Build and push ${{ matrix.app }}
        uses: docker/build-push-action@v6
        with:
          context: .
          file: infrastructure/docker/Dockerfile.node
          build-args: APP=${{ matrix.app }}
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/mr-carson-${{ matrix.app }}:latest
            ghcr.io/${{ github.repository_owner }}/mr-carson-${{ matrix.app }}:${{ steps.sha.outputs.sha7 }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 3: Verify workflow syntax locally**

```bash
# Check YAML parses without errors
node -e "const fs = require('fs'); const yaml = require('js-yaml'); yaml.load(fs.readFileSync('.github/workflows/ci.yml', 'utf8')); console.log('YAML valid')" 2>/dev/null || python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML valid')"
```

Expected: `YAML valid`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GHA workflow — unit-test, e2e, multi-arch build+push to GHCR"
```

---

## Task 5: Make GHCR packages public (one-time, manual)

GHCR packages default to private. After the first successful push, set both packages to public so the home server can pull without auth.

- [ ] **Step 1: After first CI run succeeds, open GitHub**

Navigate to: `https://github.com/mike623?tab=packages`

- [ ] **Step 2: Set mr-carson-api to public**

Open `mr-carson-api` → Package settings → Change visibility → Public

- [ ] **Step 3: Set mr-carson-bot to public**

Open `mr-carson-bot` → Package settings → Change visibility → Public

If you prefer to keep them private, add a `docker login ghcr.io` step to your home server deploy script:
```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u mike623 --password-stdin
docker compose pull
docker compose up -d
```

---

## Task 6: Home server update

Update the home server to pull from GHCR instead of building locally.

- [ ] **Step 1: Pull updated compose file on home server**

```bash
git pull
```

- [ ] **Step 2: Pull images and restart**

```bash
docker compose -f infrastructure/docker/docker-compose.yml pull
docker compose -f infrastructure/docker/docker-compose.yml up -d
```

Expected: both services start healthy. Check with:
```bash
curl http://localhost:47821/health
```

Expected response: `{"ok":true,"model":"...","ocrModel":"..."}`

---

## Self-review notes

- `api` command fix in Task 1 is load-bearing — without it the container crashes at start, breaking e2e.
- `bot` is not tested in e2e (requires real Telegram token). The e2e job only starts the `api` container.
- `cache-from: type=gha` on the e2e build job shares cache with `build-push`, so the amd64 layer built in e2e is reused in `build-push`, cutting total wall time.
- `permissions: packages: write` is scoped to `build-push` only — `unit-test` and `e2e` run with default read-only token.
- If the repo is under an org (not personal account), `github.repository_owner` resolves to the org name — still correct.
