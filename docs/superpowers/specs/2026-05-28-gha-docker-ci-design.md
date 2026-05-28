# GHA Docker CI/CD + E2E — Design Spec

**Date:** 2026-05-28
**Branch:** ripe-tarascosaurus
**Status:** Approved

## Goal

Build multi-arch Docker images for `api` and `telegram-bot` via GitHub Actions on every push to `development`, push them to GitHub Container Registry (GHCR), and gate the push behind a unit test + e2e integration test pass.

## Workflow structure

Single file: `.github/workflows/ci.yml`

**Trigger:** `push` to `development` branch

**Job graph:**

```
unit-test
  └── e2e (needs: unit-test)
        └── build-push × 2 (needs: e2e, matrix: api | telegram-bot)
```

### `unit-test` job

- `ubuntu-latest`
- Setup Node 20.10.0 + pnpm 9.12.0 via corepack
- `pnpm install --frozen-lockfile=false` (matches lockfile state in Dockerfiles)
- `pnpm test` (existing vitest suite across workspace)

### `e2e` job

- `ubuntu-latest`
- Builds `api` image for `linux/amd64` only (`load: true`, no push) using `docker/build-push-action`
- Starts container with `docker compose up api -d` using a minimal env override: `DUCKDB_PATH` unset (in-memory), `MEMORY_DB_PATH` and `MASTRA_DB_PATH` pointing to `/tmp` paths, no LLM keys set
- Polls `GET /health` until 200 (up to 60s)
- Runs `e2e/api.test.ts` via vitest
- `docker compose down` in `always()` post-step

**E2E test coverage** (no LLM API key required):

| Test | Route | Assertion |
|------|-------|-----------|
| Health check | `GET /health` | 200, `{ ok: true, model: string, ocrModel: string }` |
| Model info | `GET /model` | 200, `{ provider, agentModel, ocrModel }` |
| New session | `POST /agent/new { userId: "e2e" }` | 200, `{ threadId: string }` |

### `build-push` job (matrix)

- `ubuntu-latest`
- Matrix: `app: [api, telegram-bot]`
- `docker/setup-qemu-action` — enables arm64 emulation
- `docker/setup-buildx-action`
- `docker/login-action` — GHCR via auto-injected `GITHUB_TOKEN` (no manual secrets)
- `docker/build-push-action`:
  - `platforms: linux/amd64,linux/arm64`
  - `push: true`
  - `build-args: APP=${{ matrix.app }}`
  - `dockerfile: infrastructure/docker/Dockerfile.node`
  - Tags:
    - `ghcr.io/${{ github.repository_owner }}/mr-carson-${{ matrix.app }}:latest`
    - `ghcr.io/${{ github.repository_owner }}/mr-carson-${{ matrix.app }}:{sha7}` — SHA truncated via a prior `run` step outputting `echo "sha7=$(echo $GITHUB_SHA | cut -c1-7)" >> $GITHUB_OUTPUT`
- Cache: `type=gha` (GitHub Actions cache backend) — speeds up repeat builds

## New files

| File | Purpose |
|------|---------|
| `.github/workflows/ci.yml` | Full CI workflow |
| `e2e/api.test.ts` | Vitest e2e test suite |
| `e2e/vitest.config.ts` | Vitest config for e2e (separate from workspace unit tests) |

## Changes to existing files

### `infrastructure/docker/docker-compose.yml`

Add `image:` field to `api` and `bot` services pointing to GHCR. Keep existing `build:` context — compose uses `image:` for pull, `build:` for local dev.

```yaml
# Replace <ghcr-owner> with the GitHub username that owns this repo.
# e.g. ghcr.io/mike623/mr-carson-api:latest
api:
  image: ghcr.io/<ghcr-owner>/mr-carson-api:latest
  build:
    context: ../..
    dockerfile: infrastructure/docker/Dockerfile.node
    args:
      APP: api

bot:
  image: ghcr.io/<ghcr-owner>/mr-carson-bot:latest
  build:
    context: ../..
    dockerfile: infrastructure/docker/Dockerfile.node
    args:
      APP: telegram-bot
```

Home server deploy becomes: `docker compose pull && docker compose up -d`

## Secrets

No manual GitHub secret setup required. `GITHUB_TOKEN` is auto-injected by GHA and has write access to GHCR for the repo owner.

## Build time estimates

| Job | Estimated time |
|-----|---------------|
| unit-test | ~3 min |
| e2e (amd64 only) | ~8–12 min |
| build-push api (multi-arch) | ~15–25 min |
| build-push bot (multi-arch) | ~15–25 min |

`build-push` jobs run in parallel after e2e passes. Total wall time: ~25–35 min.

## Out of scope

- Post-deploy smoke test on home server (SSH + curl after pull)
- `POST /agent/ask` e2e coverage (requires LLM key)
- Fly.io deploy step (deferred)
- PR builds / preview environments
