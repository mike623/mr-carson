import type { DateRange, QueryExpensesArgs } from '@mr-carson/shared-types';

function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function startOfWeek(d: Date): Date {
  // ISO week, Monday-start.
  const out = new Date(d);
  const day = (out.getUTCDay() + 6) % 7;
  out.setUTCDate(out.getUTCDate() - day);
  out.setUTCHours(0, 0, 0, 0);
  return out;
}

export function rangeFor(name: DateRange, now: Date = new Date()): { start: string; end: string } {
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  switch (name) {
    case 'today':
      return { start: iso(today), end: iso(today) };
    case 'yesterday': {
      const y = new Date(today);
      y.setUTCDate(y.getUTCDate() - 1);
      return { start: iso(y), end: iso(y) };
    }
    case 'this_week': {
      const start = startOfWeek(today);
      const end = new Date(start);
      end.setUTCDate(end.getUTCDate() + 6);
      return { start: iso(start), end: iso(end) };
    }
    case 'last_week': {
      const thisWeekStart = startOfWeek(today);
      const start = new Date(thisWeekStart);
      start.setUTCDate(start.getUTCDate() - 7);
      const end = new Date(thisWeekStart);
      end.setUTCDate(end.getUTCDate() - 1);
      return { start: iso(start), end: iso(end) };
    }
    case 'this_month': {
      const start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1));
      const end = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 0));
      return { start: iso(start), end: iso(end) };
    }
    case 'last_month': {
      const start = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, 1));
      const end = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 0));
      return { start: iso(start), end: iso(end) };
    }
    case 'this_year': {
      const start = new Date(Date.UTC(today.getUTCFullYear(), 0, 1));
      const end = new Date(Date.UTC(today.getUTCFullYear(), 11, 31));
      return { start: iso(start), end: iso(end) };
    }
    case 'all_time':
      return { start: '0001-01-01', end: '9999-12-31' };
  }
}

export function resolveDateRange(args: QueryExpensesArgs): { start: string; end: string } | null {
  if (args.startDate && args.endDate) return { start: args.startDate, end: args.endDate };
  if (args.dateRange) return rangeFor(args.dateRange);
  return null;
}
