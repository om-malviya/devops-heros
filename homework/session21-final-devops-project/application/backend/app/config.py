from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Every field can be overridden by an environment variable
    of the same name in upper case (APP_NAME, DATABASE_URL, LOG_LEVEL, APP_ENV, CORS_ORIGINS).
    In Kubernetes the non-sensitive values come from a ConfigMap and DATABASE_URL from a Secret."""

    app_name: str = "TaskBoard API"
    app_env: str = "local"
    log_level: str = "info"
    # Comma-separated list of browser origins allowed by CORS. Kept explicit on purpose:
    # a wildcard "*" was flagged by Semgrep (python.fastapi.security.wildcard-cors) in the
    # CI SAST gate. In Kubernetes/Compose the browser reaches the API through the frontend
    # nginx proxy (same origin), so only the dev-server origins are needed by default.
    cors_origins: str = "http://localhost:5173,http://localhost:3000"
    database_url: str = "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
