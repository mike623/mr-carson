import { MastraLogger } from '@mastra/core/logger';

type Level = 'debug' | 'info' | 'warn' | 'error' | 'silent';

const RANK: Record<Level, number> = {
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
  silent: 100,
};

const STR_LIMIT = 2000;
const ARRAY_LIMIT = 50;
const DEPTH_LIMIT = 5;

function isPlainObject(v: unknown): v is Record<string, unknown> {
  if (v === null || typeof v !== 'object') return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function normalize(v: unknown, depth = 0): unknown {
  if (v === null || v === undefined) return v;
  if (typeof v === 'bigint') return v.toString();
  if (v instanceof Error) {
    return { name: v.name, message: v.message, stack: v.stack };
  }
  if (typeof v === 'string') {
    return v.length > STR_LIMIT
      ? `${v.slice(0, STR_LIMIT)}…(+${v.length - STR_LIMIT})`
      : v;
  }
  if (typeof Buffer !== 'undefined' && Buffer.isBuffer(v)) {
    return `<Buffer ${(v as Buffer).length}b>`;
  }
  if (v instanceof Uint8Array) return `<Bytes ${v.byteLength}b>`;
  if (depth >= DEPTH_LIMIT) return '[truncated:depth]';
  if (Array.isArray(v)) {
    const out = v.slice(0, ARRAY_LIMIT).map((x) => normalize(x, depth + 1));
    if (v.length > ARRAY_LIMIT) out.push(`…(+${v.length - ARRAY_LIMIT})`);
    return out;
  }
  if (typeof v === 'object') {
    const o: Record<string, unknown> = {};
    for (const [k, val] of Object.entries(v as object)) {
      o[k] = normalize(val, depth + 1);
    }
    return o;
  }
  return v;
}

function mergeArgs(args: unknown[]): Record<string, unknown> {
  if (args.length === 0) return {};
  if (args.length === 1 && isPlainObject(args[0])) {
    return normalize(args[0]) as Record<string, unknown>;
  }
  return { args: normalize(args) as unknown[] };
}

/**
 * Structured JSON logger for the Mastra agent. One line per event, sorted by
 * `ts` + `runId` for grep-friendly debugging. Subclass of MastraLogger so
 * `agent.__setLogger(...)` propagates it through the agent's memory + tool
 * dispatch internals as well.
 */
export class JsonLogger extends MastraLogger {
  private threshold: number;
  private loggerName: string;

  constructor(opts: { name?: string; level?: Level } = {}) {
    const level: Level =
      opts.level ?? ((process.env.LOG_LEVEL as Level | undefined) || 'info');
    super({ name: opts.name ?? 'mr-carson', level });
    this.loggerName = opts.name ?? 'mr-carson';
    this.threshold = RANK[level] ?? RANK.info;
  }

  private emit(
    level: Exclude<Level, 'silent'>,
    message: string,
    args: unknown[],
  ): void {
    if (RANK[level] < this.threshold) return;
    const entry = {
      ts: new Date().toISOString(),
      level,
      logger: this.loggerName,
      pid: process.pid,
      msg: message,
      ...mergeArgs(args),
    };
    let line: string;
    try {
      line = JSON.stringify(entry);
    } catch {
      line = JSON.stringify({
        ts: entry.ts,
        level,
        logger: this.loggerName,
        msg: message,
        warn: 'serialization-failed',
      });
    }
    const stream = level === 'error' || level === 'warn'
      ? process.stderr
      : process.stdout;
    stream.write(line + '\n');
  }

  debug(message: string, ...args: any[]): void {
    this.emit('debug', message, args);
  }
  info(message: string, ...args: any[]): void {
    this.emit('info', message, args);
  }
  warn(message: string, ...args: any[]): void {
    this.emit('warn', message, args);
  }
  error(message: string, ...args: any[]): void {
    this.emit('error', message, args);
  }
}

export const agentLogger = new JsonLogger({ name: 'mr-carson' });
