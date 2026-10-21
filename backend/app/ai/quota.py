from datetime import UTC, datetime

from sqlalchemy import func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m


async def reserve(db: AsyncSession, owner_id) -> bool | None:
    """Резервирует одну AI-генерацию и сразу фиксирует транзакцию, чтобы не держать блокировку
    строки подписки, пока идёт запрос к модели. В начале нового месяца счётчик обнуляется.

    True — генерация зарезервирована, False — лимит исчерпан, None — подписки нет (лимита нет)."""
    sub = await db.get(m.Subscription, owner_id, with_for_update=True)
    if sub is None:
        return None
    now = datetime.now(UTC)
    if (now.year, now.month) != (sub.period_start.year, sub.period_start.month):
        sub.ai_used, sub.period_start = 0, now
    ok = sub.ai_used < sub.ai_quota_month
    if ok:
        sub.ai_used += 1
    await db.commit()
    return ok


async def release(db: AsyncSession, owner_id) -> None:
    """Возвращает резерв, если AI не дал результата (ошибка модели или сети)."""
    await db.execute(update(m.Subscription).where(m.Subscription.user_id == owner_id)
                     .values(ai_used=func.greatest(m.Subscription.ai_used - 1, 0)))
