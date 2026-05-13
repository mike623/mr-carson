import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { HTTPException } from 'hono/http-exception'
import { z, ZodError } from 'zod'
import './mastra.js'   // bootstraps OTel before any agent runs
import { migrate, seedCategories, pendingRepo, chatSessionsRepo } from '@mr-carson/database'
import { runAgent } from './agent.js'
import type { ChartSink } from './tools/chartSpending.js'
import { processReceipt, commitConfirmed } from './pipeline.js'
import { agentLogger } from './logger.js'

const app = new Hono()

app.onError((err, c) => {
  if (err instanceof ZodError) {
    return c.json({ error: 'invalid request', issues: err.issues }, 400)
  }
  agentLogger.error('api.unhandled', { error: err })
  return c.json({ error: 'internal server error' }, 500)
})

app.get('/health', c => c.json({ ok: true }))

// agent routes
const AskBody = z.object({ userId: z.string().min(1), message: z.string().min(1) })
const NewSessionBody = z.object({ userId: z.string().min(1) })

app.post('/agent/ask', async c => {
  let body: unknown
  try { body = await c.req.json() } catch { throw new HTTPException(400, { message: 'invalid JSON' }) }
  const { userId, message } = AskBody.parse(body)
  const threadId = await chatSessionsRepo.getOrCreateActiveThread(userId)
  const seen = new Set<string>()
  const chartSink: ChartSink = {}
  const reply = await runAgent(userId, threadId, message, {
    attachments: { add: (p: string) => seen.add(p) },
    chartSink,
  })
  return c.json({
    reply,
    attachments: Array.from(seen).slice(0, 5),
    ...(chartSink.imageBase64 ? { imageBase64: chartSink.imageBase64 } : {}),
  })
})

app.post('/agent/new', async c => {
  let body: unknown
  try { body = await c.req.json() } catch { throw new HTTPException(400, { message: 'invalid JSON' }) }
  const { userId } = NewSessionBody.parse(body)
  const threadId = await chatSessionsRepo.rotateActiveThread(userId)
  return c.json({ threadId })
})

// receipts routes
const IngestBody = z.object({
  userId: z.string().min(1),
  chatId: z.string().min(1),
  filePath: z.string().min(1),
})

app.post('/receipts/ingest', async c => {
  let body: unknown
  try { body = await c.req.json() } catch { throw new HTTPException(400, { message: 'invalid JSON' }) }
  const input = IngestBody.parse(body)
  const pendingId = await pendingRepo.createPending(input)
  try {
    const expense = await processReceipt({ pendingId, filePath: input.filePath })
    return c.json({ pendingId, expense })
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    await pendingRepo.setPendingStatus(pendingId, 'FAILED', msg)
    throw err
  }
})

app.get('/receipts/:id', async c => {
  const pending = await pendingRepo.getPending(c.req.param('id'))
  if (!pending) throw new HTTPException(404)
  return c.json(pending)
})

app.post('/receipts/:id/confirm', async c => {
  const id = c.req.param('id')
  const pending = await pendingRepo.getPending(id)
  if (!pending || !pending.extracted) throw new HTTPException(404)
  if (pending.status === 'INSERTED') return c.json({ id })
  return c.json(await commitConfirmed({
    pendingId: id,
    userId: pending.userId,
    expense: pending.extracted,
    sourceFile: pending.filePath,
  }))
})

app.post('/receipts/:id/reject', async c => {
  await pendingRepo.setPendingStatus(c.req.param('id'), 'REJECTED')
  return c.json({ ok: true })
})

const port = Number(process.env.API_PORT ?? process.env.PORT ?? 47821)
try {
  await migrate()
  await seedCategories()
  serve({ fetch: app.fetch, port }, info => {
    agentLogger.info('api.start', { port: info.port })
  })
} catch (err) {
  agentLogger.error('api.bootstrap.error', { error: err })
  process.exit(1)
}
