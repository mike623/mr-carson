import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { getConnection, type DbConfig } from './client.js';

const here = dirname(fileURLToPath(import.meta.url));

export async function migrate(config?: DbConfig): Promise<void> {
  const schemaPath = join(here, 'schema.sql');
  const sql = readFileSync(schemaPath, 'utf-8');
  const conn = await getConnection(config);
  // DuckDB accepts a single multi-statement string.
  await conn.run(sql);
}
