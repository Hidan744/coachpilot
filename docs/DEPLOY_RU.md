# Развёртывание в России

Проверено на стенде разработки; продовая инфраструктура не развёрнута. Ниже — что нужно для запуска.

## Состав

- **API**: Python 3.12, FastAPI (`backend/`), uvicorn за обратным прокси (nginx) с HTTPS.
- **БД**: PostgreSQL 15+. Миграции: `alembic upgrade head`.
- **Каталог упражнений**: `python -m app.catalog.seed` после миграций.
- **Клиент**: Flutter — Android, iOS, Windows и веб (`flutter build web --no-web-resources-cdn` — без загрузки ресурсов с серверов Google).

## Где разместить

Любое облако с дата-центрами в России: Yandex Cloud, Selectel, VK Cloud, Cloud.ru.
Managed PostgreSQL снимает часть задач по резервным копиям и обновлениям.

## Переменные окружения (секреты — только на сервере)

| Переменная | Зачем |
|---|---|
| `CP_ENV=production` | Отключает тестовую оплату |
| `CP_DATABASE_URL` | Подключение к PostgreSQL |
| `CP_JWT_SECRET` | Подпись токенов (длинная случайная строка) |
| `CP_CORS_ORIGINS` | Адреса веб-клиента |
| `CP_PUBLIC_BASE_URL` | Внешний адрес API для ссылок родителям |
| `CP_AI_PROVIDER`, `CP_AI_API_KEY`, `CP_AI_FOLDER_ID` | YandexGPT или GigaChat; без них планы собираются по правилам |
| `CP_TELEGRAM_BOT_TOKEN`, `CP_TELEGRAM_BOT_USERNAME`, `CP_TELEGRAM_WEBHOOK_SECRET` | Уведомления; без них Telegram выключен |
| `CP_CRON_SECRET` | Защита вызова рассылки напоминаний |
| `CP_PRICE_PRO_RUB_MONTH`, `CP_PRICE_ACADEMY_RUB_MONTH`, `CP_AI_*_QUOTA_MONTH` | Тарифы |
| `CP_PAYMENTS_MODE` | `off` — оплата не подключена (по умолчанию) |

Хранить в менеджере секретов облака (Lockbox в Yandex Cloud и т. п.), не в репозитории.

## Расписание (cron)

```
*/15 * * * *  curl -s -X POST -H "X-Cron-Secret: $CP_CRON_SECRET" https://api.example.ru/notifications/reminders/run
0 3 * * *     cd /srv/coachpilot/backend && python -m app.maintenance purge
```

Webhook Telegram: `https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://api.example.ru/telegram/webhook/<SECRET>`.

## Резервные копии и восстановление

- Ежедневный `pg_dump` (или снимки managed PostgreSQL), хранение 30 дней в объектном хранилище в России.
- Раз в месяц — проверка восстановления на отдельный стенд: `pg_restore` → `alembic upgrade head` → прогон `pytest`.
- Пользователь может сам сохранить копию своих данных (Профиль → Резервная копия, JSON) и восстановить её.

## Мониторинг и журналы

- `/health` — проверка живости для балансировщика.
- Журнал запросов и ошибок — stdout uvicorn → сборщик логов облака.
- Журнал AI-запросов (`ai_requests`) — задержка, ошибки, валидность ответа.
- Журнал действий пользователей (`audit_log`).

## Устойчивость к потере связи

Клиент хранит всё на устройстве и синхронизирует очередь изменений при появлении сети; конфликты тренировок, отчётов и упражнений не перезаписываются молча. Проверено e2e-сценарием `smoke_stage2` (работа без сети и последующая синхронизация).

## Что проверить перед запуском

- Внешние сервисы: в вебе — без CDN Google (флаг `--no-web-resources-cdn`), шрифты встроены в приложение.
- Юридические вопросы — `SECURITY.md`.
- Нагрузочный тест синхронизации на реалистичном объёме (школа на 300 игроков).
