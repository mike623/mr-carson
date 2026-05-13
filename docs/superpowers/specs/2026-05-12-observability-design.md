# Observability — Mastra Studio Integration

**Date:** 2026-05-12
**Status:** Approved

## Goal

Add Mastra Studio observability to mr-carson so agent turns (LLM calls, tool dispatches, memory reads) are visible as structured traces in a local web UI at `localhost:4111`.

## Approach

Upgrade `@mastra/core` from v0.11.1 to v1.x. Introduce a `Mastra` singleton configured with `@mastra/observability` + `MastraStorageExporter`. Register the mr-carson agent with it so Studio shows it by name. Per-request state (`userId`, `attachments`, `sink`) that was previously closed over in factory functions moves to Mastra v1's `RequestContext`, passed into `agent.generate()` at call time.

## Architecture

```
main.ts
  └── imports mastra.ts (early — bootstraps OTel before any agent runs)
        └── Mastra instance
              ├── agents: { mrCarson: mrCarsonAgent }
              ├── storage: MastraCompositeStore
              │     ├── default: LibSQLStore → data/mastra.db
              │     └── observability domain: DuckDBStore → in-memory/file
              └── observability: Observability
                    └── MastraStorageExporter (writes spans to storage)

agent.ts
  └── mrCarsonAgent (static Agent, no per-request construction)
        └── tools: ocr, extractReceipt, queryExpenses, topMerchants, chartSpending

runAgent(userId, threadId, message, opts)
  └── builds RequestContext { userId, attachments?, sink? }
  └── mastra.getAgentById('mrCarson').generate(message, { requestContext, ... })

tools/
  ├── analytics.ts       — static, reads userId from requestContext
  ├── queryExpenses.ts   — static, reads userId + attachments from requestContext
  └── chartSpending.ts   — static, reads userId + sink from requestContext

memory.ts  — unchanged in function; LibSQLStore gets id field (v1 requirement)
             stores conversation history in data/memory.db (separate from mastra.db)
```

## Storage

Two separate LibSQL files:

| File | Purpose |
|------|---------|
| `data/memory.db` | Mastra Memory — conversation history per user/thread |
| `data/mastra.db` | Mastra-managed storage — agent state, DuckDB observability spans |

Observability spans flow: `MastraStorageExporter` → `MastraCompositeStore` → DuckDB domain → readable by `mastra dev`.

## File Changes

| File | Change |
|------|--------|
| `apps/api/package.json` | Bump `@mastra/core`, `@mastra/memory`, `@mastra/libsql` to v1; add `@mastra/observability`, `@mastra/duckdb` |
| `apps/api/src/mastra.ts` | **New** — `Mastra` singleton with observability + composite storage + agent registration |
| `apps/api/src/agent.ts` | Replace `buildAgent(userId, opts)` with static `mrCarsonAgent`; update `runAgent` to use `RequestContext`; drop `agent.__setLogger` |
| `apps/api/src/tools/analytics.ts` | `makeAnalyticsTool(userId)` → static `analyticsTool`; `execute({ context })` → `execute(inputData, { requestContext })` |
| `apps/api/src/tools/queryExpenses.ts` | `makeQueryExpensesTool(userId, attachments)` → static `queryExpensesTool`; reads `userId` + `attachments` from `requestContext` |
| `apps/api/src/tools/chartSpending.ts` | `makeChartSpendingTool(userId, sink)` → static `chartSpendingTool`; reads `userId` + `sink` from `requestContext` |
| `apps/api/src/memory.ts` | Add `id: 'mr-carson-memory'` to `LibSQLStore` constructor |
| `apps/api/src/main.ts` | Add `import './mastra.js'` as first non-Node import |

## Tool API Migration

```typescript
// v0 (factory with closure)
export function makeAnalyticsTool(userId: string) {
  return createTool({
    execute: async ({ context }) => {
      await expensesRepo.topMerchants(userId, { dateRange: context.dateRange }, context.topN ?? 5);
    },
  });
}

// v1 (static, requestContext)
export const analyticsTool = createTool({
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    await expensesRepo.topMerchants(userId, { dateRange: inputData.dateRange }, inputData.topN ?? 5);
  },
});
```

## RequestContext in runAgent

```typescript
import { RequestContext } from '@mastra/core';

const ctx = new RequestContext();
ctx.set('userId', userId);
if (opts.attachments) ctx.set('attachments', opts.attachments);
if (opts.chartSink)   ctx.set('sink', opts.chartSink);

const agent = mastra.getAgentById('mrCarson');
await agent.generate(message, { maxSteps: 6, threadId, resourceId: userId, runId, requestContext: ctx, onStepFinish });
```

## New mastra.ts

```typescript
import { Mastra } from '@mastra/core';
import { MastraCompositeStore } from '@mastra/core/storage';
import { LibSQLStore } from '@mastra/libsql';
import { DuckDBStore } from '@mastra/duckdb';
import { Observability, MastraStorageExporter } from '@mastra/observability';
import { mrCarsonAgent } from './agent.js';

export const mastra = new Mastra({
  agents: { mrCarson: mrCarsonAgent },
  storage: new MastraCompositeStore({
    id: 'mr-carson-storage',
    default: new LibSQLStore({ id: 'mr-carson-mastra', url: 'file:./data/mastra.db' }),
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

## Dev Scripts

```json
"studio": "dotenv -e ../../.env -- mastra dev --dir src"
```

- `pnpm dev` — Hono API + bot (unchanged)
- `pnpm --filter @mr-carson/api studio` — Mastra Studio at `localhost:4111`

## What Studio Shows

- Every `agent.generate()` call as a top-level trace
- Tool dispatches (ocr, extractReceipt, queryExpenses, topMerchants, chartSpending) as child spans
- LLM call durations and token usage
- Memory read/write operations
- `userId` and `threadId` in span metadata via `resourceId` and `threadId` on `generate()`

## Out of Scope

- `SensitiveDataFilter` (can be added later if receipt text appears in spans)
- Mastra Cloud / `MastraPlatformExporter` (local-only for now)
- Vector memory / semantic recall (not currently used)
