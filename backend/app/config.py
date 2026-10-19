from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CP_", env_file=".env", extra="ignore")

    env: str = "dev"
    database_url: str = "postgresql+asyncpg://coachpilot:coachpilot@localhost:5432/coachpilot"

    jwt_secret: str = "dev-secret-change-me-dev-secret-change-me"
    jwt_algorithm: str = "HS256"
    access_token_ttl_min: int = 30
    refresh_token_ttl_days: int = 60

    # Версия текста согласия на обработку ПД, которую принимает пользователь.
    consent_version: str = "2026-10"

    sync_push_max_changes: int = 500
    sync_pull_max_limit: int = 1000

    cors_origins: list[str] = ["*"]


@lru_cache
def get_settings() -> Settings:
    return Settings()
