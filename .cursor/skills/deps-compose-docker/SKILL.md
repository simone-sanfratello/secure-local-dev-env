---
name: deps-compose-docker
description: >-
  Adds, removes, or updates dependencies using Docker Compose profile `deps` (web-deps, api-node-deps, api-rust-deps)
  with bind-mounted lockfiles and shared pnpm store. Use when changing package.json/Cargo.toml, refreshing lockfiles,
  or advising install/add/remove/update commands—prefer this over host `pnpm`/`cargo` for dependency mutations.
---

# Dependency changes via Docker Compose (`deps` profile)

## Why this workflow

- Toolchains match the repo pins (**Node.js 24.14.1**, **pnpm 10.33.0**, **Rust** image aligned with **`api-rust/Dockerfile.dev`**).
- Package manager runs in a container with resource limits; manifests and lockfiles update on the **host** via bind mounts.
- Services use **filtered DNS** (`dns: [172.28.0.53]`); only registry hosts allowed in **`local-env/network/Corefile`** resolve. If a new registry is needed, extend the Corefile whitelist first.

## Entry points (repo root)

| Stack | `just` recipe | Compose service |
|-------|---------------|-----------------|
| **web** | `just web-deps <cmd> [args...]` | `web-deps` |
| **api-node** | `just api-node-deps <cmd> [args...]` | `api-node-deps` |
| **api-rust** | `just api-rust-deps <cmd> [args...]` | `api-rust-deps` |

`just` wraps:

```bash
docker compose --profile deps run --rm --build --user "$(id -u):$(id -g)" <service> <cmd> [args...]
```

**pnpm** recipes also run **`local-env/deps/ensure-pnpm-store-writable.sh`** so **`/.pnpm-store`** (bind-mounted from repo **`/.pnpm-store`**) is writable for your UID.

## pnpm (`web-deps`, `api-node-deps`)

- **Image** entrypoint: **`local-env/deps/pnpm-entrypoint.sh`** (whitelisted verbs only).
- **Commands**: `install` · `add` · `remove` / `rm` · `update` · `help`
- Compose sets **`CI=true`** so non-interactive **`install`** works without a TTY. **`add` / `remove` / `update`** run with **`CI` unset** so **`pnpm-lock.yaml`** can be updated on the bind-mounted tree.
- **Shared store**: **`web/.npmrc`** and **`api-node/.npmrc`** use **`store-dir=../.pnpm-store`**; commit **`pnpm-lock.yaml`** after changes; run **`pnpm audit`** when appropriate (see **`supply-chain-security`** / **`security`** rule).

Examples:

```bash
just web-deps add zod
just web-deps remove some-package
just web-deps install --frozen-lockfile
just api-node-deps add -D @types/node
```

## Cargo (`api-rust-deps`)

- **Image** entrypoint: **`local-env/deps/cargo-entrypoint.sh`** (whitelisted verbs only).
- **Commands**: `add` · `remove` / `rm` · `update` · `install` (for **`cargo install`** binaries—often ephemeral unless **`CARGO_HOME`** is mounted).
- Commit **`api-rust/Cargo.lock`** after changes.

Examples:

```bash
just api-rust-deps add serde --features derive
just api-rust-deps rm serde
```

## After dependency changes

1. **Commit** the updated lockfile(s).
2. **Rebuild or restart** dev containers if they cache **`node_modules`** / **`target`** (e.g. restart **`web-dev`**, **`api-node-dev`**, or **`api-rust-dev`**).
3. If CI uses **`pnpm install --frozen-lockfile`**, ensure the lockfile was produced by this workflow (or equivalent) so CI stays green.

## Do not

- Run arbitrary shells inside deps containers—the entrypoints only allow the listed commands.
- Use **`npm`** or **`yarn`** for this repo (see **`security`** rule).
- Assume new external hosts work without checking **CoreDNS** allowlists for registry/API egress.
