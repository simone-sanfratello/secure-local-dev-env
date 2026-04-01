# Rust 1.94.1 (2026-03-25)
FROM rust:1.94.1-bookworm@sha256:fdb91abf3cb33f1ebc84a76461d2472fd8cf606df69c181050fa7474bade2895 AS builder
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release

# Debian 12.13 (bookworm)
FROM debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates dumb-init libssl3 wget \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 api \
    && useradd --system --uid 10001 --gid api --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin api

COPY --from=builder /app/target/release/api-rust /usr/local/bin/api-rust
RUN chmod 0555 /usr/local/bin/api-rust

USER api

ARG APP_PORT=4000
ENV APP_PORT=${APP_PORT}
EXPOSE ${APP_PORT}
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["api-rust"]
