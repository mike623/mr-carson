import { DEFAULT_CATEGORIES } from '@mr-carson/shared-types';
import { getConnection, type DbConfig } from './client.js';

export async function seedCategories(config?: DbConfig): Promise<void> {
  const conn = await getConnection(config);
  for (const name of DEFAULT_CATEGORIES) {
    await conn.run(
      `INSERT INTO categories (name, is_default) VALUES (?, TRUE)
       ON CONFLICT (name) DO NOTHING`,
      [name] as never,
    );
  }
}
