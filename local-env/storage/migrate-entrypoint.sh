#!/bin/sh
set -eu

if [ -z "${DATABASE_URL:-}" ]; then
	echo "DATABASE_URL is required" >&2
	exit 1
fi

if [ -n "${MIGRATION_FORCE_VERSION:-}" ]; then
	exec migrate -path /migrations -database "$DATABASE_URL" force "$MIGRATION_FORCE_VERSION"
fi

exec migrate -path /migrations -database "$DATABASE_URL" up ${MIGRATION_VERSION:+"$MIGRATION_VERSION"}
