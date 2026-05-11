import { Context, Markup, Telegraf } from 'telegraf';
import { message } from 'telegraf/filters';
import { config } from './config.js';
import { ask, confirmPending, getPending, ingestReceipt, rejectPending } from './api.js';
import { downloadTelegramFile } from './download.js';
import { escapeMd, formatExpensePreview } from './format.js';

export function createBot(): Telegraf {
  // Local Ollama OCR + extraction can take a minute on cold start; the default
  // 90s Telegraf handler timeout fires before we can reply. Bump to 5 minutes.
  const bot = new Telegraf(config.botToken, { handlerTimeout: 300_000 });

  // Allow-list guard: silently drop anything from non-allowed users.
  bot.use(async (ctx, next) => {
    const userId = ctx.from?.id?.toString();
    if (!userId || !config.allowedUserIds.has(userId)) return;
    return next();
  });

  bot.command('start', async (ctx) => {
    await ctx.reply(
      "Hi, I'm Mr. Carson. Send me a receipt photo and I'll log the expense.",
    );
  });

  bot.command('help', async (ctx) => {
    await ctx.reply(
      [
        'Commands:',
        '/start  — say hello',
        '/help   — this message',
        '/summary — recent spend summary',
        '/chart   — spending chart, last month by category',
        '/categories — list categories',
        '',
        'Or just send a receipt photo, or ask in plain English.',
      ].join('\n'),
    );
  });

  bot.command('summary', async (ctx) => {
    const reply = await ask(ctx.from!.id.toString(), 'Summarise my spending this month.');
    await deliverAgentReply(ctx, reply);
  });

  bot.command('categories', async (ctx) => {
    const reply = await ask(ctx.from!.id.toString(), 'List my expense categories.');
    await deliverAgentReply(ctx, reply);
  });

  bot.command('chart', async (ctx) => {
    const reply = await ask(
      ctx.from!.id.toString(),
      'Chart my spending over the last month by category.',
    );
    await deliverAgentReply(ctx, reply);
  });

  // Photo / document handlers: ingest, then show confirmation buttons.
  bot.on(message('photo'), async (ctx) => {
    const photos = ctx.message.photo;
    const best = photos[photos.length - 1];
    if (!best) return;
    await handleFile(ctx, best.file_id, `photo-${best.file_unique_id}.jpg`);
  });

  bot.on(message('document'), async (ctx) => {
    const doc = ctx.message.document;
    // Telegram delivers images as "documents" when the user picks them as files
    // (no compression) — those are fine. Anything else (PDFs, etc.) is rejected.
    if (doc.mime_type?.startsWith('image/')) {
      await handleFile(ctx, doc.file_id, doc.file_name ?? `doc-${doc.file_unique_id}`);
      return;
    }
    await ctx.reply('Please send the receipt as a photo.');
  });

  bot.on(message('text'), async (ctx) => {
    const text = ctx.message.text;
    const userId = ctx.from.id.toString();
    await ctx.sendChatAction('typing');
    const result = await ask(userId, text);
    await deliverAgentReply(ctx, result);
  });

  bot.action(/^confirm:(.+)$/, async (ctx) => {
    const id = ctx.match[1]!;
    try {
      await confirmPending(id);
      await ctx.editMessageReplyMarkup(undefined);
      await ctx.reply('Saved. ✅');
    } catch (err) {
      await ctx.reply(`Could not save: ${(err as Error).message}`);
    } finally {
      await ctx.answerCbQuery();
    }
  });

  bot.action(/^reject:(.+)$/, async (ctx) => {
    const id = ctx.match[1]!;
    try {
      await rejectPending(id);
      await ctx.editMessageReplyMarkup(undefined);
      await ctx.reply('Discarded.');
    } catch (err) {
      await ctx.reply(`Could not discard: ${(err as Error).message}`);
    } finally {
      await ctx.answerCbQuery();
    }
  });

  bot.action(/^edit:(.+)$/, async (ctx) => {
    const id = ctx.match[1]!;
    const pending = await getPending(id);
    await ctx.reply(
      `To edit, reply with corrected JSON for receipt ${id}. (Editing UI coming soon.)\n\nCurrent:\n${JSON.stringify(
        pending.extracted,
        null,
        2,
      )}`,
    );
    await ctx.answerCbQuery();
  });

  return bot;
}

// Telegram caption hard limit.
const CAPTION_MAX = 1024;

async function deliverAgentReply(
  ctx: Context,
  result: { reply: string; imageBase64?: string },
): Promise<void> {
  const reply = result.reply.trim();
  if (result.imageBase64) {
    const buf = Buffer.from(result.imageBase64, 'base64');
    const caption = reply.length > 0 && reply.length <= CAPTION_MAX ? reply : undefined;
    await ctx.replyWithPhoto({ source: buf }, caption ? { caption } : undefined);
    if (reply.length > CAPTION_MAX) await ctx.reply(reply);
    return;
  }
  if (reply.length > 0) await ctx.reply(reply);
}

async function handleFile(ctx: Context, fileId: string, name: string): Promise<void> {
  await ctx.sendChatAction('typing');
  try {
    const localPath = await downloadTelegramFile(ctx.telegram, fileId, name);
    const userId = ctx.from!.id.toString();
    const chatId = ctx.chat!.id.toString();
    const { pendingId, expense } = await ingestReceipt({ userId, chatId, filePath: localPath });

    await ctx.replyWithMarkdownV2(formatExpensePreview(expense), {
      ...Markup.inlineKeyboard([
        [
          Markup.button.callback('✅ Confirm', `confirm:${pendingId}`),
          Markup.button.callback('✏️ Edit', `edit:${pendingId}`),
          Markup.button.callback('🗑 Reject', `reject:${pendingId}`),
        ],
      ]),
    });
  } catch (err) {
    await ctx.reply(`Couldn't process that receipt: ${escapeMd((err as Error).message)}`);
  }
}
