---
name: backend-rust-api
description: Designs and implements the Rust HTTP API in api-rust/ (Axum-style) with PostgreSQL. Use when adding routes, handlers, middleware, auth, validation, migrations, or database access for the B2C SaaS. For the Node sibling service, use the api-node project rule.
---

# Rust API (`api-rust/`)

## Principles

- Thin handlers: extract → validate DTO → call service → map errors to HTTP.
- Stable JSON error shape: `{ "error": { "code", "message" } }` (adjust once, reuse everywhere).
- Auth: session/JWT as chosen; never trust client-only checks for authorization.

## Database (PostgreSQL)

- Access only through the service layer (no direct DB from `web/`).
- Schema changes: SQL migrations in **`storage/migrations/`**; follow **`database`** rule and **`database-postgres`** skill (modeling, indexes, up/down practice).
- Local dev: document how to run Postgres (e.g. Docker Compose) and apply migrations.

## Workflow

1. Define or extend OpenAPI / types if the project uses them.
2. Add a **Postgres migration** if schema changes; run tests locally against a migrated DB.
3. Expose only what the web app needs; version breaking changes (`/api/v2`).

## Checklist for new endpoints

- [ ] Input validated at boundary
- [ ] Correct status codes (400 vs 401 vs 403 vs 404 vs 409 vs 422)
- [ ] Tests for happy path + one failure mode
