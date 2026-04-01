#!/usr/bin/env bash
# Bootstrap + run PostgreSQL (CloudNativePG-style image for Docker Compose).
# Mimics library/postgres env: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB.
set -euo pipefail

if [[ "$(id -u)" == "0" ]]; then
	mkdir -p "${PGDATA:-/var/lib/postgresql/data}"
	chown -R postgres:postgres /var/lib/postgresql
	chmod 700 "${PGDATA:-/var/lib/postgresql/data}" || true
	exec runuser -u postgres -- "$0" "$@"
fi

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
export PGDATA

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-$POSTGRES_USER}"
: "${POSTGRES_PASSWORD?"POSTGRES_PASSWORD must be set"}"

if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
	PWFILE="$(mktemp)"
	chmod 600 "$PWFILE"
	printf '%s\n' "$POSTGRES_PASSWORD" >"$PWFILE"
	initdb -D "$PGDATA" \
		--username="$POSTGRES_USER" \
		--pwfile="$PWFILE" \
		--auth-host=scram-sha-256 \
		--auth-local=trust
	rm -f "$PWFILE"

	{
		echo ""
		echo "# myproject storage image"
		echo "listen_addresses = '*'"
	} >>"$PGDATA/postgresql.conf"

	echo "host all all all scram-sha-256" >>"$PGDATA/pg_hba.conf"

	pg_ctl -D "$PGDATA" -w -o "-c listen_addresses=*" start

	if [[ "$POSTGRES_DB" != "postgres" ]]; then
		DB_EXISTS="$(psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'")"
		if [[ "$DB_EXISTS" != "1" ]]; then
			psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
				-c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
		fi
	fi

	pg_ctl -D "$PGDATA" -m fast -w stop
fi

exec postgres -D "$PGDATA"
