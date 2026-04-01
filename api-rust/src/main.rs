use std::sync::Arc;

use api_rust::{app, config::AppConfig};
use tracing::error;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_ansi(false)
        .with_env_filter(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info,tower_http=info".into()),
        )
        .json()
        .flatten_event(true)
        .with_current_span(false)
        .with_span_list(false)
        .init();

    let config = match AppConfig::from_env() {
        Ok(cfg) => cfg,
        Err(err) => {
            error!("configuration error: {err}");
            std::process::exit(1);
        }
    };

    let redis_client = match redis::Client::open(config.redis_url.clone()) {
        Ok(client) => client,
        Err(err) => {
            error!("redis client initialization failed: {err}");
            std::process::exit(1);
        }
    };

    let state = app::AppState {
        config: Arc::new(config),
        redis_client,
        http_client: reqwest::Client::new(),
    };

    app::run_server(state).await;
}
