import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { expensesRepo } from '@mr-carson/database';
import { DateRangeSchema } from '@mr-carson/shared-types';

export function makeAnalyticsTool(userId: string) {
  return createTool({
    id: 'topMerchants',
    description: 'Return the top-N merchants by total spend over a date range.',
    inputSchema: z.object({
      dateRange: DateRangeSchema.optional(),
      topN: z.number().int().positive().max(20).optional(),
    }),
    outputSchema: z.object({
      merchants: z.array(
        z.object({
          merchant: z.string(),
          total: z.number(),
          currency: z.string(),
        }),
      ),
    }),
    execute: async ({ context }) => {
      const merchants = await expensesRepo.topMerchants(
        userId,
        { dateRange: context.dateRange },
        context.topN ?? 5,
      );
      return { merchants };
    },
  });
}
