# Развёртывание

## Сервер (backend)

Требования 152-ФЗ: персональные данные граждан РФ хранятся на серверах в РФ.
Подходит любой VPS российского облака: Yandex Cloud, Selectel, Timeweb Cloud, VK Cloud.

Для пилота достаточно VPS 2 vCPU / 4 ГБ RAM / 40 ГБ SSD (~1,5–3 тыс. ₽/мес).

1. Установите Docker и Docker Compose на сервер.
2. Направьте A-запись домена API (например `api.coachpilot.ru`) на IP сервера.
3. Скопируйте репозиторий и настройте окружение:
   ```bash
   cd deploy
   cp .env.prod.example .env   # заполните DOMAIN, DB_PASSWORD, CP_JWT_SECRET, ключи AI
   docker compose -f docker-compose.prod.yml up -d --build
   docker compose -f docker-compose.prod.yml exec api python -m app.catalog.seed
   ```
4. Проверка: `curl https://api.coachpilot.ru/health` → `{"status":"ok"}`.

Миграции БД применяются автоматически при старте контейнера API (`alembic upgrade head`).
Каталог упражнений обновляется командой `python -m app.catalog.seed` (идемпотентно).

### Бэкапы
Сервис `backup` раз в сутки делает `pg_dump` в `deploy/backups/` и хранит 14 дней.
Копируйте эту папку в объектное хранилище (Yandex Object Storage / Selectel S3), например через `rclone` по cron.
Восстановление: `pg_restore -h localhost -U coachpilot -d coachpilot --clean coachpilot-YYYY-MM-DD.dump`.

### Обновление
```bash
git pull && cd deploy && docker compose -f docker-compose.prod.yml up -d --build api
```

## AI-провайдер

| Провайдер | Переменные | Где взять |
|---|---|---|
| YandexGPT | `CP_AI_PROVIDER=yandexgpt`, `CP_AI_API_KEY`, `CP_AI_FOLDER_ID` | Yandex Cloud → AI Studio: сервисный аккаунт с ролью `ai.languageModels.user`, API-ключ, id каталога |
| GigaChat | `CP_AI_PROVIDER=gigachat`, `CP_AI_API_KEY` (ключ авторизации), `CP_AI_CA_BUNDLE` | developers.sber.ru; нужен корневой сертификат НУЦ Минцифры |
| Любой OpenAI-совместимый | `CP_AI_PROVIDER=openai_compat`, `CP_AI_BASE_URL`, `CP_AI_API_KEY`, `CP_AI_MODEL` | локальная модель, прокси и т.п. |

После подключения ключа проверьте качество на 20 запросах:
```bash
docker compose -f docker-compose.prod.yml exec api python -m app.ai.eval
```
Если AI недоступен, приложение автоматически собирает план по правилам из библиотеки.

## Мобильное приложение

Адрес API задаётся при сборке:
```bash
cd app
flutter build apk --release --dart-define=API_URL=https://api.coachpilot.ru       # Android APK
flutter build appbundle --release --dart-define=API_URL=https://api.coachpilot.ru # Google Play / RuStore
flutter build ipa --release --dart-define=API_URL=https://api.coachpilot.ru       # iOS (нужен macOS + Xcode)
```

* **Android**: перед публикацией создайте ключ подписи (`keytool -genkey ...`) и пропишите его в
  `android/key.properties` (см. документацию Flutter «Build and release an Android app»).
  Каналы: RuStore (бесплатно, доступно из РФ), Google Play, прямая раздача APK пилотным тренерам.
* **iOS**: нужен Apple Developer Program ($99/год) и macOS с Xcode или облачная сборка (Codemagic).
  Для пилота — TestFlight.
* **Web-версия** (для демонстраций): `flutter build web --release --no-web-resources-cdn` — статические файлы
  можно раздать тем же Caddy.

## Мониторинг

* Журнал API: `docker compose logs -f api` — медленные (>3 с) и ошибочные запросы с `x-request-id`.
* Ошибки приложения и продуктовые события — таблица `events` (см. [METRICS.md](METRICS.md)).
* Журнал AI-запросов (провайдер, токены, время, ошибки валидации) — таблица `ai_requests`.

## Демо-версия в браузере (без сервера)

Сборка с `DEMO_ONLY=true` сразу открывает демо-режим: всё работает в браузере, данные хранятся
в IndexedDB этого браузера, планы собираются из встроенной библиотеки по правилам (без AI).
```bash
cd app
flutter build web --release --no-web-resources-cdn --dart-define=DEMO_ONLY=true
```
Папку `build/web` можно раздать любым статическим хостингом (Caddy, Nginx, Yandex Object Storage).
В обычной сборке тот же режим доступен по кнопке «Попробовать без регистрации» на экране входа.

## Web-версия на GitHub Pages

Workflow `.github/workflows/pages.yml` при каждом пуше в `main` собирает демо-версию и публикует её
по адресу `https://<владелец>.github.io/coachpilot/`. Один раз включите в настройках репозитория:
**Settings → Pages → Build and deployment → Source: GitHub Actions**.
GitHub Pages для приватного репозитория доступен на платных тарифах GitHub; на бесплатном репозиторий должен быть публичным.
