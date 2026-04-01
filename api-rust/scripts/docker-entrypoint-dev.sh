#!/bin/sh
# Dev container: bind-mounted source; cargo watch for hot reload.
set -eu
cd /app

# Named volumes (target dir, cargo registry) may have been created as root by a previous image/version.
# Fix once on container boot, then drop privileges to the unprivileged dev user.
if [ "$(id -u)" = "0" ]; then
  mkdir -p /app/target /usr/local/cargo/registry
  chown -R app:app /app /usr/local/cargo/registry
fi

# Bump mtimes on mounted sources so the first cargo run rebuilds this crate (image may only warm deps).
gosu app:app sh -eu -c 'find src -type f -exec touch {} +'
echo "Starting cargo watch in /app..."
exec gosu app:app cargo watch -x run --why
