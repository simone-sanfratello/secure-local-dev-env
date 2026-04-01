#[derive(Clone)]
pub struct AppConfig {
    pub app_name: String,
    pub app_port: String,
    pub http_health_path: String,
    pub http_api_v1_prefix: String,
    pub database_url: String,
    pub cors_allowed_origin: String,
    pub redis_url: String,
    pub openai_base_url: String,
    pub openai_model: String,
    pub openai_api_key: String,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("missing required environment variable: {0}")]
    Missing(String),
    #[error("invalid header value: {0}")]
    InvalidHeader(String),
    #[error("invalid port value: {0}")]
    InvalidPort(String),
}

impl AppConfig {
    pub fn from_env() -> Result<Self, ConfigError> {
        let app_name = std::env::var("APP_NAME").unwrap_or_else(|_| "api-rust".into());
        let app_port = std::env::var("APP_PORT")
            .unwrap_or_else(|_| "4000".into())
            .parse::<u16>()
            .map_err(|_| ConfigError::InvalidPort("APP_PORT".to_string()))?;
        let cors_allowed_origin = std::env::var("CORS_ALLOWED_ORIGIN")
            .map_err(|_| ConfigError::Missing("CORS_ALLOWED_ORIGIN".to_string()))?;
        let database_url = std::env::var("DATABASE_URL")
            .map_err(|_| ConfigError::Missing("DATABASE_URL".to_string()))?;
        let redis_url = std::env::var("REDIS_URL")
            .map_err(|_| ConfigError::Missing("REDIS_URL".to_string()))?;
        let openai_base_url =
            std::env::var("OPENAI_BASE_URL").unwrap_or_else(|_| "https://api.openai.com".into());
        let openai_model = std::env::var("OPENAI_MODEL")
            .map_err(|_| ConfigError::Missing("OPENAI_MODEL".to_string()))?;
        let openai_api_key = std::env::var("OPENAI_API_KEY")
            .map_err(|_| ConfigError::Missing("OPENAI_API_KEY".to_string()))?;

        let http_health_path = normalize_http_path(
            std::env::var("HTTP_HEALTH_PATH").unwrap_or_else(|_| "/health".into()),
        );

        let http_api_v1_prefix = normalize_http_path(
            std::env::var("HTTP_API_V1_PREFIX").unwrap_or_else(|_| "/api/v1".into()),
        );

        Ok(Self {
            app_name,
            app_port: app_port.to_string(),
            http_health_path,
            http_api_v1_prefix,
            database_url,
            cors_allowed_origin,
            redis_url,
            openai_base_url,
            openai_model,
            openai_api_key,
        })
    }
}

/// Ensures a leading `/` and no trailing `/` (except root `/`).
fn normalize_http_path(s: String) -> String {
    let t = s.trim();
    if t.is_empty() {
        return "/".to_string();
    }
    let with_lead = if t.starts_with('/') {
        t.to_string()
    } else {
        format!("/{t}")
    };
    if with_lead == "/" {
        return with_lead;
    }
    with_lead.trim_end_matches('/').to_string()
}
