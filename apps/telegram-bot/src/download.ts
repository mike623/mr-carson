import { mkdirSync, createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import type { Telegram } from 'telegraf';
import { config } from './config.js';

export async function downloadTelegramFile(
  telegram: Telegram,
  fileId: string,
  suggestedName: string,
): Promise<string> {
  mkdirSync(config.uploadsDir, { recursive: true });
  const link = await telegram.getFileLink(fileId);
  const res = await fetch(link.toString());
  if (!res.ok || !res.body) {
    throw new Error(`telegram file download failed: ${res.status}`);
  }
  const dest = join(config.uploadsDir, `${Date.now()}-${suggestedName}`);
  await pipeline(Readable.fromWeb(res.body as never), createWriteStream(dest));
  return dest;
}
