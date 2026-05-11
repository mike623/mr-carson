import { describe, expect, it } from 'vitest';
import {
  ExpenseSchema,
  QueryExpensesArgsSchema,
  PendingStatusSchema,
  DEFAULT_CATEGORIES,
} from './index.js';

describe('ExpenseSchema', () => {
  const valid = {
    merchant: 'Tesco',
    date: '2026-05-01',
    currency: 'gbp',
    total: 12.5,
    items: [{ name: 'Milk', amount: 1.2, category: 'Groceries' }],
  };

  it('parses a valid expense and uppercases currency', () => {
    const parsed = ExpenseSchema.parse(valid);
    expect(parsed.currency).toBe('GBP');
    expect(parsed.items).toHaveLength(1);
  });

  it('rejects malformed date', () => {
    expect(() => ExpenseSchema.parse({ ...valid, date: '01/05/2026' })).toThrow();
  });

  it('rejects negative total', () => {
    expect(() => ExpenseSchema.parse({ ...valid, total: -1 })).toThrow();
  });

  it('rejects empty items', () => {
    expect(() => ExpenseSchema.parse({ ...valid, items: [] })).toThrow();
  });

  it('rejects 2-letter currency', () => {
    expect(() => ExpenseSchema.parse({ ...valid, currency: 'GB' })).toThrow();
  });
});

describe('QueryExpensesArgsSchema', () => {
  it('accepts empty args', () => {
    expect(QueryExpensesArgsSchema.parse({})).toEqual({});
  });

  it('accepts a date range enum', () => {
    expect(QueryExpensesArgsSchema.parse({ dateRange: 'last_week' }).dateRange).toBe('last_week');
  });

  it('rejects malformed startDate', () => {
    expect(() => QueryExpensesArgsSchema.parse({ startDate: 'yesterday' })).toThrow();
  });

  it('rejects limit > 1000', () => {
    expect(() => QueryExpensesArgsSchema.parse({ limit: 5000 })).toThrow();
  });
});

describe('PendingStatusSchema', () => {
  it('accepts the canonical statuses', () => {
    for (const s of [
      'RECEIVED',
      'OCR_COMPLETE',
      'AWAITING_CONFIRMATION',
      'CONFIRMED',
      'REJECTED',
      'INSERTED',
      'FAILED',
    ]) {
      expect(PendingStatusSchema.parse(s)).toBe(s);
    }
  });

  it('rejects unknown status', () => {
    expect(() => PendingStatusSchema.parse('PENDING')).toThrow();
  });
});

describe('DEFAULT_CATEGORIES', () => {
  it('contains Other as the catch-all', () => {
    expect(DEFAULT_CATEGORIES).toContain('Other');
  });
});
