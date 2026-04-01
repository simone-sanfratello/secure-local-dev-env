#!/bin/sh
# Dependency helper for api-rust. Only whitelisted verbs run — no arbitrary shells.
# Expects /app bind-mounted to the Rust crate (Cargo.toml + Cargo.lock live here).
set -eu

usage() {
  cat <<'EOF' >&2
Usage: deps-entrypoint <command> [args...]

Commands:
  add           cargo add <crate|flags>...
  remove | rm   cargo remove <crate>...
  update        cargo update [crate|flags]...
  install       cargo install <binary-crate>...  (installs under the container's CARGO_HOME; mount it to keep binaries, or use only for ephemeral tooling)

Examples (from repo root):
  docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" api-rust-deps add serde --features derive

Or: just api-rust-deps add tokio --features full
EOF
}

cd /app

cmd="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$cmd" in
  add)
    exec cargo add "$@"
    ;;
  remove | rm)
    exec cargo remove "$@"
    ;;
  update)
    exec cargo update "$@"
    ;;
  install)
    exec cargo install "$@"
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
