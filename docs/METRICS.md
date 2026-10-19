# Метрики продукта

События пишутся в таблицу `events` (своё хранилище, без сторонних SDK). Основные события:

| Событие | Когда | Свойства |
|---|---|---|
| `signup`, `login`, `app_open` | регистрация, вход, запуск | — |
| `team_created`, `player_added`, `drill_created` | создание сущностей | `age_group`, `has_scheme` |
| `ai_plan_generated` | получен план | `source` (ai/rules/offline_rules), `ms`, `warnings`, `clarifying` |
| `plan_saved` | план сохранён | `ai`, `blocks`, `edited` — сколько блоков тренер изменил после AI |
| `session_started`, `session_finished` | проведение | `blocks`, `skipped`, `minutes`, `notes_count` |
| `report_confirmed` | отчёт подтверждён | `ai_suggestions`, `rating` |
| `sync_conflict` | конфликт синхронизации | `count` |
| `app_error` | необработанная ошибка | `message`, `where`, `stack` |

## Запросы

```sql
-- Активация: доля зарегистрированных, кто провёл первую тренировку
SELECT count(DISTINCT f.user_id)::float / NULLIF(count(DISTINCT s.user_id), 0) AS activation
FROM events s LEFT JOIN events f ON f.user_id = s.user_id AND f.name = 'session_finished'
WHERE s.name = 'signup';

-- Доля AI-планов, принятых с небольшими правками (≤ 2 изменённых блока)
SELECT avg(((props->>'edited')::int <= 2)::int) AS accepted_share
FROM events WHERE name = 'plan_saved' AND (props->>'ai')::bool AND props ? 'edited';

-- Недельная активность тренеров (проводили занятия)
SELECT date_trunc('week', client_ts) AS week, count(DISTINCT user_id)
FROM events WHERE name = 'session_finished' GROUP BY 1 ORDER BY 1;

-- Себестоимость AI: токены за месяц
SELECT date_trunc('month', created_at) AS month, kind, count(*), sum(tokens_in) AS tin, sum(tokens_out) AS tout,
       avg(latency_ms)::int AS avg_ms, avg(valid::int) AS valid_share
FROM ai_requests GROUP BY 1, 2 ORDER BY 1;

-- Ошибки приложения за сутки
SELECT props->>'message' AS message, count(*) FROM events
WHERE name = 'app_error' AND created_at > now() - interval '1 day' GROUP BY 1 ORDER BY 2 DESC;

-- Ошибки синхронизации
SELECT date_trunc('day', created_at), sum((props->>'count')::int) FROM events
WHERE name = 'sync_conflict' GROUP BY 1 ORDER BY 1;
```
