import { createTool } from '@mastra/core/tools';
import { expensesRepo } from '@mr-carson/database';
import {
  QueryExpensesArgsSchema,
  QueryExpensesResultSchema,
} from '@mr-carson/shared-types';

export interface AttachmentCollector {
  add(sourceFile: string): void;
}

/**
 * The agent never writes SQL. It picks structured filters; the repository
 * compiles them into a parameterized query. User isolation is enforced by
 * threading the Telegram userId through the request context.
 *
 * When an attachment collector is provided, distinct non-null sourceFiles
 * from the result set are pushed to it so the bot can surface the original
 * receipt image alongside the agent's text reply.
 */
export function makeQueryExpensesTool(
  userId: string,
  attachments?: AttachmentCollector,
) {
  return createTool({
    id: 'queryExpenses',
    description:
      "Aggregate the user's expenses by optional category / merchant / date range. Returns matching line items and the total.",
    inputSchema: QueryExpensesArgsSchema,
    outputSchema: QueryExpensesResultSchema,
    execute: async ({ context }) => {
      const result = await expensesRepo.queryExpenses(userId, context);
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
}
