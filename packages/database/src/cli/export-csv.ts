import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { closeConnection, run } from '../client.js';

const TABLES = ['categories', 'merchants', 'expenses', 'expense_items', 'pending_expenses', 'chat_sessions'];

const date = new Date().toISOString().slice(0, 10);
const exportDir = resolve(process.env.EXPORT_DIR ?? `./data/exports/${date}`);
mkdirSync(exportDir, { recursive: true });

for (const table of TABLES) {
  const dest = `${exportDir}/${table}.csv`;
  await run(`COPY ${table} TO '${dest}' (HEADER, DELIMITER ',')`);
  console.log(`export-csv: ${table} → ${dest}`);
}

await closeConnection();
