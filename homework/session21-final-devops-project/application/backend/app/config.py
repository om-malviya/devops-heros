from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Every field can be overridden by an environment variable
    of the same name in upper case (APP_NAME, DATABASE_URL, LOG_LEVEL, APP_ENV).
    In Kubernetes the non-sensitive values come from a ConfigMap and DATABASE_URL from a Secret."""

    app_name: str = "TaskBoard API"
    app_env: str = "local"
    log_level: str = "info"
    database_url: str = "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskboard"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
