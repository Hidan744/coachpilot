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

    # Регистраций с одного адреса в час (на тестовом стенде e2e — больше).
    register_limit_per_hour: int = 10

    # Внешний адрес API для ссылок родителям (https://api.example.ru). Пусто — адрес из запроса.
    public_base_url: str = ""
    # Часовой пояс для дат на странице родителей (Пермь — Asia/Yekaterinburg).
    display_tz: str = "Europe/Moscow"

    # AI: mock | yandexgpt | gigachat | openai_compat
    ai_provider: str = "mock"
    ai_api_key: str = ""
    ai_folder_id: str = ""  # YandexGPT
    ai_model: str = ""
    ai_base_url: str = ""  # openai_compat
    ai_ca_bundle: str = ""  # GigaChat: путь к сертификату НУЦ Минцифры
    ai_free_quota_month: int = 30

    # Тарифы: цены в рублях и лимиты AI задаются здесь или переменными окружения, а не в интерфейсе.
    price_pro_rub_month: int = 990
    price_academy_rub_month: int = 4990
    ai_pro_quota_month: int = 300
    ai_academy_quota_month: int = 2000
    # Оплата: off — не подключена; test — тестовый режим (недоступен при env=production).
    payments_mode: str = "off"

    # Telegram: без токена интеграция выключена и ничего не отправляет.
    telegram_bot_token: str = ""
    telegram_bot_username: str = ""
    telegram_webhook_secret: str = ""
    # Секрет для вызова рассылки напоминаний по расписанию (cron).
    cron_secret: str = ""

    # Сроки хранения (дни): удалённые записи, журналы AI-запросов и действий.
    retention_deleted_days: int = 180
    retention_ai_log_days: int = 365
    retention_audit_days: int = 1095


@lru_cache
def get_settings() -> Settings:
    return Settings()
