import { createBot } from './bot.js';

const bot = createBot();

bot.launch().then(() => {
  // eslint-disable-next-line no-console
  console.log('mr-carson telegram bot started');
});

process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));
