use serde_json::Value;

use crate::{app::ApiError, config::AppConfig};

pub async fn call_openai(
    http_client: &reqwest::Client,
    config: &AppConfig,
    prompt: &str,
) -> Result<Value, ApiError> {
    if config.openai_api_key.trim().is_empty() {
        return Err(ApiError::Internal(
            "OPENAI_API_KEY is not configured".to_owned(),
        ));
    }

    let url = format!(
        "{}/v1/responses",
        config.openai_base_url.trim_end_matches('/')
    );

    let payload = serde_json::json!({
        "model": config.openai_model,
        "input": prompt
    });

    let response = http_client
        .post(url)
        .bearer_auth(&config.openai_api_key)
        .json(&payload)
        .send()
        .await
        .map_err(|err| ApiError::Internal(format!("failed calling OpenAI: {err}")))?;

    let status = response.status();
    let body = response
        .text()
        .await
        .map_err(|err| ApiError::Internal(format!("failed reading OpenAI response: {err}")))?;

    if !status.is_success() {
        let upstream_message = truncate_for_error(&body, 512);
        return Err(ApiError::Internal(format!(
            "OpenAI request failed with status {status}: {upstream_message}"
        )));
    }

    serde_json::from_str::<Value>(&body)
        .map_err(|err| ApiError::Internal(format!("invalid OpenAI JSON response: {err}")))
}

pub fn extract_openai_text(openai_response: &Value) -> String {
    if let Some(text) = openai_response.get("output_text").and_then(Value::as_str) {
        return text.to_owned();
    }

    if let Some(text) = openai_response.get("output_text").and_then(Value::as_array) {
        let joined = text
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join("\n");
        if !joined.trim().is_empty() {
            return joined;
        }
    }

    if let Some(text) = openai_response
        .pointer("/output/0/content/0/text")
        .and_then(Value::as_str)
    {
        return text.to_owned();
    }

    if let Some(text) = openai_response
        .pointer("/choices/0/message/content")
        .and_then(Value::as_str)
    {
        return text.to_owned();
    }

    if let Some(text) = openai_response
        .pointer("/choices/0/text")
        .and_then(Value::as_str)
    {
        return text.to_owned();
    }

    "No output text found in OpenAI response.".to_owned()
}

fn truncate_for_error(input: &str, max_chars: usize) -> String {
    let count = input.chars().count();
    if count <= max_chars {
        return input.to_owned();
    }

    let truncated = input.chars().take(max_chars).collect::<String>();
    format!("{truncated}... (truncated)")
}
