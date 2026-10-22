"""Журнал важных действий: кто и когда входил, выгружал или удалял данные, делился карточкой игрока."""

import uuid

from fastapi import Request
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m


def client_ip(request: Request | None) -> str:
    if request is None or request.client is None:
        return ""
    return request.client.host[:64]


async def audit(
    db: AsyncSession, user_id: uuid.UUID | None, action: str, request: Request | None = None, **details
) -> None:
    """Добавляет запись в журнал; фиксация — вместе с основной транзакцией."""
    db.add(m.AuditLog(user_id=user_id, action=action, details={k: str(v) for k, v in details.items()},
                      ip=client_ip(request)))
