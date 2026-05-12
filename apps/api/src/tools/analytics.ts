import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { expensesRepo } from '@mr-carson/database';
import { DateRangeSchema } from '@mr-carson/shared-types';

export const analyticsTool = createTool({
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
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const merchants = await expensesRepo.topMerchants(
      userId,
      { dateRange: inputData.dateRange },
      inputData.topN ?? 5,
    );
    return { merchants };
  },
});
