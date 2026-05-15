import { z } from 'zod';

export const DEFAULT_CATEGORIES = [
  'Groceries',
  'Dining',
  'Pets',
  'Transport',
  'Utilities',
  'Entertainment',
  'Health',
  'Household',
  'Shopping',
  'Travel',
  'Other',
] as const;

export type DefaultCategory = (typeof DEFAULT_CATEGORIES)[number];

export const ExpenseItemSchema = z.object({
  name: z.string().min(1),
  amount: z.number().nonnegative(),
  category: z.string().min(1),
});

export const ExpenseSchema = z.object({
  merchant: z.string().min(1),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
  currency: z.string().length(3).toUpperCase(),
  total: z.number().nonnegative(),
  vat: z.number().nonnegative().optional(),
  items: z.array(ExpenseItemSchema).min(1),
});

export type ExpenseItem = z.infer<typeof ExpenseItemSchema>;
export type Expense = z.infer<typeof ExpenseSchema>;

export const PendingStatusSchema = z.enum([
  'RECEIVED',
  'OCR_COMPLETE',
  'AWAITING_CONFIRMATION',
  'CONFIRMED',
  'REJECTED',
  'INSERTED',
  'FAILED',
]);
export type PendingStatus = z.infer<typeof PendingStatusSchema>;

export const PendingExpenseSchema = z.object({
  id: z.string().uuid(),
  userId: z.string(),
  chatId: z.string(),
  status: PendingStatusSchema,
  filePath: z.string().nullable(),
  rawOcr: z.string().nullable(),
  extracted: ExpenseSchema.nullable(),
  errorMessage: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type PendingExpense = z.infer<typeof PendingExpenseSchema>;

export const DateRangeSchema = z.enum([
  'today',
  'yesterday',
  'this_week',
  'last_week',
  'this_month',
  'last_month',
  'this_year',
  'all_time',
]);
export type DateRange = z.infer<typeof DateRangeSchema>;

export const QueryExpensesArgsSchema = z.object({
  category: z.string().optional(),
  merchant: z.string().optional(),
  dateRange: DateRangeSchema.optional(),
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  limit: z.number().int().positive().max(1000).optional(),
  includeImages: z.boolean().optional(),
});
export type QueryExpensesArgs = z.infer<typeof QueryExpensesArgsSchema>;

export const QueryExpensesResultSchema = z.object({
  total: z.number(),
  vatTotal: z.number(),
  currency: z.string(),
  count: z.number().int().nonnegative(),
  rows: z
    .array(
      z.object({
        expenseId: z.string(),
        date: z.string(),
        merchant: z.string(),
        name: z.string(),
        category: z.string(),
        amount: z.number(),
        currency: z.string(),
        sourceFile: z.string().nullable(),
      }),
    )
    .max(1000),
});
export type QueryExpensesResult = z.infer<typeof QueryExpensesResultSchema>;

export const GranularitySchema = z.enum(['day', 'week', 'month']);
export type Granularity = z.infer<typeof GranularitySchema>;

export const ChartTypeSchema = z.enum(['bar', 'line', 'pie', 'doughnut']);
export type ChartType = z.infer<typeof ChartTypeSchema>;

export const ChartSpendingArgsSchema = z.object({
  category: z.string().optional(),
  dateRange: DateRangeSchema.optional(),
  startDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  endDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional(),
  granularity: GranularitySchema.optional(),
  chartType: ChartTypeSchema.optional(),
  stacked: z.boolean().optional(),
});
export type ChartSpendingArgs = z.infer<typeof ChartSpendingArgsSchema>;

export const ChartSpendingResultSchema = z.object({
  summary: z.string(),
  chartType: ChartTypeSchema,
  granularity: GranularitySchema,
  currency: z.string(),
  totalsByCategory: z.array(z.object({ category: z.string(), total: z.number() })),
  buckets: z.array(z.string()),
  imageBase64: z.string(),
});
export type ChartSpendingResult = z.infer<typeof ChartSpendingResultSchema>;

export const OcrResultSchema = z.object({
  structured: ExpenseSchema.nullable(),
  rawText: z.string(),
  confidence: z.number().min(0).max(1).optional(),
});
export type OcrResult = z.infer<typeof OcrResultSchema>;
