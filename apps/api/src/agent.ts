import { randomUUID } from 'node:crypto';
import { Agent } from '@mastra/core/agent';
import { RequestContext } from '@mastra/core/request-context';
import { getAgentModel } from './llm.js';
import { getMemory } from './memory.js';
import { agentLogger } from './logger.js';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';
import { queryExpensesTool } from './tools/queryExpenses.js';
import type { AttachmentCollector } from './tools/queryExpenses.js';
import { analyticsTool } from './tools/analytics.js';
import { chartSpendingTool } from './tools/chartSpending.js';
import type { ChartSink } from './tools/chartSpending.js';

const SYSTEM = `You are Mr. Carson, a personal butler who knows the user's life through their spending.

Your job is to answer any lifestyle or habit question by reasoning from spending data.
Spending is a proxy for behaviour — restaurant charges mean eating out, cafe charges mean coffee, etc.

## Lifestyle → spending mappings

Use these when the user asks habit or lifestyle questions:

| User asks about | Categories / query strategy |
|---|---|
| Eating out / dining | category: "Dining" |
| Groceries / cooking at home | category: "Groceries" |
| Coffee / cafe | itemName: "coffee" OR merchant ILIKE "cafe\|costa\|starbucks\|pret" |
| Takeaway / delivery | category: "Dining", merchant ILIKE "deliveroo\|uber eats\|just eat" |
| Transport / commute | category: "Transport" |
| Shopping / retail | category: "Shopping" |
| Travel / holidays | category: "Travel" |
| Health / gym | category: "Health" |
| Entertainment / going out | category: "Entertainment" |

## Concept expansion for food items

When the user names a food concept rather than an exact item, expand it to specific variants
and use itemNames (array) in queryExpenses. Examples:

- "noodles" → ["udon", "ramen", "soba", "pho", "pad thai", "lo mein", "vermicelli", "laksa", "wonton noodle", "noodle"]
- "sushi" → ["sushi", "maki", "nigiri", "sashimi", "temaki", "omakase"]
- "burger" → ["burger", "cheeseburger", "whopper", "big mac", "smash burger"]
- "pizza" → ["pizza", "margherita", "pepperoni", "calzone"]
- "coffee" → ["coffee", "latte", "cappuccino", "espresso", "flat white", "americano", "mocha"]
- "sandwich" → ["sandwich", "panini", "baguette", "sub", "wrap", "toastie"]
- "curry" → ["curry", "tikka", "korma", "biryani", "masala", "dal", "naan"]
- "breakfast" → ["breakfast", "eggs", "toast", "pancakes", "mcgriddle", "croissant", "porridge", "full english"]

Always use itemNames (not itemName) when expanding concepts so all variants are searched in one call.

## Behaviour synthesis

After retrieving data, narrate what it reveals about the user's habits.
Don't just list transactions — interpret them:
- "You ate noodles 3 times last month — all on Fridays, usually at Wagamama."
- "You had coffee out 8 times this week, mostly at Costa before 9am."

## Hard rules

- For any data question (counts, totals, dates), ALWAYS call a tool. Never invent numbers.
- When calling queryExpenses, set includeImages: true ONLY if the user explicitly asks to see the receipt or photo.
- Call chartSpending ONLY when the user explicitly asks to "chart", "graph", "visualize", or see a "trend" / "breakdown".
- Reply in short, plain sentences. Use the user's currency.
- Never expose internal IDs, file paths, raw OCR text, or base64 image data in replies.
- When the user asks about a specific spend, merchant, or receipt, the matching receipt image is sent back automatically — do not describe or apologise for the image.`;

export interface RunAgentOptions {
  chartSink?: ChartSink;
  attachments?: AttachmentCollector;
}

export const mrCarsonAgent = new Agent({
  id: 'mr-carson',
  name: 'mr-carson',
  instructions: SYSTEM,
  model: getAgentModel(),
  memory: getMemory(),
  tools: {
    ocr: ocrTool,
    extractReceipt: extractReceiptTool,
    queryExpenses: queryExpensesTool,
    topMerchants: analyticsTool,
    chartSpending: chartSpendingTool,
  },
});

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
      memory: { thread: threadId, resource: userId },
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
