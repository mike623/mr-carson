import { mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { Mastra } from '@mastra/core';
import { MastraCompositeStore } from '@mastra/core/storage';
import { LibSQLStore } from '@mastra/libsql';
import { DuckDBStore } from '@mastra/duckdb';
import { Observability, DefaultExporter } from '@mastra/observability';
import { mrCarsonAgent } from './agent.js';

function mastraDbUrl(): string {
  const raw = process.env.MASTRA_DB_PATH ?? './data/mastra.db';
  const abs = resolve(raw);
  mkdirSync(dirname(abs), { recursive: true });
  return `file:${abs}`;
}

export const mastra = new Mastra({
  agents: { mrCarson: mrCarsonAgent },
  storage: new MastraCompositeStore({
    id: 'mr-carson-storage',
    default: new LibSQLStore({ id: 'mr-carson-mastra', url: mastraDbUrl() }),
    domains: {
      observability: new DuckDBStore().observability,
    },
  }),
  observability: new Observability({
    configs: {
      default: {
        serviceName: 'mr-carson',
        exporters: [new DefaultExporter()],
      },
    },
  }),
});
