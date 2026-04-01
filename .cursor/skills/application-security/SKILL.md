---
name: application-security
description: Reviews and implements security for the Next.js frontend, Rust API, Postgres, Redis, and Docker. Use when adding auth, handling user data, configuring headers, dependencies, secrets, enforcing Node 24.14.1 and pnpm-only workflows, or responding to audit or vulnerability reports.
---

# Application security

## Tooling baseline (this repo)

- **Node.js `24.14.1`** and **pnpm `10.33.0`** are pinned; **`engine-strict=true`** in **`.npmrc`**—do not suggest `npm install`, `yarn`, or relaxed `engines` ranges without an intentional Node/pnpm upgrade across `.node-version`, Docker, and CI.
- Use **`pnpm`** in all install/add/CI examples for **`web/`**, **`test/`**, and repo root.
- **Local dev** (supply-chain / resource bounds): prefer **`just dev`** (full Docker stack with profile **`dev`**: infra + api-rust-dev + api-node-dev + web-dev, all sandboxed with hot reload)—not bare **`pnpm dev`** or **`cargo watch`** on the host for routine work. See **`security`** project rule **Local development (sandbox)**.

## Quick triage

| Change | Check |
|--------|--------|
| New dependency | Exact version; `pnpm audit`; note transitive risk; postinstall risk |
| New API route | Authz, validation, rate limits, error leakage |
| New client form | Server validation; no secrets in props/env exposed to browser |
| Session / JWT | Expiry, rotation, storage, CSRF if cookies |
| User-generated HTML | Sanitize; CSP; avoid raw `dangerouslySetInnerHTML` |

## Frontend (`web/`)

1. Confirm **`NEXT_PUBLIC_*`** exposes only non-secret config.
2. Review **links** (`target="_blank"`) for `rel` attributes where needed.
3. Align with Biome **a11y** and **security** rules; add **CSP** incrementally (start report-only if needed).

## Backend (`api-node/`, `api-rust`)

1. **Validate** DTOs at the boundary; map errors to safe client messages.
2. **SQL**: only prepared/parameterized queries; migrations reviewed for destructive ops.
3. **Redis**: no sensitive data without encryption/TTL policy when applicable.

## Workflow: dependency bump

1. Read changelog / advisory for the package.
2. Update **one** logical bump (or minimal set); run tests, **`pnpm audit`**, and **`pnpm run lint`** (or package equivalents).
3. If breaking, document in `docs/` or ADR when behavior or threat model changes.

## Workflow: Node or pnpm version bump

1. Update **`.node-version`**, root / `web` / `test` **`engines`**, **`packageManager`**, **`web/Dockerfile`** base image, and any CI matrix—same version everywhere.
2. Run **`pnpm install`** at root, **`web/`**, and **`test/`**; commit updated lockfiles.
3. Note security support dates for the new Node line in `docs/` if policy requires it.

## Workflow: incident or CVE

1. Reproduce scope (which service, versions).
2. Patch version or mitigate (WAF, feature flag).
3. Rotate credentials if exposure suspected; record timeline in runbook.
