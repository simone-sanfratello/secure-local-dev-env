# syntax=docker/dockerfile:1
# PostgreSQL 18 (CloudNativePG base) with custom bootstrap for Docker Compose (POSTGRES_* env).
# Without this entrypoint, use the base image tag directly.
#
# Build: docker build -t myproject-postgres:18.1 -f storage/Dockerfile .

# PostgreSQL 18.1 (Debian 18.1-1.pgdg13+2)
FROM ghcr.io/cloudnative-pg/postgresql:18.1-system-trixie@sha256:51bc94428be3df3e234447278e33803544a93d27a57a4b6af737f218d6472d12

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends dumb-init \
  && rm -rf /var/lib/apt/lists/*

COPY local-env/storage/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Uncomment to install PGDG packages (major must match the image, e.g. 18):
# RUN apt-get update \
#   && apt-get install -y --no-install-recommends postgresql-18-pgvector \
#   && apt-get purge -y --auto-remove \
#   && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/docker-entrypoint.sh"]
