import { randomUUID } from 'node:crypto';
import { Agent } from '@mastra/core/agent';
import { getModel } from './llm.js';
import { getMemory } from './memory.js';
import { agentLogger } from './logger.js';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';
import {
  makeQueryExpensesTool,
  type AttachmentCollector,
} from './tools/queryExpenses.js';
import { analyticsTool } from './tools/analytics.js';
import { makeChartSpendingTool, type ChartSink } from './tools/chartSpending.js';

const SYSTEM = `You are Mr. Carson, a careful personal-finance assistant.

You help one user track and query their expenses.

Hard rules:
- For numeric data questions, ALWAYS call a tool (queryExpenses, topMerchants, or chartSpending). Never invent totals or item lists.
- When the user asks to "show", "chart", "graph", "visualize", "plot", or see a "trend" / "breakdown" / "by category", call chartSpending. The chart image is delivered to the user automatically; in your text reply, briefly describe what is on the chart instead of restating every number.
- Reply in short, plain sentences. Use the user's currency.
- If the user asks something you cannot answer from tools, say so.
- Never expose internal IDs, file paths, raw OCR text, or base64 image data in replies.
- When the user asks about a specific spend, merchant, or receipt, the matching
  receipt image is sent back automatically by the host — do not describe the
  image or apologise for not having one.`;

export interface BuildAgentOptions {
  chartSink?: ChartSink;
  attachments?: AttachmentCollector;
}

/**
 * Each request builds a fresh agent that closes over the calling userId so
 * tool executions are tenant-scoped at construction time.
 *
 * - `attachments` is threaded into queryExpenses so the host can surface
 *   the original receipt image alongside the reply.
 * - `chartSink` captures the PNG produced by chartSpending so the host can
 *   deliver it to the user.
 */
export function buildAgent(userId: string, opts: BuildAgentOptions = {}): Agent {
  const chartSink: ChartSink = opts.chartSink ?? {};
  const agent = new Agent({
    name: 'mr-carson',
    instructions: SYSTEM,
    model: getModel(),
    memory: getMemory(),
    tools: {
      ocr: ocrTool,
      extractReceipt: extractReceiptTool,
      queryExpenses: makeQueryExpensesTool(userId, opts.attachments),
      topMerchants: analyticsTool,
      chartSpending: makeChartSpendingTool(userId, chartSink),
    },
  });
  // Routes Mastra's internal debug stream (memory, tool dispatch, LLM calls)
  // through our structured JSON logger.
  agent.__setLogger(agentLogger);
  return agent;
}

function preview(s: string, n = 500): string {
  return s.length > n ? `${s.slice(0, n)}…(+${s.length - n})` : s;
}

interface StepLike {
  stepType?: string;
  finishReason?: string;
  text?: string;
  warnings?: unknown;
  usage?: unknown;
  toolCalls?: Array<{ toolCallId?: string; toolName?: string; args?: unknown }>;
  toolResults?: Array<{
    toolCallId?: string;
    toolName?: string;
    result?: unknown;
    error?: unknown;
  }>;
}

function summarizeToolCall(c: NonNullable<StepLike['toolCalls']>[number]) {
  return { id: c.toolCallId, name: c.toolName, args: c.args };
}

function summarizeToolResult(r: NonNullable<StepLike['toolResults']>[number]) {
  return {
    id: r.toolCallId,
    name: r.toolName,
    ok: r.error == null,
    error: r.error ? String(r.error) : undefined,
    result: r.result,
  };
}

function summarizeStep(step: StepLike) {
  return {
    stepType: step.stepType,
    finishReason: step.finishReason,
    textLen: step.text?.length ?? 0,
    text: step.text ? preview(step.text, 400) : undefined,
    toolCalls: (step.toolCalls ?? []).map(summarizeToolCall),
    toolResults: (step.toolResults ?? []).map(summarizeToolResult),
    usage: step.usage,
    warnings: step.warnings,
  };
}

/**
 * Run one conversational turn. `threadId` scopes Mastra Memory recall — a new
 * threadId starts a fresh session (see /new). `opts` lets callers harvest
 * receipt attachments and chart images produced during the turn.
 *
 * Every turn emits structured JSON log lines:
 *   - `agent.request`  on entry (userId, threadId, msg preview)
 *   - `agent.step`     per Mastra step (tool calls, results, usage)
 *   - `agent.response` on success (finishReason, usage, duration)
 *   - `agent.error`    on failure (stack, duration)
 * Each line carries a shared `runId` so a single turn can be grep'd end-to-end.
 */
export async function runAgent(
  userId: string,
  threadId: string,
  message: string,
  opts: BuildAgentOptions = {},
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

  const agent = buildAgent(userId, opts);
  try {
    const result = await agent.generate(message, {
      maxSteps: 6,
      threadId,
      resourceId: userId,
      runId,
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
