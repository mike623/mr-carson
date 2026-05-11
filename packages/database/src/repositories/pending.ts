import { v4 as uuid } from 'uuid';
import type { Expense, PendingExpense, PendingStatus } from '@mr-carson/shared-types';
import { query, run } from '../client.js';

export interface CreatePendingInput {
  userId: string;
  chatId: string;
  filePath: string | null;
}

export async function createPending(input: CreatePendingInput): Promise<string> {
  const id = uuid();
  await run(
    `INSERT INTO pending_expenses (id, user_id, chat_id, status, file_path)
     VALUES (?, ?, ?, 'RECEIVED', ?)`,
    [id, input.userId, input.chatId, input.filePath],
  );
  return id;
}

export async function setPendingStatus(
  id: string,
  status: PendingStatus,
  errorMessage?: string | null,
): Promise<void> {
  await run(
    `UPDATE pending_expenses
     SET status = ?, error_message = ?, updated_at = now()
     WHERE id = ?`,
    [status, errorMessage ?? null, id],
  );
}

export async function setPendingOcr(id: string, rawOcr: string): Promise<void> {
  await run(
    `UPDATE pending_expenses
     SET raw_ocr = ?, status = 'OCR_COMPLETE', updated_at = now()
     WHERE id = ?`,
    [rawOcr, id],
  );
}

export async function setPendingExtraction(id: string, expense: Expense): Promise<void> {
  await run(
    `UPDATE pending_expenses
     SET extracted_json = ?, status = 'AWAITING_CONFIRMATION', updated_at = now()
     WHERE id = ?`,
    [JSON.stringify(expense), id],
  );
}

interface PendingRow {
  id: string;
  user_id: string;
  chat_id: string;
  status: PendingStatus;
  file_path: string | null;
  raw_ocr: string | null;
  extracted_json: string | null;
  error_message: string | null;
  created_at: string;
  updated_at: string;
}

function toPending(row: PendingRow): PendingExpense {
  return {
    id: row.id,
    userId: row.user_id,
    chatId: row.chat_id,
    status: row.status,
    filePath: row.file_path,
    rawOcr: row.raw_ocr,
    extracted: row.extracted_json ? JSON.parse(row.extracted_json) : null,
    errorMessage: row.error_message,
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at),
  };
}

export async function getPending(id: string): Promise<PendingExpense | null> {
  const rows = await query<PendingRow>(`SELECT * FROM pending_expenses WHERE id = ?`, [id]);
  return rows[0] ? toPending(rows[0]) : null;
}

export async function getLatestPendingForUser(userId: string): Promise<PendingExpense | null> {
  const rows = await query<PendingRow>(
    `SELECT * FROM pending_expenses
     WHERE user_id = ? AND status = 'AWAITING_CONFIRMATION'
     ORDER BY created_at DESC LIMIT 1`,
    [userId],
  );
  return rows[0] ? toPending(rows[0]) : null;
}
