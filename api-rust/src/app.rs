use std::sync::Arc;

use axum::{
    Json, Router,
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
};
use tower_http::{
    cors::{Any, CorsLayer},
    trace::TraceLayer,
};
use tracing::{info, warn};

use crate::{config::AppConfig, routes};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<AppConfig>,
    pub redis_client: redis::Client,
    pub http_client: reqwest::Client,
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("internal error: {0}")]
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };

        let payload = serde_json::json!({
            "error": {
                "message": message
            }
        });

        (status, Json(payload)).into_response()
    }
}

pub fn build_router(state: AppState) -> Router {
    let health_path = state.config.http_health_path.clone();
    let items_path = format!("{}/items", state.config.http_api_v1_prefix);
    let blocked_probe_path = format!("{}/blocked-probe", state.config.http_api_v1_prefix);
    let cors_origin = match state.config.cors_allowed_origin.parse::<HeaderValue>() {
        Ok(origin) => origin,
        Err(_) => {
            warn!(
                cors_allowed_origin = %state.config.cors_allowed_origin,
                "Invalid CORS_ALLOWED_ORIGIN; falling back to http://localhost:3001"
            );
            HeaderValue::from_static("http://localhost:3001")
        }
    };

    let cors = CorsLayer::new()
        .allow_origin(cors_origin)
        .allow_methods([Method::GET, Method::POST, Method::OPTIONS])
        .allow_headers(Any);

    Router::new()
        .route("/", get(routes::root))
        .route(&health_path, get(routes::health))
        .route(
            &items_path,
            get(routes::list_items).post(routes::create_item),
        )
        .route(&blocked_probe_path, get(routes::blocked_probe))
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state)
}

pub async fn run_server(state: AppState) {
    let app = build_router(state.clone());
    let bind_address = format!("0.0.0.0:{}", state.config.app_port);
    let listener = tokio::net::TcpListener::bind(&bind_address)
        .await
        .expect("failed to bind TCP listener");

    info!(
        app = %state.config.app_name,
        address = %bind_address,
        "Starting API server"
    );

    axum::serve(listener, app)
        .await
        .expect("Failed running axum server");
}
