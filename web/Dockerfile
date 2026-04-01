# Node.js 24.14.1
FROM node:24.14.1-bookworm-slim@sha256:06e5c9f86bfa0aaa7163cf37a5eaa8805f16b9acb48e3f85645b09d459fc2a9f AS base
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
RUN corepack enable

FROM base AS deps
COPY package.json pnpm-lock.yaml .npmrc ./
RUN corepack prepare pnpm@10.33.0 --activate \
    && pnpm install --frozen-lockfile

FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY next-env.d.ts tsconfig.json ./
COPY postcss.config.mjs ./
COPY next.config.ts ./
COPY package.json pnpm-lock.yaml .npmrc ./
COPY public ./public
COPY app ./app

ARG NEXT_PUBLIC_API_URL=http://localhost:4001
ARG NEXT_PUBLIC_API_NODE_URL=http://localhost:4002
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_NODE_URL=$NEXT_PUBLIC_API_NODE_URL

RUN corepack prepare pnpm@10.33.0 --activate \
    && pnpm run build

FROM base AS runner
ENV NODE_ENV=production
USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends dumb-init \
  && rm -rf /var/lib/apt/lists/*
RUN groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs nextjs
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs

ARG PORT=3000
ENV PORT=${PORT}
EXPOSE ${PORT}
ENV HOSTNAME=0.0.0.0

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server.js"]
