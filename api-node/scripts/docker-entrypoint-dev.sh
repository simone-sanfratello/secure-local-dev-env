#!/bin/sh
set -eu

cd /app
corepack prepare pnpm@10.33.0 --activate

if [ ! -d node_modules ]; then
  echo "api-node-dev: node_modules missing or stale — run \`just api-node-deps install --frozen-lockfile\` (or \`add <pkg>\`) on the host tree, then restart this service." >&2
  exit 1
fi

exec pnpm run dev
