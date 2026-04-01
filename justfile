# https://github.com/casey/just — run `just` to list recipes
set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
pnpm_activate := "corepack prepare pnpm@10.33.0 --activate"

default:
    @just --list

# Write .env files that contain only secrets (OPENAI_API_KEY) for Compose + api-rust + api-node.
# Prompts for the key if OPENAI_API_KEY is unset; otherwise export OPENAI_API_KEY=... or pipe one line.
secrets:
    bash local-env/write-app-secret-envs.sh

# Stop Compose project and remove volumes (destructive: DB data, named volumes).
reset:
    cd "{{justfile_directory()}}" && docker compose down -v

fix:
    cd "{{justfile_directory()}}" && docker compose up --build --force-recreate --remove-orphans

dev:
    bash "{{justfile_directory()}}/local-env/deps/ensure-pnpm-store-writable.sh" "{{justfile_directory()}}"
    cd "{{justfile_directory()}}" && docker compose --profile dev up --build

test:
    cd "{{justfile_directory()}}" && docker compose --profile test up --build

# --- web (Next.js) ---

# Dependency changes via Compose (`deps` profile): pinned Node + pnpm; bind-mounts ./web. `add`/`rm`/`update` refresh `web/pnpm-lock.yaml` (commit it). 
# Example: `just web-deps add zod` `just web-deps rm zod` `just web-deps install --no-frozen-lockfile`
web-deps *args:
    bash "{{justfile_directory()}}/local-env/deps/ensure-pnpm-store-writable.sh" "{{justfile_directory()}}"
    cd "{{justfile_directory()}}" && docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" web-deps {{args}}

# Next dev sandboxed in Docker with hot reload (bind-mount web/ + volumes for node_modules/.next)
web-dev:
    bash "{{justfile_directory()}}/local-env/deps/ensure-pnpm-store-writable.sh" "{{justfile_directory()}}"
    cd "{{justfile_directory()}}" && docker compose --profile dev up --build web-dev

web-test:
    cd "{{justfile_directory()}}" && docker compose --profile test run --rm --build web-test

# --- api-rust ---

# Dependency changes via Compose (`deps` profile): pinned Rust; bind-mounts ./api-rust. 
# Example: `just api-rust-deps add serde --features derive` `just api-rust-deps rm serde`
api-rust-deps *args:
    cd "{{justfile_directory()}}" && docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" api-rust-deps {{args}}

# Rust API dev sandboxed in Docker with hot reload (bind-mount api-rust/ + volumes for target/ and cargo registry)
api-rust-dev:
    docker compose --profile dev up --build api-rust-dev

api-rust-test:
    cd "{{justfile_directory()}}" && docker compose --profile test run --rm --build api-rust-test

# --- api-node ---

# Dependency changes via Compose (`deps` profile): pinned Node + pnpm; bind-mounts ./api-node. 
# Example: `just api-node-deps add -D @types/node` `just api-node-deps rm @types/node` `just api-node-deps install --no-frozen-lockfile`
api-node-deps *args:
    bash "{{justfile_directory()}}/local-env/deps/ensure-pnpm-store-writable.sh" "{{justfile_directory()}}"
    cd "{{justfile_directory()}}" && docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" api-node-deps {{args}}

# api-node dev sandboxed in Docker with hot reload (bind-mount api-node/ + node_modules volume)
api-node-dev:
    bash "{{justfile_directory()}}/local-env/deps/ensure-pnpm-store-writable.sh" "{{justfile_directory()}}"
    cd "{{justfile_directory()}}" && docker compose --profile dev up --build api-node-dev

api-node-test:
    cd "{{justfile_directory()}}" && docker compose --profile test run --rm --build api-node-test

