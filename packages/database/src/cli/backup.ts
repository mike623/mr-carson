import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { closeConnection, getDbPath, run } from '../client.js';

const srcPath = getDbPath();
const date = new Date().toISOString().slice(0, 10);
const backupDir = resolve(process.env.BACKUP_DIR ?? './data/backups');
const destPath = `${backupDir}/mr-carson-${date}.duckdb`;

mkdirSync(backupDir, { recursive: true });

await run(`ATTACH '${destPath}' AS backup`);
await run(`COPY FROM DATABASE main TO backup`);
await run(`DETACH backup`);

console.log(`backup: ${srcPath} → ${destPath}`);
await closeConnection();
