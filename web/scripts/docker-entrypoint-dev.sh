#!/bin/sh
# Dev container: bind-mounted source; node_modules and .next live on named volumes.
set -eu
cd /app
corepack prepare pnpm@10.33.0 --activate

# If named volumes were created with root ownership, make sure Next/Turbopack can write
# lockfiles and cache under `.next` before dropping privileges.
if [ "$(id -u)" = "0" ]; then
  chown -R node:node /app/.next /app/.turbo 2>/dev/null || true
fi

if [ ! -d node_modules/next ]; then
  echo "web-dev: node_modules is empty — run the deps workflow (e.g. compose profile 'deps') to install, then restart web-dev." >&2
  exit 1
fi

if [ "$(id -u)" = "0" ]; then
  # Keep deps stable during web-dev execution; updates happen via the deps workflow.
  chmod -R a-w /app/node_modules 2>/dev/null || true
fi

if [ "$(id -u)" = "0" ] && command -v su >/dev/null 2>&1; then
  # Run the actual dev server as the unprivileged `node` user.
  set +e
  su -s /bin/sh node -c "pnpm run dev:docker"
  rc=$?
  set -e
  exit $rc
fi

exec pnpm run dev:docker
