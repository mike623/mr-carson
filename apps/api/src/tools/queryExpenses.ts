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
    "Aggregate the user's expenses by optional filters. " +
    'Filters: category (e.g. "Dining"), merchant (ILIKE), ' +
    'itemName (single ILIKE on receipt line-item name, e.g. "udon"), ' +
    'itemNames (array of terms ORed together — use this for concept expansion, ' +
    'e.g. ["udon","ramen","pho","soba","pad thai","lo mein"] for "noodles"), ' +
    'dateRange / startDate+endDate. ' +
    'Returns matching line items, spend total, and VAT total.',
  inputSchema: QueryExpensesArgsSchema,
  outputSchema: QueryExpensesResultSchema,
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const attachments = requestContext?.get('attachments') as AttachmentCollector | undefined;
    const result = await expensesRepo.queryExpenses(userId, inputData);
    if (attachments && inputData.includeImages) {
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
