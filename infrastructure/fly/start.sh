#!/bin/sh
set -e

mkdir -p /data/uploads

# API (Mastra bundled output)
node apps/api/.mastra/output/index.mjs &
API_PID=$!

# Wait for API to be ready before starting bot
until wget -qO- http://localhost:${API_PORT:-47821}/health >/dev/null 2>&1; do
  sleep 2
done

# Bot (long-polling Telegram)
node apps/telegram-bot/dist/main.js &
BOT_PID=$!

# Exit if either process dies
wait $API_PID $BOT_PID
