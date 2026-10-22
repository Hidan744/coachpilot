"""Сроки хранения: окончательно удаляет то, что больше не нужно хранить.

    python -m app.maintenance purge   # запускать по расписанию, например раз в сутки

- записи, удалённые пользователем, — через retention_deleted_days после удаления
  (до этого они нужны, чтобы удаление дошло до всех устройств);
- журнал AI-запросов — через retention_ai_log_days;
- журнал действий — через retention_audit_days;
- просроченные коды привязки Telegram.
"""

import argparse
import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.config import get_settings
from app.sync import REGISTRY


async def purge(db: AsyncSession, now: datetime | None = None) -> dict[str, int]:
    st, now = get_settings(), now or datetime.now(UTC)
    out: dict[str, int] = {}
    deleted_before = now - timedelta(days=st.retention_deleted_days)
    for name, spec in REGISTRY.items():
        r = await db.execute(delete(spec.model).where(spec.model.deleted_at.is_not(None),
                                                      spec.model.deleted_at < deleted_before))
        if r.rowcount:
            out[name] = r.rowcount
    ai_before = now - timedelta(days=st.retention_ai_log_days)
    r = await db.execute(delete(m.AIRequest).where(m.AIRequest.created_at < ai_before))
    out["ai_requests"] = r.rowcount
    r = await db.execute(delete(m.AuditLog).where(m.AuditLog.at < now - timedelta(days=st.retention_audit_days)))
    out["audit_log"] = r.rowcount
    r = await db.execute(delete(m.TelegramLinkCode).where(m.TelegramLinkCode.expires_at < now))
    out["telegram_codes"] = r.rowcount
    await db.commit()
    return out


async def _cli() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["purge"])
    ap.parse_args()
    from app.db import SessionLocal

    async with SessionLocal() as db:
        print(await purge(db))


if __name__ == "__main__":
    asyncio.run(_cli())
