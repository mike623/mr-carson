import type { Expense } from '@mr-carson/shared-types';

const CATEGORY_EMOJI: Record<string, string> = {
  Groceries: '🛒',
  Dining: '🍽️',
  Pets: '🐾',
  Transport: '🚌',
  Utilities: '💡',
  Entertainment: '🎬',
  Health: '💊',
  Household: '🏠',
  Shopping: '🛍️',
  Travel: '✈️',
  Other: '•',
};

function money(amount: number, currency: string): string {
  return `${currency} ${amount.toFixed(2)}`;
}

export function formatExpensePreview(expense: Expense): string {
  const lines: string[] = [];
  lines.push(`*${escapeMd(expense.merchant)}* — ${escapeMd(expense.date)}`);
  lines.push('');
  for (const item of expense.items) {
    const emoji = CATEGORY_EMOJI[item.category] ?? '•';
    lines.push(
      `${emoji} ${escapeMd(item.name)}  _${escapeMd(item.category)}_  ${escapeMd(
        money(item.amount, expense.currency),
      )}`,
    );
  }
  lines.push('');
  lines.push(`*Total:* ${escapeMd(money(expense.total, expense.currency))}`);
  return lines.join('\n');
}

// Telegram MarkdownV2 reserved-char escape.
export function escapeMd(s: string): string {
  return s.replace(/([_*\[\]()~`>#+\-=|{}.!\\])/g, '\\$1');
}
