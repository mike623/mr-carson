ARG NODE_VERSION=20.10.0

# ---------- builder ----------
FROM node:${NODE_VERSION}-bookworm AS builder
WORKDIR /app

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@9.12.0 --activate

COPY pnpm-workspace.yaml package.json turbo.json tsconfig.base.json ./
COPY packages packages
COPY apps apps

RUN pnpm install --frozen-lockfile=false
RUN pnpm --filter @mr-carson/database build
RUN pnpm --filter @mr-carson/shared-types build
RUN pnpm --filter @mr-carson/telegram-bot build
# mastra build bundles the API into apps/api/.mastra/output/
RUN pnpm --filter @mr-carson/api build

# ---------- runtime ----------
FROM node:${NODE_VERSION}-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN corepack enable && corepack prepare pnpm@9.12.0 --activate

COPY --from=builder /app /app
RUN pnpm install --prod --frozen-lockfile=false

COPY infrastructure/fly/start.sh /start.sh
RUN chmod +x /start.sh

CMD ["/start.sh"]
