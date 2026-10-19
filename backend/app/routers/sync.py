from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app import sync
from app.config import get_settings
from app.db import get_db
from app.models import User
from app.schemas import PullOut, PushIn, PushOut
from app.security import current_user

router = APIRouter(tags=["sync"])


@router.post("/sync/push", response_model=PushOut)
async def push(
    body: PushIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> PushOut:
    if len(body.changes) > get_settings().sync_push_max_changes:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Слишком много изменений")
    return PushOut(results=await sync.push(db, user.id, body.changes))


@router.get("/sync/pull", response_model=PullOut)
async def pull(
    since: int = Query(0, ge=0),
    limit: int = Query(500, ge=1),
    user: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
) -> PullOut:
    limit = min(limit, get_settings().sync_pull_max_limit)
    return await sync.pull(db, user.id, since, limit)


@router.get("/catalog/drills")
async def catalog(
    version: str = Query("", max_length=64),
    _: User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Системная библиотека упражнений. Клиент передаёт версию (хеш) своего каталога —
    если она совпадает с серверной, список не отдаётся повторно."""
    current, drills = await sync.system_catalog(db)
    if version == current:
        return {"version": current, "changed": False, "drills": []}
    return {"version": current, "changed": True, "drills": drills}
