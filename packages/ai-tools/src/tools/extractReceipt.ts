import { createTool } from '@mastra/core/tools';
import { generateObject } from 'ai';
import { z } from 'zod';
import { ExpenseSchema, DEFAULT_CATEGORIES } from '@mr-carson/shared-types';
import { categoriesRepo } from '@mr-carson/database';
import { getModel } from '../llm.js';

const SYSTEM = `You convert noisy OCR text from receipts into strict JSON.

Rules:
- Output a single Expense object matching the provided schema.
- Skip subtotal, tax, and duplicate total rows. Only include real line items.
- Do NOT invent items. If a line is ambiguous, omit it.
- "total" must equal the receipt's grand total, not the sum of items.
- "date" must be YYYY-MM-DD. If absent, use today's date.
- "currency" must be a 3-letter ISO code. If unknown, use the provided default.
- "category" for each item must be chosen from the allowed list. Use "Other" if uncertain.`;

export const extractReceiptTool = createTool({
  id: 'extractReceipt',
  description:
    'Convert raw OCR text into a strict Expense JSON object. Use when the OCR sidecar returned only raw text.',
  inputSchema: z.object({
    rawText: z.string().min(1),
    defaultCurrency: z.string().length(3).optional(),
    today: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/)
      .optional(),
  }),
  outputSchema: ExpenseSchema,
  execute: async ({ context }) => {
    const allowedCategories = await categoriesRepo
      .listCategories()
      .catch(() => [...DEFAULT_CATEGORIES]);
    const defaultCurrency = context.defaultCurrency ?? process.env.DEFAULT_CURRENCY ?? 'GBP';
    const today = context.today ?? new Date().toISOString().slice(0, 10);

    const prompt = `Allowed categories: ${allowedCategories.join(', ')}
Default currency: ${defaultCurrency}
Today's date: ${today}

OCR text:
"""
${context.rawText}
"""`;

    const { object } = await generateObject({
      model: getModel(),
      schema: ExpenseSchema,
      system: SYSTEM,
      prompt,
    });
    return object;
  },
});
