from functools import lru_cache

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai import planner
from app.ai.providers import LLMProvider, build_provider
from app.config import get_settings
from app.db import get_db
from app.models import Subscription, User
from app.security import current_user

router = APIRouter(prefix="/ai", tags=["ai"])


@lru_cache
def _provider() -> LLMProvider:
    return build_provider(get_settings())


def get_provider() -> LLMProvider:
    return _provider()


@router.post("/plan", response_model=planner.PlanOut)
async def plan(
    body: planner.PlanRequest,
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
    provider: LLMProvider = Depends(get_provider),
) -> planner.PlanOut:
    try:
        return await planner.generate_plan(db, provider, user.id, body)
    except ValueError as e:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(e)) from e


@router.get("/quota")
async def quota(user: User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    sub = await db.get(Subscription, user.id)
    if sub is None:
        return {"plan": "free", "used": 0, "limit": 0}
    return {"plan": sub.plan, "used": sub.ai_used, "limit": sub.ai_quota_month}
