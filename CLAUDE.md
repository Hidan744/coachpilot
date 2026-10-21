# CoachPilot — заметки для Claude

Мобильный помощник футбольного тренера: Flutter-приложение (`app/`) и FastAPI-бэкенд (`backend/`).
Обзор — в `README.md`, архитектура — в `docs/ARCHITECTURE.md`.

## Открытые задачи

Список исправлений по итогам ревью — `docs/REVIEW_TODO.md`. Прежде чем брать новую работу,
посмотри, что там ещё не отмечено `[x]`; закрывая пункт, отмечай его в том же коммите.

## Проверки перед пушем

- Backend: `cd backend && ruff check . && alembic upgrade head && alembic check && pytest -q`
  (нужен PostgreSQL и БД `coachpilot_test`, адрес — `CP_DATABASE_URL`).
- App: `cd app && dart run build_runner build --delete-conflicting-outputs && flutter analyze && flutter test`.
