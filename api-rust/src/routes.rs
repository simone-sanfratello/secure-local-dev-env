use std::time::Duration;

use axum::{Json, extract::State, http::StatusCode, response::IntoResponse};
use chrono::{DateTime, Utc};
use rand::{RngExt, rng};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::info;
use uuid::Uuid;

use crate::{
    app::{ApiError, AppState},
    openai::{call_openai, extract_openai_text},
};

#[derive(Debug, Deserialize)]
pub struct CreateItemRequest {
    prompt: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StoredItem {
    id: String,
    prompt: String,
    openai_text: String,
    openai_raw: Value,
    created_at: DateTime<Utc>,
}

pub async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

pub async fn root(State(state): State<AppState>) -> impl IntoResponse {
    Json(serde_json::json!({
        "service": state.config.app_name,
    }))
}

/// GET — tries HTTPS to a host outside the default CoreDNS allowlist (e.g. `facebook.com`).
const BLOCKED_PROBE_URL: [&str; 5] = [
    "https://www.facebook.com/",
    "https://www.google.com/",
    "https://www.amazon.com/",
    "https://www.apple.com/",
    "https://www.microsoft.com/",
];

pub async fn blocked_probe(State(state): State<AppState>) -> impl IntoResponse {
    let index = rng().random_range(0..BLOCKED_PROBE_URL.len());
    let url = BLOCKED_PROBE_URL[index];
    info!("blocked probe, calling {}", url);
    let result = state
        .http_client
        .get(url)
        .timeout(Duration::from_secs(10))
        .send()
        .await;

    match result {
        Ok(resp) => {
            let status = resp.status().as_u16();
            Json(serde_json::json!({
                "target": BLOCKED_PROBE_URL,
                "outcome": "reached",
                "http_status": status,
                "note": "TLS/HTTP succeeded; this host was reachable from the API container ! BUT SHOULD NOT BE !",
            }))
        }
        Err(e) => {
            let detail = e.to_string();
            let lower = detail.to_lowercase();
            let likely_dns = lower.contains("dns")
                || lower.contains("lookup")
                || lower.contains("resolve")
                || lower.contains("nxdomain")
                || lower.contains("name or service not known")
                || lower.contains("failed to lookup");
            Json(serde_json::json!({
                "target": BLOCKED_PROBE_URL,
                "outcome": if likely_dns { "failed_dns_or_block" } else { "failed_other" },
                "error": detail
            }))
        }
    }
}

pub async fn list_items(State(state): State<AppState>) -> Result<Json<Vec<StoredItem>>, ApiError> {
    let mut conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|err| ApiError::Internal(format!("failed connecting to redis: {err}")))?;

    let values: Vec<String> = conn
        .lrange("items:all", 0, -1)
        .await
        .map_err(|err| ApiError::Internal(format!("failed reading redis list: {err}")))?;

    let items = values
        .into_iter()
        .filter_map(|raw| serde_json::from_str::<StoredItem>(&raw).ok())
        .collect::<Vec<_>>();

    Ok(Json(items))
}

pub async fn create_item(
    State(state): State<AppState>,
    Json(payload): Json<CreateItemRequest>,
) -> Result<(StatusCode, Json<StoredItem>), ApiError> {
    if payload.prompt.trim().is_empty() {
        return Err(ApiError::BadRequest("prompt is required".to_owned()));
    }

    let openai_raw = call_openai(&state.http_client, &state.config, &payload.prompt).await?;
    let openai_text = extract_openai_text(&openai_raw);
    let item = StoredItem {
        id: Uuid::new_v4().to_string(),
        prompt: payload.prompt,
        openai_text,
        openai_raw,
        created_at: Utc::now(),
    };

    let serialized = serde_json::to_string(&item)
        .map_err(|err| ApiError::Internal(format!("failed serializing item: {err}")))?;

    let mut conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|err| ApiError::Internal(format!("failed connecting to redis: {err}")))?;

    conn.rpush::<_, _, i64>("items:all", serialized)
        .await
        .map_err(|err| ApiError::Internal(format!("failed writing item to redis: {err}")))?;

    Ok((StatusCode::CREATED, Json(item)))
}
