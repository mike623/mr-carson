function required(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(`missing env: ${name}`);
  }
  return v;
}

export const config = {
  botToken: required('TELEGRAM_BOT_TOKEN'),
  allowedUserIds: new Set(
    (process.env.TELEGRAM_ALLOWED_USER_IDS ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  ),
  apiUrl: process.env.API_URL ?? 'http://localhost:3000',
  uploadsDir: process.env.UPLOADS_DIR ?? '/data/uploads',
  defaultCurrency: process.env.DEFAULT_CURRENCY ?? 'GBP',
};
