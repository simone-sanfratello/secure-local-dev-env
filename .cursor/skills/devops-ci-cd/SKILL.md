---
name: devops-ci-cd
description: Sets up CI/CD, Docker, GitHub Actions, env separation, and deployment checks. Use when editing pipelines, Dockerfiles, compose files, the root justfile, or release process.
---

# DevOps

## Just (`justfile`)

- CI can invoke the same steps as local **`just`** recipes (e.g. `just web-test`, `just api-rust-test`, `just api-node-test`) to avoid drift.

## Commits

- **Conventional Commits** at repo root (commitlint + Husky); PR titles often mirror `type(scope): summary` for changelog-friendly history.

## Conventions

- **Docker Compose**: On this repo’s `docker-compose.yml`, all **`dev-internal`** app/storage/test/deps services use **`dns: [172.28.0.53]`** (CoreDNS allowlist in **`local-env/network/Corefile`**) except **`dns-filter`**. New Compose service keys must be added to the Corefile **`compose_services`** view. Profiles include **`notify`**, a sidecar that **polls** **`dns-filter`** logs and surfaces **`NXDOMAIN` / `SERVFAIL`** via **`notify-send`**: **immediate** intro (domain + service), then **batched follow-ups per service** after **`DNS_FILTER_NOTIFY_BATCH_SEC`** (default **5s**). It maps the **querier IP** to **Compose service** via **`NOTIFY_DOCKER_NETWORK`** + **`DNS_NOTIFY_IP_MAP_SEC`**. **`DNS_NOTIFY_GLOBAL_MAX`** / **`DNS_NOTIFY_GLOBAL_WINDOW_SEC`** cap total toasts per rolling window (default **10** / **300s**); first block also shows **one** cap-explanation toast (**not** counted). Desktop hosts need **`NOTIFY_DBUS`**, **`NOTIFY_DESKTOP_UID` / `NOTIFY_DESKTOP_GID`**, and (on Ubuntu) **`security_opt: apparmor=unconfined`** on **`notify`** so **AppArmor** does not block **D-Bus** from the container.
- Secrets in CI provider or runtime secret store only.
- Build artifacts reproducibly: lockfiles committed (`web/pnpm-lock.yaml`, `api-node/pnpm-lock.yaml`, `test/pnpm-lock.yaml`, `api-rust/Cargo.lock`).

## PR pipeline (target)

- Web: **Node.js 24.14.1** + **pnpm** `10.33.0` (Corepack); `pnpm install --frozen-lockfile`, `pnpm run lint` (Biome), `pnpm run build`, unit tests
- **api-node**: same Node/pnpm pin in **`api-node/`**; `pnpm install --frozen-lockfile`, `pnpm run lint` / `pnpm run build` / `pnpm run test` as defined in that package
- **api-rust**: `cargo clippy`, `cargo test` (from **`api-rust/`**)
- Optional: build container images on main/tags

## Production mindset

- Health/readiness endpoints for your runtime (include **PostgreSQL** readiness where applicable)
- Migrations gated and observable; rollback plan for schema changes
