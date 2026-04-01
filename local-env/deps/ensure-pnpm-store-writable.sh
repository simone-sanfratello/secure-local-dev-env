#!/usr/bin/env bash
# Ensure repo `.pnpm-store` exists and is writable for `docker compose run --user "$(id -u):$(id -g)"`.
# If Docker created the directory as root, fix ownership via a short Alpine container (no host sudo).
set -euo pipefail

repo_root="${1:-}"
if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
  echo "usage: ensure-pnpm-store-writable.sh <repo-root>" >&2
  exit 1
fi

dir="$repo_root/.pnpm-store"
mkdir -p "$dir"

if [ -w "$dir" ] && [ -x "$dir" ]; then
  exit 0
fi

# Root in a one-off container can chown the bind-mounted dir (fixes Docker-created root-owned `.pnpm-store`).
docker run --rm \
  -v "$dir:/s" \
  alpine:3.21@sha256:c3f8e73fdb79deaebaa2037150150191b9dcbfba68b4a46d70103204c53f4709 \
  chown -R "$(id -u):$(id -g)" /s

if [ ! -w "$dir" ]; then
  echo "error: still not writable: $dir" >&2
  exit 1
fi
