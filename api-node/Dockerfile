FROM node:24.14.1-bookworm-slim@sha256:06e5c9f86bfa0aaa7163cf37a5eaa8805f16b9acb48e3f85645b09d459fc2a9f AS base
WORKDIR /app
RUN corepack enable \
  && apt-get update \
  && apt-get install -y --no-install-recommends dumb-init \
  && rm -rf /var/lib/apt/lists/*

FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN corepack prepare pnpm@10.33.0 --activate \
  && pnpm install --frozen-lockfile

FROM deps AS builder
COPY tsconfig.json ./
COPY src ./src
RUN pnpm run build

FROM base AS runner
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
RUN corepack prepare pnpm@10.33.0 --activate \
  && pnpm install --frozen-lockfile --prod
COPY --from=builder /app/dist ./dist

RUN chown -R node:node /app
USER node
ARG APP_PORT=4002
ENV APP_PORT=${APP_PORT}
EXPOSE ${APP_PORT}

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "dist/main.js"]
