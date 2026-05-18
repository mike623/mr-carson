import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { Mastra } from '@mastra/core';
import { registerApiRoute } from '@mastra/core/server';
import { MastraCompositeStore } from '@mastra/core/storage';
import { LibSQLStore } from '@mastra/libsql';
import { DuckDBStore } from '@mastra/duckdb';
import { Observability, DefaultExporter } from '@mastra/observability';
import { z, ZodError } from 'zod';
import { HTTPException } from 'hono/http-exception';
import { migrate, seedCategories, pendingRepo, expensesRepo, chatSessionsRepo } from '@mr-carson/database';
import { mrCarsonAgent, runAgent } from './agent.js';
import { processReceipt, commitConfirmed } from './pipeline.js';
import type { ChartSink } from './tools/chartSpending.js';
import { agentLogger } from './logger.js';

function hashFile(filePath: string): string {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function hashFileIfExists(filePath: string | null | undefined): string | undefined {
  if (!filePath || !existsSync(filePath)) return undefined;
  return createHash('sha256').update(readFileSync(filePath)).digest('hex');
}

function mastraDbUrl(): string {
  const raw = process.env.MASTRA_DB_PATH ?? './data/mastra.db';
  const abs = resolve(raw);
  mkdirSync(dirname(abs), { recursive: true });
  return `file:${abs}`;
}

const AskBody = z.object({ userId: z.string().min(1), message: z.string().min(1) });
const NewSessionBody = z.object({ userId: z.string().min(1) });
const IngestBody = z.object({
  userId: z.string().min(1),
  chatId: z.string().min(1),
  filePath: z.string().min(1),
});

// Mastra dev server hosts everything: agent endpoints, receipt pipeline,
// Studio chat UI, traces, and OTel observability — all in one process so
// DuckDB has a single writer.
await migrate();
await seedCategories();

export const mastra = new Mastra({
  agents: { mrCarson: mrCarsonAgent },
  storage: new MastraCompositeStore({
    id: 'mr-carson-storage',
    default: new LibSQLStore({ id: 'mr-carson-mastra', url: mastraDbUrl() }),
    domains: {
      observability: new DuckDBStore().observability,
    },
  }),
  observability: new Observability({
    configs: {
      default: {
        serviceName: 'mr-carson',
        exporters: [new DefaultExporter()],
      },
    },
  }),
  server: {
    port: Number(process.env.API_PORT ?? process.env.PORT ?? 47821),
    host: '0.0.0.0',
    studioHost: 'localhost',
    onError: (err, c) => {
      if (err instanceof ZodError) {
        return c.json({ error: 'invalid request', issues: err.issues }, 400);
      }
      agentLogger.error('api.unhandled', { error: err });
      return c.json({ error: 'internal server error' }, 500);
    },
    apiRoutes: [
      registerApiRoute('/health', {
        method: 'GET',
        handler: (c) => c.json({ ok: true }),
      }),
      registerApiRoute('/model', {
        method: 'GET',
        handler: (c) => {
          const useOpenRouter = Boolean(process.env.OPENROUTER_API_KEY);
          return c.json({
            provider: useOpenRouter ? 'openrouter' : 'ollama',
            agentModel: useOpenRouter
              ? (process.env.OPENROUTER_MODEL ?? 'mistralai/mistral-small-3.1-24b-instruct')
              : (process.env.OLLAMA_MODEL ?? 'mistral-small'),
            ocrModel: useOpenRouter
              ? (process.env.OPENROUTER_OCR_MODEL ?? 'google/gemma-3n-e4b-it:free')
              : (process.env.OLLAMA_OCR_MODEL ?? 'MedAIBase/PaddleOCR-VL:0.9b'),
          });
        },
      }),
      registerApiRoute('/agent/ask', {
        method: 'POST',
        handler: async (c) => {
          let body: unknown;
          try {
            body = await c.req.json();
          } catch {
            throw new HTTPException(400, { message: 'invalid JSON' });
          }
          const { userId, message } = AskBody.parse(body);
          const threadId = await chatSessionsRepo.getOrCreateActiveThread(userId);
          const seen = new Set<string>();
          const chartSink: ChartSink = {};
          const reply = await runAgent(userId, threadId, message, {
            attachments: { add: (p: string) => seen.add(p) },
            chartSink,
          });
          return c.json({
            reply,
            attachments: Array.from(seen).slice(0, 5),
            ...(chartSink.imageBase64 ? { imageBase64: chartSink.imageBase64 } : {}),
          });
        },
      }),
      registerApiRoute('/agent/new', {
        method: 'POST',
        handler: async (c) => {
          let body: unknown;
          try {
            body = await c.req.json();
          } catch {
            throw new HTTPException(400, { message: 'invalid JSON' });
          }
          const { userId } = NewSessionBody.parse(body);
          const threadId = await chatSessionsRepo.rotateActiveThread(userId);
          return c.json({ threadId });
        },
      }),
      registerApiRoute('/receipts/ingest', {
        method: 'POST',
        handler: async (c) => {
          let body: unknown;
          try {
            body = await c.req.json();
          } catch {
            throw new HTTPException(400, { message: 'invalid JSON' });
          }
          const input = IngestBody.parse(body);

          // Hard dedup: reject identical file before OCR runs.
          const imageHash = hashFile(input.filePath);
          const existingId = await expensesRepo.findByImageHash(input.userId, imageHash);
          if (existingId) {
            return c.json({ error: 'duplicate', existingId }, 409);
          }

          const pendingId = await pendingRepo.createPending(input);
          try {
            const expense = await processReceipt({ pendingId, filePath: input.filePath });

            // Soft dedup: warn if fields match a previous expense (different image).
            const softDuplicate = await expensesRepo.findSoftDuplicate(input.userId, {
              merchant: expense.merchant,
              date: expense.date,
              total: expense.total,
              currency: expense.currency,
            });

            return c.json({
              pendingId,
              expense,
              ...(softDuplicate ? { softDuplicate } : {}),
            });
          } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            await pendingRepo.setPendingStatus(pendingId, 'FAILED', msg);
            throw err;
          }
        },
      }),
      registerApiRoute('/receipts/:id', {
        method: 'GET',
        handler: async (c) => {
          const pending = await pendingRepo.getPending(c.req.param('id'));
          if (!pending) throw new HTTPException(404);
          return c.json(pending);
        },
      }),
      registerApiRoute('/receipts/:id/confirm', {
        method: 'POST',
        handler: async (c) => {
          const id = c.req.param('id');
          const pending = await pendingRepo.getPending(id);
          if (!pending || !pending.extracted) throw new HTTPException(404);
          if (pending.status === 'INSERTED') return c.json({ id });
          const imageHash = hashFileIfExists(pending.filePath);
          return c.json(
            await commitConfirmed({
              pendingId: id,
              userId: pending.userId,
              expense: pending.extracted,
              sourceFile: pending.filePath,
              imageHash,
            }),
          );
        },
      }),
      registerApiRoute('/receipts/:id/reject', {
        method: 'POST',
        handler: async (c) => {
          await pendingRepo.setPendingStatus(c.req.param('id'), 'REJECTED');
          return c.json({ ok: true });
        },
      }),
    ],
  },
});
