import { Agent } from '@mastra/core/agent';
import { getModel } from './llm.js';
import { getMemory } from './memory.js';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';
import { makeQueryExpensesTool } from './tools/queryExpenses.js';
import { makeAnalyticsTool } from './tools/analytics.js';

const SYSTEM = `You are Mr. Carson, a careful personal-finance assistant.

You help one user track and query their expenses.

Hard rules:
- For data questions, ALWAYS call a tool (queryExpenses or topMerchants). Never
  invent totals or item lists.
- Reply in short, plain sentences. Use the user's currency.
- If the user asks something you cannot answer from tools, say so.
- Never expose internal IDs, file paths, or raw OCR text in replies.`;

/**
 * Each request builds a fresh agent that closes over the calling userId so
 * tool executions are tenant-scoped at construction time.
 */
export function buildAgent(userId: string): Agent {
  return new Agent({
    name: 'mr-carson',
    instructions: SYSTEM,
    model: getModel(),
    memory: getMemory(),
    tools: {
      ocr: ocrTool,
      extractReceipt: extractReceiptTool,
      queryExpenses: makeQueryExpensesTool(userId),
      topMerchants: makeAnalyticsTool(userId),
    },
  });
}

/**
 * Run one conversational turn. `threadId` scopes Mastra Memory recall — a new
 * threadId starts a fresh session (see /new).
 */
export async function runAgent(
  userId: string,
  threadId: string,
  message: string,
): Promise<string> {
  const agent = buildAgent(userId);
  const result = await agent.generate(message, {
    maxSteps: 6,
    threadId,
    resourceId: userId,
  });
  return result.text ?? '';
}
