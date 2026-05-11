import { query, run } from '../client.js';

export async function listCategories(): Promise<string[]> {
  const rows = await query<{ name: string }>(
    `SELECT name FROM categories ORDER BY is_default DESC, name ASC`,
  );
  return rows.map((r) => r.name);
}

export async function addCategory(name: string): Promise<void> {
  await run(
    `INSERT INTO categories (name, is_default) VALUES (?, FALSE)
     ON CONFLICT (name) DO NOTHING`,
    [name],
  );
}
