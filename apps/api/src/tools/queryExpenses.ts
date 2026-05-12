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

/**
 * @deprecated Use queryExpensesTool directly with requestContext instead.
 * Factory kept for backward compatibility during migration to @mastra/core v1.
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
