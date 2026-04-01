# Secure local development environment

This repository is the companion code for the article **[Securing Local Development Environment Against Dependency Supply Chain Attacks](https://simone-sanfratello.netlify.app/articles/securing-local-development-environment-against-dependency-supply-chain-attacks/)**.


---

Monorepo for a small full-stack app: a **Next.js** frontend (`web/`), a **Rust** HTTP API (`api-rust/`), a **Node** HTTP API (`api-node/`), **PostgreSQL** migrations (`storage/`), and **Docker Compose** wiring with filtered DNS, resource limits, and sandboxed containers.

Day-to-day work stays inside Docker (hot reload on bind mounts). [just](https://github.com/casey/just) wraps Compose so you do not have to remember profiles and long `docker compose` lines.

## Repository layout

| Path | Role |
|------|------|
| `web/` | Next.js (TypeScript), Turbopack dev, Biome, pnpm |
| `api-rust/` | Axum API, PostgreSQL, Redis |
| `api-node/` | Fastify API, TypeScript (`tsc` + `node --watch`), PostgreSQL, pnpm |
| `storage/` | Postgres image + golang-migrate SQL migrations |
| `local-env/` | Shared scripts (secrets helper, pnpm store fix, network Corefile, notify sidecar) |
| `docker-compose.yml` | Services, profiles (`dev`, `test`, `deps`, `full`), volumes, DNS |
| `justfile` | Standard commands (`just dev`, `just deps`, …) |

Node services pin **Node.js 24.14.1** and **pnpm 10.33.0** (see each package’s `package.json`). Rust tooling is pinned in `api-rust/` via the deps image.

## Prerequisites

- **Docker** and **Docker Compose** (Compose v2 plugin is fine).
- **[just](https://github.com/casey/just)** installed on the host (`just` is only the task runner; builds run in containers).

You do **not** need Node, pnpm, or Rust on the host for the recommended workflow—only for optional editor integrations.

## First-time setup

1. **Secrets for local Compose**  
   APIs expect `OPENAI_API_KEY` in gitignored env files. Generate them interactively:

   ```bash
   just secrets
   ```

   Or non-interactively:

   ```bash
   export OPENAI_API_KEY='sk-...'
   just secrets
   ```

   This writes secret-only `api-rust/.env` and `api-node/.env` (mode `600`). Do not commit them.

2. **Install dependencies (all services)**  
   `just deps` runs installs inside Compose’s **`deps`** profile: pnpm for `web/` and `api-node/` (refreshing lockfiles), and `cargo` for `api-rust/`. Commit updated `pnpm-lock.yaml` / `Cargo.lock` when they change.

3. **Start the stack**  
   ```bash
   just dev
   ```

## Using `just`

Run **`just`** with no arguments to print the recipe list (same as `just --list`). Recipes are defined in the repo-root `justfile` and almost always `cd` to the repo root for you.

### Core workflows

| Command | What it does |
|---------|----------------|
| `just dev` | Compose **profile `dev`**: Postgres, Redis, migrations, DNS sidecars, **api-rust-dev**, **api-node-dev**, **web-dev** with bind mounts and hot reload. Builds images if needed. |
| `just deps` | Runs `just web-deps install --no-frozen-lockfile`, `just api-node-deps install --no-frozen-lockfile`, and `just api-rust-deps install`—one-shot dependency bootstrap or refresh after clone. |
| `just test` | Compose **profile `test`**: runs **web-test**, **api-node-test**, **api-rust-test**, **storage-test** (lint/typecheck/tests/smoke as configured per Dockerfile). |
| `just secrets` | Writes `OPENAI_API_KEY` into the API `.env` files (see above). |
| `just clean` | `docker compose down -v` across **dev**, **test**, **deps**, and **full** profiles—**deletes DB volumes and other named volumes**. |
| `just fix` | `docker compose up --build --force-recreate` with **no** Compose profile—brings up **unprofiled** services only (CoreDNS, Postgres, migration job, Redis). App containers use profiles (`dev`, `full`, …); use `just dev` or `--profile full` when you need those. |

### Per-service development (`dev` profile)

These start **one** named Compose service, but **dependencies still come up** (for example, `web-dev` pulls up **api-rust-dev**, **api-node-dev**, Postgres, Redis, migrations, and DNS helpers because of `depends_on`). Use them when you want a shorter command or to attach logs to a single service name:

- `just web-dev` — Next.js dev (Turbopack) on port 3001.
- `just api-rust-dev` — Rust API with `cargo watch` on 4001.
- `just api-node-dev` — Node API with watch mode on 4002.

For the usual “whole stack, mixed logs” workflow, prefer **`just dev`** (same profile, all app services defined together).

### Per-service tests

- `just web-test`
- `just api-node-test`
- `just api-rust-test`

### Changing dependencies (recommended: do not use host `pnpm` / `cargo` for installs)

The **`deps`** profile bind-mounts each app directory so manifests, lockfiles, `node_modules`, and `target/` stay on your disk.

Pass **pnpm or cargo arguments after the recipe name**:

```bash
# Web (Next.js)
just web-deps add zod
just web-deps rm some-package
just web-deps install --no-frozen-lockfile

# api-node
just api-node-deps add -D @types/node
just api-node-deps install --no-frozen-lockfile

# api-rust
just api-rust-deps add serde --features derive
just api-rust-deps rm serde
```

`just deps` is a convenience shortcut for initial `install` across all three; for day-to-day edits, call **`web-deps`**, **`api-node-deps`**, or **`api-rust-deps`** with the verbs you need.

**Shared pnpm store:** `web/` and `api-node/` use a repo-level **`.pnpm-store`** (gitignored). Recipes that touch pnpm ensure that directory is writable from your user (avoids root-owned directories created by Docker).

## Local URLs and ports (after `just dev`)

| Service | URL / port |
|---------|-------------|
| Web | http://localhost:3001 |
| api-rust | http://localhost:4001 |
| api-node | http://localhost:4002 |
| PostgreSQL | `localhost:5432` (user/password/db: `myproject` / `myproject` / `myproject`) |
| Redis | `localhost:6379` |

Health checks: Rust API `/health`, Node API `/health`; versioned JSON under `/api/v1/...` per service.

## Compose profiles (reference)

- **`dev`** — Local development with hot reload (`just dev`, single-service `*-dev` recipes).
- **`test`** — Ephemeral test runners (`just test`, `just *-test`).
- **`deps`** — One-off dependency containers (`just web-deps`, etc.).
- **`full`** — Production-style images for **web**, **api-rust**, **api-node** (not wired in `just`; run `docker compose --profile full up --build` if you need that mode).

Dev/test/deps traffic uses a filtered resolver (`dns-filter`); allowlisted egress is configured in `local-env/network/Corefile`. A **`notify`** sidecar can surface DNS denials on Linux desktops when session D-Bus is mounted—see compose comments and env vars if you tune it.
