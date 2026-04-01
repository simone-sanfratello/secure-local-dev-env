---
name: database-postgres
description: >-
  Models PostgreSQL schemas, indexes, and constraints for performance and integrity;
  writes golang-migrate SQL in storage/migrations with safe upgrade and rollback
  paths. Use when designing tables, relationships, query patterns, migrations, index
  tuning, or reviewing DDL for the myproject stack.
---

# Database (PostgreSQL) — DBA workflow

## When editing schema

1. **Read access paths** — List the queries the Rust service will run (filters, joins, sorts, limits). Design keys and indexes for those paths, not hypothetical ones.
2. **Choose keys** — Surrogate keys (`bigint`, `uuid`) vs natural keys: pick one primary pattern per table cluster and stay consistent with existing migrations.
3. **Relations** — Every association should have explicit FKs unless a documented exception. Set `ON DELETE` / `ON UPDATE` explicitly (`RESTRICT`, `CASCADE`, `SET NULL`) so behavior is reviewable.
4. **Constrain early** — `CHECK`, `NOT NULL`, `UNIQUE`, and enum/check constraints that mirror domain rules reduce bugs cheaper than app-only validation.

## Indexing checklist

- [ ] FK columns used in joins are indexed when the parent is large or the child is queried by parent id.
- [ ] Common `WHERE` predicates have supporting indexes (leading columns match combined filters).
- [ ] `ORDER BY` / cursor pagination columns are covered where needed (often composite with filter columns).
- [ ] No redundant indexes (same leading prefix as another unless serving distinct important queries).
- [ ] Verify with **`EXPLAIN (ANALYZE, BUFFERS)`** on representative queries after significant DDL (in a staging copy with realistic stats).

## Migration discipline (golang-migrate)

- **Naming**: `NNN_short_description.up.sql` and matching `.down.sql` in `storage/migrations/`. **Increment** `NNN`; do not reuse numbers.
- **Immutability**: Treat applied migration files as append-only history. Fixes ship as **new** migrations.
- **Safety**: Prefer additive steps: new nullable column → backfill → set `NOT NULL` with default in a later step if needed. Dropping columns is last in a expand–contract sequence.
- **`down`**: Must undo `up` in reverse order. If data loss is unavoidable on rollback, make that obvious in migration comments and team process.
- **Locks**: Large table rewrites and non-concurrent index builds block writes; plan `CONCURRENTLY` and transaction boundaries per Postgres docs for production scale.

## Operational notes

- Align timezone and timestamp types with API (usually UTC + `timestamptz`).
- For secrets and PII: follow **`security`** and **`application-security`** — DDL should not embed secrets; avoid logging row data in migration runners.

## Coordination

- After schema changes, **api-rust** and **api-node** code must use parameterized SQL against the new shape; update any integration tests that assume old columns (see **`backend-rust-api`** skill and **`api-node`** rule).
