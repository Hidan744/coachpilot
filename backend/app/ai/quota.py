from datetime import UTC, datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m


async def quota_ok(db: AsyncSession, owner_id) -> tuple[bool, m.Subscription | None]:
    """Есть ли у тренера AI-генерации в этом месяце. В начале нового месяца счётчик обнуляется."""
    sub = await db.get(m.Subscription, owner_id, with_for_update=True)
    if sub is None:
        return True, None
    now = datetime.now(UTC)
    if (now.year, now.month) != (sub.period_start.year, sub.period_start.month):
        sub.ai_used, sub.period_start = 0, now
    return sub.ai_used < sub.ai_quota_month, sub
