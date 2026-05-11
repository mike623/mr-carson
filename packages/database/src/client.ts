import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { DuckDBInstance, type DuckDBConnection } from '@duckdb/node-api';

let instancePromise: Promise<DuckDBInstance> | null = null;
let connectionPromise: Promise<DuckDBConnection> | null = null;

export interface DbConfig {
  /** Absolute or relative path to the .duckdb file. */
  path?: string;
}

export function getDbPath(config: DbConfig = {}): string {
  const raw = config.path ?? process.env.DUCKDB_PATH ?? './data/mr-carson.duckdb';
  return resolve(raw);
}

export async function getConnection(config: DbConfig = {}): Promise<DuckDBConnection> {
  if (!connectionPromise) {
    const path = getDbPath(config);
    mkdirSync(dirname(path), { recursive: true });
    instancePromise = DuckDBInstance.create(path);
    connectionPromise = instancePromise.then((i) => i.connect());
  }
  return connectionPromise;
}

export async function closeConnection(): Promise<void> {
  if (connectionPromise) {
    const conn = await connectionPromise;
    conn.close();
    connectionPromise = null;
    instancePromise = null;
  }
}

/**
 * Run a parameterized query and return rows as plain objects.
 * DuckDB returns Decimal/Date as native objects — we coerce to JS primitives
 * because the rest of the app deals in numbers and ISO strings.
 */
export async function query<T = Record<string, unknown>>(
  sql: string,
  params: unknown[] = [],
  config?: DbConfig,
): Promise<T[]> {
  const conn = await getConnection(config);
  const reader = await conn.runAndReadAll(sql, params as never);
  return reader.getRowObjectsJson() as T[];
}

export async function run(sql: string, params: unknown[] = [], config?: DbConfig): Promise<void> {
  const conn = await getConnection(config);
  await conn.run(sql, params as never);
}
