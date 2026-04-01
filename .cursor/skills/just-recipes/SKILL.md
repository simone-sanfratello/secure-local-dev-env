---
name: just-recipes
description: Runs and extends the repo root justfile for myproject. Use when the user wants task runners, Makefile-style commands, or to document how to build, lint, test, or deploy without memorizing pnpm/cargo paths.
---

# Just recipes

## Discover

```bash
just
```

## Common flows

| Goal | Recipe |
|------|--------|
| First clone (hooks + deps) | `just setup` |
| Full local stack (Docker profile `dev`: infra + api-rust-dev + api-node-dev + web-dev) | `just dev` |
| Next dev in Docker (bind-mount for hot reload) | `just web-dev` |
| Rust API dev in Docker (cargo watch, bind-mount for hot reload) | `just api-rust-dev` |
| Node API dev in Docker (bind-mount for hot reload) | `just api-node-dev` |
| Production build (web) | `just web-build` |
| Biome | `just web-lint` / `just web-format` |
| Rust API test (Docker) | `just api-rust-test` |
| Node API test (Docker) | `just api-node-test` |
| Docker stack | `just docker-up` |
| Conventional commit (interactive) | `just commit` (after `git add`) |

## Adding recipes

Edit **`justfile`** at the repo root; keep **`set shell`** with `bash -eu -o pipefail` for safer scripts. Use **`{{pnpm_activate}}`** for pnpm consistency.

## Prerequisites

Install **[just](https://github.com/casey/just)** (e.g. `cargo install just`, distro package, or upstream binary). Use **Node.js 24.14.1** (`.node-version`) for pnpm/Corepack parity with CI and Docker.
