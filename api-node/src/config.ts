export class ConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConfigError";
  }
}

export type AppConfig = {
  appName: string;
  appPort: number;
  corsAllowedOrigin: string;
  httpHealthPath: string;
  httpApiV1Prefix: string;
  databaseUrl: string;
  openaiBaseUrl: string;
  openaiModel: string;
  openaiApiKey: string;
};

function normalizeHttpPath(raw: string): string {
  const value = String(raw || "").trim();
  if (!value) {
    return "/";
  }
  const withLeadingSlash = value.startsWith("/") ? value : `/${value}`;
  return withLeadingSlash === "/"
    ? withLeadingSlash
    : withLeadingSlash.replace(/\/+$/, "");
}

function envWithDefault(key: string, defaultValue: string): string {
  const value = process.env[key];
  if (typeof value !== "string" || value.trim() === "") {
    return defaultValue;
  }
  return value;
}

function requiredEnv(key: string): string {
  const value = process.env[key];
  if (typeof value !== "string" || value.trim() === "") {
    throw new ConfigError(`missing required environment variable: ${key}`);
  }
  return value;
}

function parseAppPort(raw: string): number {
  const trimmed = raw.trim();
  if (trimmed === "" || !/^\d+$/.test(trimmed)) {
    throw new ConfigError("invalid port value: APP_PORT");
  }
  const port = Number.parseInt(trimmed, 10);
  if (Number.isNaN(port) || port < 1 || port > 65_535) {
    throw new ConfigError("invalid port value: APP_PORT");
  }
  return port;
}

export function loadConfig(): AppConfig {
  const appName = envWithDefault("APP_NAME", "api-node");
  const appPort = parseAppPort(envWithDefault("APP_PORT", "4002"));
  const corsAllowedOrigin = requiredEnv("CORS_ALLOWED_ORIGIN");
  const databaseUrl = requiredEnv("DATABASE_URL");
  const openaiBaseUrl = envWithDefault(
    "OPENAI_BASE_URL",
    "https://api.openai.com",
  );
  const openaiModel = requiredEnv("OPENAI_MODEL");
  const openaiApiKey = requiredEnv("OPENAI_API_KEY");

  const httpHealthPath = normalizeHttpPath(
    envWithDefault("HTTP_HEALTH_PATH", "/health"),
  );
  const httpApiV1Prefix = normalizeHttpPath(
    envWithDefault("HTTP_API_V1_PREFIX", "/api/v1"),
  );

  return {
    appName,
    appPort,
    corsAllowedOrigin,
    httpHealthPath,
    httpApiV1Prefix,
    databaseUrl,
    openaiBaseUrl,
    openaiModel,
    openaiApiKey,
  };
}
