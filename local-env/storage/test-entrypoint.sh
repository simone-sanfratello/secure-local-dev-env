#!/bin/sh
# Storage test image: migrations exist and (when DATABASE_URL is set) `migrate version` succeeds.
set -eu

if [ ! -d /migrations ]; then
  echo "storage-test: /migrations missing" >&2
  exit 1
fi

# golang-migrate names: *_up.{sql,sum} in some setups; this repo uses *.up.sql
# shellcheck disable=SC2012
_n="$(ls /migrations/*.up.sql 2>/dev/null | wc -l)"
if [ "$_n" -lt 1 ]; then
  echo "storage-test: no *.up.sql under /migrations" >&2
  exit 1
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "storage-test: ok (${_n} up migration(s); set DATABASE_URL for DB check)" >&2
  exit 0
fi

exec migrate -path /migrations -database "$DATABASE_URL" version
