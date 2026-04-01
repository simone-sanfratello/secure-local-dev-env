#!/bin/sh
# Dev container: bind-mounted source; cargo watch for hot reload.
set -eu
cd /app

# `target/` is on the bind-mounted host tree; only the cargo registry uses a named volume (may be root-owned).
if [ "$(id -u)" = "0" ]; then
  mkdir -p /usr/local/cargo/registry
  chown -R app:app /usr/local/cargo/registry
fi

# Bump mtimes on mounted sources so the first cargo run rebuilds this crate (image may only warm deps).
gosu app:app sh -eu -c 'find src -type f -exec touch {} +'
echo "Starting cargo watch in /app..."
exec gosu app:app cargo watch -x run --why
