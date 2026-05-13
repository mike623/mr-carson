import { getConnection, type DbConfig } from './client.js';
import { SCHEMA_SQL } from './schema.js';

export async function migrate(config?: DbConfig): Promise<void> {
  const conn = await getConnection(config);
  // DuckDB accepts a single multi-statement string.
  await conn.run(SCHEMA_SQL);
}
