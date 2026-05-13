# Mastra v1 + Studio Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade @mastra/core from v0.11.1 to v1, refactor per-request agent factories to static tools using RequestContext, and wire Mastra Studio observability so agent traces are visible at localhost:4111.

**Architecture:** A static `Mastra` singleton in `src/mastra.ts` is imported early in `main.ts` to bootstrap OTel globally. The `mrCarsonAgent` is a static `Agent` registered with that instance. Per-request state (`userId`, `attachments`, `sink`) previously closed over in factory functions now travels through `RequestContext` passed to `agent.generate()`.

**Tech Stack:** `@mastra/core` v1.x, `@mastra/observability`, `@mastra/duckdb`, `@mastra/libsql` v1, `RequestContext` from `@mastra/core/request-context`, `pnpm` monorepo.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `apps/api/package.json` | Modify | Bump @mastra/* to v1, add @mastra/observability + @mastra/duckdb |
| `apps/api/src/memory.ts` | Modify | Add `id` field to `LibSQLStore` (v1 requirement) |
| `apps/api/src/logger.ts` | Modify | Verify `MastraLogger` import still valid in v1 |
| `apps/api/src/tools/analytics.ts` | Modify | `makeAnalyticsTool(userId)` → static `analyticsTool`; v1 execute signature |
| `apps/api/src/tools/queryExpenses.ts` | Modify | `makeQueryExpensesTool(userId, attachments)` → static; reads from `requestContext` |
| `apps/api/src/tools/chartSpending.ts` | Modify | `makeChartSpendingTool(userId, sink)` → static; reads from `requestContext` |
| `apps/api/src/agent.ts` | Modify | Replace `buildAgent(userId, opts)` with static `mrCarsonAgent`; update `runAgent` to use `RequestContext`; drop `agent.__setLogger` |
| `apps/api/src/mastra.ts` | Create | `Mastra` singleton with `Observability` + composite storage |
| `apps/api/src/main.ts` | Modify | Import `./mastra.js` as first non-Node import |

---

## Task 1: Bump @mastra/* packages to v1

**Files:**
- Modify: `apps/api/package.json`

- [ ] **Step 1: Update package versions**

Open `apps/api/package.json`. Replace the `dependencies` block entries:

```json
"@mastra/core": "^1.32.1",
"@mastra/libsql": "^1.0.0",
"@mastra/memory": "^1.0.0",
"@mastra/observability": "^1.11.1",
"@mastra/duckdb": "^1.0.0",
```

(Keep all other deps unchanged.)

- [ ] **Step 2: Install**

```bash
pnpm install
```

Expected: no resolution errors. If `@mastra/duckdb` or others aren't found at `^1.0.0`, run `npm info @mastra/duckdb version` to get the latest and use that exact version.

- [ ] **Step 3: Run typecheck — expect failures**

```bash
pnpm --filter @mr-carson/api typecheck
```

Expected: TypeScript errors about changed APIs. That's fine — subsequent tasks fix them one by one.

- [ ] **Step 4: Commit**

```bash
git add apps/api/package.json pnpm-lock.yaml
git commit -m "chore(api): bump @mastra/* to v1, add observability + duckdb packages"
```

---

## Task 2: Fix LibSQLStore — add required `id` field

**Files:**
- Modify: `apps/api/src/memory.ts`

The v1 `LibSQLStore` constructor requires an `id` field alongside `url`.

- [ ] **Step 1: Add `id` to LibSQLStore**

Open `apps/api/src/memory.ts`. Change the `LibSQLStore` instantiation from:

```typescript
singleton = new Memory({
  storage: new LibSQLStore({ url: memoryDbUrl() }),
  options: {
    lastMessages: 20,
  },
});
```

To:

```typescript
singleton = new Memory({
  storage: new LibSQLStore({ id: 'mr-carson-memory', url: memoryDbUrl() }),
  options: {
    lastMessages: 20,
  },
});
```

- [ ] **Step 2: Typecheck this file**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep memory
```

Expected: no errors referencing `memory.ts`.

- [ ] **Step 3: Commit**

```bash
git add apps/api/src/memory.ts
git commit -m "fix(api): add required id field to LibSQLStore for @mastra/libsql v1"
```

---

## Task 3: Fix logger.ts for v1

**Files:**
- Modify: `apps/api/src/logger.ts`

`MastraLogger` may have moved subpaths in v1. Verify the import compiles; fix if not.

- [ ] **Step 1: Check current import**

`apps/api/src/logger.ts` line 1:
```typescript
import { MastraLogger } from '@mastra/core/logger';
```

Run:
```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep logger
```

- [ ] **Step 2: Fix import if broken**

If typecheck reports `Cannot find module '@mastra/core/logger'`, update the import. In v1 the logger moved to:

```typescript
import { MastraLogger } from '@mastra/core';
```

If the original `@mastra/core/logger` still resolves cleanly, leave it unchanged.

- [ ] **Step 3: Commit**

```bash
git add apps/api/src/logger.ts
git commit -m "fix(api): update MastraLogger import for @mastra/core v1"
```

---

## Task 4: Convert analytics tool to static

**Files:**
- Modify: `apps/api/src/tools/analytics.ts`

Replace the `makeAnalyticsTool(userId)` factory with a static export. `userId` moves to `requestContext`.

- [ ] **Step 1: Rewrite analytics.ts**

Replace the entire file content with:

```typescript
import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { expensesRepo } from '@mr-carson/database';
import { DateRangeSchema } from '@mr-carson/shared-types';

export const analyticsTool = createTool({
  id: 'topMerchants',
  description: 'Return the top-N merchants by total spend over a date range.',
  inputSchema: z.object({
    dateRange: DateRangeSchema.optional(),
    topN: z.number().int().positive().max(20).optional(),
  }),
  outputSchema: z.object({
    merchants: z.array(
      z.object({
        merchant: z.string(),
        total: z.number(),
        currency: z.string(),
      }),
    ),
  }),
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const merchants = await expensesRepo.topMerchants(
      userId,
      { dateRange: inputData.dateRange },
      inputData.topN ?? 5,
    );
    return { merchants };
  },
});
```

- [ ] **Step 2: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep analytics
```

Expected: no errors in `analytics.ts`.

- [ ] **Step 3: Commit**

```bash
git add apps/api/src/tools/analytics.ts
git commit -m "refactor(api): convert makeAnalyticsTool to static analyticsTool with RequestContext"
```

---

## Task 5: Convert queryExpenses tool to static

**Files:**
- Modify: `apps/api/src/tools/queryExpenses.ts`

`makeQueryExpensesTool(userId, attachments)` → static. Both `userId` and `attachments` come from `requestContext`.

- [ ] **Step 1: Rewrite queryExpenses.ts**

Replace the entire file content with:

```typescript
import { createTool } from '@mastra/core/tools';
import { expensesRepo } from '@mr-carson/database';
import {
  QueryExpensesArgsSchema,
  QueryExpensesResultSchema,
} from '@mr-carson/shared-types';

export interface AttachmentCollector {
  add(sourceFile: string): void;
}

export const queryExpensesTool = createTool({
  id: 'queryExpenses',
  description:
    "Aggregate the user's expenses by optional category / merchant / date range. Returns matching line items and the total.",
  inputSchema: QueryExpensesArgsSchema,
  outputSchema: QueryExpensesResultSchema,
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const attachments = requestContext?.get('attachments') as AttachmentCollector | undefined;
    const result = await expensesRepo.queryExpenses(userId, inputData);
    if (attachments) {
      const seen = new Set<string>();
      for (const row of result.rows) {
        if (row.sourceFile && !seen.has(row.sourceFile)) {
          seen.add(row.sourceFile);
          attachments.add(row.sourceFile);
        }
      }
    }
    return result;
  },
});
```

- [ ] **Step 2: Run existing queryExpenses tests**

```bash
pnpm --filter @mr-carson/api test -- src/tools/queryExpenses.test.ts
```

Expected: all tests pass (pure logic tests don't depend on execute signature).

- [ ] **Step 3: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep queryExpenses
```

- [ ] **Step 4: Commit**

```bash
git add apps/api/src/tools/queryExpenses.ts
git commit -m "refactor(api): convert makeQueryExpensesTool to static queryExpensesTool with RequestContext"
```

---

## Task 6: Convert chartSpending tool to static

**Files:**
- Modify: `apps/api/src/tools/chartSpending.ts`

`makeChartSpendingTool(userId, sink)` → static. Both move to `requestContext`. The pure helper functions (`buildChartConfig`, `defaultGranularity`) stay unchanged.

- [ ] **Step 1: Replace factory with static export**

In `apps/api/src/tools/chartSpending.ts`, replace lines 124–210 (the `makeChartSpendingTool` function) with:

```typescript
export const chartSpendingTool = createTool({
  id: 'chartSpending',
  description:
    'Render a chart of the user\'s spending over a date range, grouped by category. ' +
    'Use this whenever the user asks to "show", "chart", "graph", "visualize", or see a "trend" / "breakdown" of spending. ' +
    'Returns a summary; the chart image is delivered separately to the user.',
  inputSchema: ChartSpendingArgsSchema,
  outputSchema: ChartSpendingResultSchema,
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const sink = requestContext?.get('sink') as ChartSink | undefined;

    const { rows, granularity, currency } = await expensesRepo.byCategoryOverTime(userId, {
      dateRange: inputData.dateRange,
      startDate: inputData.startDate,
      endDate: inputData.endDate,
      category: inputData.category,
      granularity: inputData.granularity,
    });

    const buckets = Array.from(new Set(rows.map((r) => r.bucket))).sort();
    const categories = Array.from(new Set(rows.map((r) => r.category))).sort();
    const matrix: number[][] = buckets.map(() => categories.map(() => 0));
    const bucketIdx = new Map(buckets.map((b, i) => [b, i]));
    const catIdx = new Map(categories.map((c, i) => [c, i]));
    for (const r of rows) {
      const bi = bucketIdx.get(r.bucket)!;
      const ci = catIdx.get(r.category)!;
      matrix[bi]![ci] = r.total;
    }

    const totalsByCategory = categories
      .map((cat) => ({
        category: cat,
        total: Math.round(
          matrix.reduce((acc, row) => acc + (row[catIdx.get(cat)!] ?? 0), 0) * 100,
        ) / 100,
      }))
      .sort((a, b) => b.total - a.total);

    const grandTotal = totalsByCategory.reduce((a, b) => a + b.total, 0);
    const chartType = pickChartType(inputData.chartType, buckets.length, categories.length);
    const stacked = inputData.stacked ?? true;

    const summary =
      grandTotal === 0
        ? 'No spending found in that range.'
        : `Spent ${currency} ${grandTotal.toFixed(2)} across ${categories.length} categories over ${buckets.length} ${granularity}(s). Top: ${totalsByCategory
            .slice(0, 3)
            .map((c) => `${c.category} ${currency} ${c.total.toFixed(2)}`)
            .join(', ')}.`;

    if (grandTotal === 0) {
      return { summary, chartType, granularity, currency, totalsByCategory, buckets, imageBase64: '' };
    }

    const config = buildChartConfig({ buckets, categories, matrix, totalsByCategory, chartType, currency, stacked });
    const imageBase64 = await renderViaQuickChart(config);
    if (sink) sink.imageBase64 = imageBase64;

    return { summary, chartType, granularity, currency, totalsByCategory, buckets, imageBase64 };
  },
});
```

- [ ] **Step 2: Run existing chartSpending tests**

```bash
pnpm --filter @mr-carson/api test -- src/tools/chartSpending.test.ts
```

Expected: all tests pass (`buildChartConfig` and `defaultGranularity` are unchanged pure functions).

- [ ] **Step 3: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep chartSpending
```

- [ ] **Step 4: Commit**

```bash
git add apps/api/src/tools/chartSpending.ts
git commit -m "refactor(api): convert makeChartSpendingTool to static chartSpendingTool with RequestContext"
```

---

## Task 7: Refactor agent.ts — static agent + RequestContext in runAgent

**Files:**
- Modify: `apps/api/src/agent.ts`

`buildAgent(userId, opts)` is removed. `mrCarsonAgent` is a static `Agent`. `runAgent` builds a `RequestContext` and calls `mrCarsonAgent.generate()` directly (no `mastra.getAgentById()` — avoids circular dependency with `mastra.ts`).

- [ ] **Step 1: Update imports in agent.ts**

At the top of `apps/api/src/agent.ts`, replace existing imports with:

```typescript
import { randomUUID } from 'node:crypto';
import { Agent } from '@mastra/core/agent';
import { RequestContext } from '@mastra/core/request-context';
import { getModel } from './llm.js';
import { getMemory } from './memory.js';
import { agentLogger } from './logger.js';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';
import { queryExpensesTool } from './tools/queryExpenses.js';
import type { AttachmentCollector } from './tools/queryExpenses.js';
import { analyticsTool } from './tools/analytics.js';
import { chartSpendingTool } from './tools/chartSpending.js';
import type { ChartSink } from './tools/chartSpending.js';
```

- [ ] **Step 2: Replace buildAgent with static mrCarsonAgent**

Remove the `BuildAgentOptions` interface and `buildAgent` function entirely. Replace with:

```typescript
export interface RunAgentOptions {
  chartSink?: ChartSink;
  attachments?: AttachmentCollector;
}

export const mrCarsonAgent = new Agent({
  name: 'mr-carson',
  instructions: SYSTEM,
  model: getModel(),
  memory: getMemory(),
  tools: {
    ocr: ocrTool,
    extractReceipt: extractReceiptTool,
    queryExpenses: queryExpensesTool,
    topMerchants: analyticsTool,
    chartSpending: chartSpendingTool,
  },
});
```

- [ ] **Step 3: Update runAgent to use RequestContext**

Replace the `runAgent` function body. The signature changes `BuildAgentOptions` → `RunAgentOptions`, and `buildAgent` is replaced by `RequestContext`:

```typescript
export async function runAgent(
  userId: string,
  threadId: string,
  message: string,
  opts: RunAgentOptions = {},
): Promise<string> {
  const runId = randomUUID();
  const startedAt = Date.now();
  agentLogger.info('agent.request', {
    runId,
    userId,
    threadId,
    msgLen: message.length,
    msg: preview(message, 800),
    hasAttachmentSink: Boolean(opts.attachments),
    hasChartSink: Boolean(opts.chartSink),
  });

  const ctx = new RequestContext();
  ctx.set('userId', userId);
  if (opts.attachments) ctx.set('attachments', opts.attachments);
  if (opts.chartSink) ctx.set('sink', opts.chartSink);

  try {
    const result = await mrCarsonAgent.generate(message, {
      maxSteps: 6,
      threadId,
      resourceId: userId,
      runId,
      requestContext: ctx,
      onStepFinish: ((step: StepLike) => {
        agentLogger.info('agent.step', { runId, ...summarizeStep(step) });
      }) as never,
    });

    const r = result as unknown as {
      text?: string;
      finishReason?: string;
      usage?: unknown;
      steps?: unknown[];
      warnings?: unknown;
    };
    agentLogger.info('agent.response', {
      runId,
      userId,
      threadId,
      ms: Date.now() - startedAt,
      finishReason: r.finishReason,
      usage: r.usage,
      steps: r.steps?.length ?? 0,
      textLen: r.text?.length ?? 0,
      text: r.text ? preview(r.text, 600) : undefined,
      warnings: r.warnings,
    });
    return result.text ?? '';
  } catch (err) {
    agentLogger.error('agent.error', {
      runId,
      userId,
      threadId,
      ms: Date.now() - startedAt,
      error: err,
    });
    throw err;
  }
}
```

- [ ] **Step 4: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep agent
```

If `RequestContext` import fails (`Cannot find module '@mastra/core/request-context'`), try `import { RequestContext } from '@mastra/core'` instead.

- [ ] **Step 5: Commit**

```bash
git add apps/api/src/agent.ts
git commit -m "refactor(api): replace buildAgent closure with static mrCarsonAgent + RequestContext"
```

---

## Task 8: Create mastra.ts — Mastra singleton with observability

**Files:**
- Create: `apps/api/src/mastra.ts`

This file owns the `Mastra` instance. It is imported early in `main.ts` to bootstrap OTel globally before any agent runs. Agents registered here show up in Studio by name.

Uses two storage layers:
- `data/mastra.db` — LibSQL for Mastra-managed state
- DuckDB (in-process) — observability spans

- [ ] **Step 1: Create apps/api/src/mastra.ts**

```typescript
import { mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { Mastra } from '@mastra/core';
import { MastraCompositeStore } from '@mastra/core/storage';
import { LibSQLStore } from '@mastra/libsql';
import { DuckDBStore } from '@mastra/duckdb';
import { Observability, MastraStorageExporter } from '@mastra/observability';
import { mrCarsonAgent } from './agent.js';

function mastraDbUrl(): string {
  const raw = process.env.MASTRA_DB_PATH ?? './data/mastra.db';
  const abs = resolve(raw);
  mkdirSync(dirname(abs), { recursive: true });
  return `file:${abs}`;
}

export const mastra = new Mastra({
  agents: { mrCarson: mrCarsonAgent },
  storage: new MastraCompositeStore({
    id: 'mr-carson-storage',
    default: new LibSQLStore({ id: 'mr-carson-mastra', url: mastraDbUrl() }),
    domains: {
      observability: await new DuckDBStore().getStore('observability'),
    },
  }),
  observability: new Observability({
    configs: {
      default: {
        serviceName: 'mr-carson',
        exporters: [new MastraStorageExporter()],
      },
    },
  }),
});
```

- [ ] **Step 2: Typecheck**

```bash
pnpm --filter @mr-carson/api typecheck 2>&1 | grep mastra
```

If `MastraCompositeStore` import path is wrong, try `from '@mastra/core'` instead of `from '@mastra/core/storage'`.

- [ ] **Step 3: Commit**

```bash
git add apps/api/src/mastra.ts
git commit -m "feat(api): add Mastra singleton with observability + DuckDB storage for Studio"
```

---

## Task 9: Wire mastra.ts into main.ts + add studio script

**Files:**
- Modify: `apps/api/src/main.ts`
- Modify: `apps/api/package.json`

- [ ] **Step 1: Add early import of mastra.ts**

Open `apps/api/src/main.ts`. After the Node built-in imports and before any other imports, add:

```typescript
import './mastra.js'
```

The file top should look like:

```typescript
import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import { z, ZodError } from 'zod'
import './mastra.js'   // ← bootstraps OTel before any agent runs
import { migrate, seedCategories, pendingRepo, chatSessionsRepo } from '@mr-carson/database'
import { runAgent } from './agent.js'
// ... rest unchanged
```

- [ ] **Step 2: Update runAgent call sites in main.ts**

`runAgent`'s third option argument type changed from `BuildAgentOptions` to `RunAgentOptions` — the shape is identical (`chartSink?`, `attachments?`) so the call sites in `main.ts` need no changes.

- [ ] **Step 3: Add studio script to package.json**

In `apps/api/package.json` scripts section, add:

```json
"studio": "dotenv -e ../../.env -- mastra dev --dir src"
```

- [ ] **Step 4: Full typecheck**

```bash
pnpm --filter @mr-carson/api typecheck
```

Expected: zero errors.

- [ ] **Step 5: Run all tests**

```bash
pnpm --filter @mr-carson/api test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add apps/api/src/main.ts apps/api/package.json
git commit -m "feat(api): wire Mastra Studio observability — import mastra.ts early, add studio script"
```

---

## Task 10: Smoke test Studio

- [ ] **Step 1: Start the API in one terminal**

```bash
pnpm dev
```

Expected: `{"msg":"api.start","port":3001}` log line.

- [ ] **Step 2: Start Studio in a second terminal**

```bash
pnpm --filter @mr-carson/api studio
```

Expected: Studio starts, prints URL `http://localhost:4111`.

- [ ] **Step 3: Trigger an agent turn**

Send a message to the Telegram bot, or POST directly:

```bash
curl -X POST http://localhost:3001/agent/ask \
  -H 'content-type: application/json' \
  -d '{"userId":"test-user","message":"how much did I spend this month?"}'
```

- [ ] **Step 4: Verify trace in Studio**

Open `http://localhost:4111` in a browser. Navigate to the Traces or Observability section. You should see a trace for the `agent.generate` call with child spans for each tool invoked and the LLM call.

- [ ] **Step 5: Update CLAUDE.md**

Add Studio to the commands table in `CLAUDE.md`:

```
pnpm --filter @mr-carson/api studio   # Mastra Studio at localhost:4111
```

- [ ] **Step 6: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Mastra Studio command to CLAUDE.md"
```

---

## Self-Review Notes

- **Circular dep:** `mastra.ts` imports `mrCarsonAgent` from `agent.ts`. `agent.ts` does NOT import from `mastra.ts`. `runAgent` calls `mrCarsonAgent.generate()` directly — no `mastra.getAgent()` needed at runtime.
- **Top-level await:** `await new DuckDBStore().getStore('observability')` in `mastra.ts` requires ESM top-level await — this is fine since `apps/api` uses `"type": "module"`.
- **`MASTRA_DB_PATH`** env var is optional and not in `.env.example` — implementer should add it to `.env.example` if the team wants to configure it.
- **`logger.ts`** — `MastraLogger` may need import path adjustment (Task 3). The JSON logger still handles stdout/stderr; OTel handles Studio traces — they serve different purposes and coexist.
- **`agent.__setLogger`** — removed as part of Task 7. No replacement needed; OTel is now the tracing path.
