import { createTool } from '@mastra/core/tools';
import { expensesRepo } from '@mr-carson/database';
import {
  QueryExpensesArgsSchema,
  QueryExpensesResultSchema,
} from '@mr-carson/shared-types';

/**
 * The agent never writes SQL. It picks structured filters; the repository
 * compiles them into a parameterized query. User isolation is enforced by
 * threading the Telegram userId through the request context.
 */
export function makeQueryExpensesTool(userId: string) {
  return createTool({
    id: 'queryExpenses',
    description:
      'Aggregate the user\'s expenses by optional category / merchant / date range. Returns matching line items and the total.',
    inputSchema: QueryExpensesArgsSchema,
    outputSchema: QueryExpensesResultSchema,
    execute: async ({ context }) => {
      return expensesRepo.queryExpenses(userId, context);
    },
  });
}
