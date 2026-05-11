import { Agent } from '@mastra/core/agent';
import { getModel } from './llm.js';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';
import {
  makeQueryExpensesTool,
  type AttachmentCollector,
} from './tools/queryExpenses.js';
import { makeAnalyticsTool } from './tools/analytics.js';
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
  return new Agent({
    name: 'mr-carson',
    instructions: SYSTEM,
    model: getModel(),
    tools: {
      ocr: ocrTool,
      extractReceipt: extractReceiptTool,
      queryExpenses: makeQueryExpensesTool(userId, opts.attachments),
      topMerchants: makeAnalyticsTool(userId),
      chartSpending: makeChartSpendingTool(userId, chartSink),
    },
  });
}
