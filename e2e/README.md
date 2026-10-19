# E2E-проверки (Flutter web + Playwright)

```bash
# 1. backend
cd backend && .venv/bin/uvicorn app.main:app --port 8000 &
# 2. web-сборка приложения
cd app && flutter build web --release --no-web-resources-cdn --dart-define=API_URL=http://localhost:8000
python3 -m http.server 8080 -d build/web &
# 3. сценарии (нужен пакет playwright)
cd e2e && npm i playwright && node smoke_stage2.mjs
```

Переменные: `APP_URL`, `API_URL`, `SHOTS` (папка для скриншотов), `CHROME` (путь к Chromium).
