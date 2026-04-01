#!/bin/sh
# Dependency helper for pnpm apps (web, api-node). Only whitelisted verbs run — no arbitrary shells.
# Expects /app bind-mounted to the app directory (package.json + pnpm-lock.yaml live here).
set -eu

usage() {
  cat <<'EOF' >&2
Usage: deps-entrypoint <command> [args...]

Commands:
  install       pnpm install — sync from lockfile (pass extra flags after command)
  add           pnpm add <packages>...
  remove | rm   pnpm remove <packages>...
  update        pnpm update [packages|flags]...

Examples (from repo root):
  docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" web-deps add -D typescript

Or: just web-deps add zod
EOF
}

cd /app
corepack prepare pnpm@10.33.0 --activate

cmd="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

# Compose sets CI=true for non-interactive `pnpm install` (no TTY). That also
# enables frozen-lockfile behavior on install paths. Mutating commands must
# update pnpm-lock.yaml, so run them without CI.
case "$cmd" in
  install)
    exec pnpm install "$@"
    ;;
  add)
    exec env -u CI pnpm add "$@"
    ;;
  remove | rm)
    exec env -u CI pnpm remove "$@"
    ;;
  update)
    exec env -u CI pnpm update "$@"
    ;;
  help | --help | -h | "")
    usage
    exit 0
    ;;
  *)
    echo "deps-entrypoint: unknown command: ${cmd:-<empty>}" >&2
    usage
    exit 1
    ;;
esac
