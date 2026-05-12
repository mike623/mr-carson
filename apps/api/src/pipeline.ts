import { expensesRepo, pendingRepo } from '@mr-carson/database';
import type { Expense, OcrResult } from '@mr-carson/shared-types';
import { ExpenseSchema } from '@mr-carson/shared-types';
import { ocrTool } from './tools/ocr.js';
import { extractReceiptTool } from './tools/extractReceipt.js';

/**
 * Drive a receipt from "file on disk" → "ready for user confirmation".
 *
 * Step 1: run GLM-OCR.
 * Step 2: if the sidecar returned structured JSON, use it directly.
 *         Otherwise, ask the LLM to extract from raw OCR text.
 * Step 3: persist the extraction on the pending row so the bot can show a
 *         confirmation UI even if the process restarts.
 */
export async function processReceipt(opts: {
  pendingId: string;
  filePath: string;
}): Promise<Expense> {
  const ocr: OcrResult = await ocrTool.execute!({
    context: { filePath: opts.filePath },
  } as never);

  await pendingRepo.setPendingOcr(opts.pendingId, ocr.rawText);

  let expense: Expense;
  if (ocr.structured) {
    expense = ExpenseSchema.parse(ocr.structured);
  } else {
    expense = (await extractReceiptTool.execute!({
      context: { rawText: ocr.rawText },
    } as never)) as Expense;
  }

  await pendingRepo.setPendingExtraction(opts.pendingId, expense);
  return expense;
}

/**
 * Commit a user-confirmed expense to DuckDB and mark the pending row inserted.
 */
export async function commitConfirmed(opts: {
  pendingId: string;
  userId: string;
  expense: Expense;
  sourceFile?: string | null;
}): Promise<{ id: string }> {
  const result = await expensesRepo.insertExpense({
    userId: opts.userId,
    expense: opts.expense,
    sourceFile: opts.sourceFile ?? null,
  });
  await pendingRepo.setPendingStatus(opts.pendingId, 'INSERTED');
  return result;
}
