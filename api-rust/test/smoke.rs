//! In-process HTTP smoke: Axum router, no bound TCP port.

use std::sync::{Arc, Once};

use api_rust::{
    app::{AppState, build_router},
    config::AppConfig,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use tower::ServiceExt;

static ENV: Once = Once::new();

fn ensure_env_defaults() {
    ENV.call_once(|| unsafe {
        let set = |k: &str, v: &str| {
            if std::env::var_os(k).is_none() {
                std::env::set_var(k, v);
            }
        };
        set("CORS_ALLOWED_ORIGIN", "http://localhost:3001");
        set(
            "DATABASE_URL",
            "postgres://myproject:myproject@127.0.0.1:5432/myproject?sslmode=disable",
        );
        set("REDIS_URL", "redis://127.0.0.1:6379/0");
        set("OPENAI_MODEL", "gpt-4.1-mini");
        set("OPENAI_API_KEY", "local-test-key-not-used");
        set("HTTP_HEALTH_PATH", "/health");
        set("HTTP_API_V1_PREFIX", "/api/v1");
        if std::env::var_os("APP_PORT").is_none() {
            std::env::set_var("APP_PORT", "4001");
        }
    });
}

async fn router() -> axum::Router {
    ensure_env_defaults();
    let config = Arc::new(AppConfig::from_env().expect("config from env"));
    let redis_client = redis::Client::open(config.redis_url.as_str()).expect("redis URL");
    let state = AppState {
        config,
        redis_client,
        http_client: reqwest::Client::new(),
    };
    build_router(state)
}

#[tokio::test]
async fn health_returns_ok_json() {
    let app = router().await;
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .expect("health response");

    assert_eq!(response.status(), StatusCode::OK);
    let bytes = response
        .into_body()
        .collect()
        .await
        .expect("body")
        .to_bytes();
    let v: serde_json::Value = serde_json::from_slice(&bytes).expect("json");
    assert_eq!(v["status"], "ok");
}
