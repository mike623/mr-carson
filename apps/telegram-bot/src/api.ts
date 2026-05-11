import type { Expense, PendingExpense } from '@mr-carson/shared-types';
import { config } from './config.js';

async function fetchJson<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(config.apiUrl + path, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers ?? {}) },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`api ${res.status} ${path}: ${body}`);
  }
  return (await res.json()) as T;
}

export async function ingestReceipt(input: {
  userId: string;
  chatId: string;
  filePath: string;
}): Promise<{ pendingId: string; expense: Expense }> {
  return fetchJson('/receipts/ingest', { method: 'POST', body: JSON.stringify(input) });
}

export async function confirmPending(id: string): Promise<{ id: string }> {
  return fetchJson(`/receipts/${id}/confirm`, { method: 'POST' });
}

export async function rejectPending(id: string): Promise<{ ok: true }> {
  return fetchJson(`/receipts/${id}/reject`, { method: 'POST' });
}

export async function getPending(id: string): Promise<PendingExpense> {
  return fetchJson(`/receipts/${id}`);
}

export interface AskResponse {
  reply: string;
  attachments: string[];
  imageBase64?: string;
}

export async function ask(userId: string, message: string): Promise<AskResponse> {
  const res = await fetchJson<Partial<AskResponse>>('/agent/ask', {
    method: 'POST',
    body: JSON.stringify({ userId, message }),
  });
  return {
    reply: res.reply ?? '',
    attachments: Array.isArray(res.attachments) ? res.attachments : [],
    ...(typeof res.imageBase64 === 'string' && res.imageBase64.length > 0
      ? { imageBase64: res.imageBase64 }
      : {}),
  };
}

export async function newSession(userId: string): Promise<{ threadId: string }> {
  return fetchJson('/agent/new', {
    method: 'POST',
    body: JSON.stringify({ userId }),
  });
}
