import logging
import time
import uuid

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.config import get_settings
from app.db import engine
from app.routers import account, ai, auth, events, shares, sync

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("coachpilot")

_settings = get_settings()
if _settings.env == "prod" and ("change-me" in _settings.jwt_secret or len(_settings.jwt_secret) < 32):
    raise RuntimeError("CP_JWT_SECRET не задан: в продакшене нужен случайный секрет длиной от 32 символов")

app = FastAPI(title="CoachPilot API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(account.router)
app.include_router(sync.router)
app.include_router(ai.router)
app.include_router(events.router)
app.include_router(shares.router)


@app.middleware("http")
async def request_log(request: Request, call_next):
    """Журнал запросов с id и временем; необработанные ошибки — в лог и понятный ответ клиенту."""
    rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:12]
    started = time.monotonic()
    try:
        response = await call_next(request)
    except Exception:
        log.exception("unhandled error rid=%s %s %s", rid, request.method, request.url.path)
        response = JSONResponse({"detail": "Ошибка сервера, попробуйте позже"}, status_code=500)
    ms = int((time.monotonic() - started) * 1000)
    if response.status_code >= 500 or ms > 3000:
        log.warning("rid=%s %s %s -> %s %dms", rid, request.method, request.url.path, response.status_code, ms)
    response.headers["x-request-id"] = rid
    return response


@app.get("/health", tags=["system"])
async def health() -> dict:
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    return {"status": "ok"}
