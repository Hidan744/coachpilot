import json
from datetime import datetime

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_db
from app.models import Event, User
from app.security import current_user

router = APIRouter(tags=["events"])


class EventIn(BaseModel):
    name: str = Field(pattern=r"^[a-z][a-z0-9_]{1,49}$")
    props: dict = Field(default_factory=dict)
    ts: datetime

    @field_validator("props")
    @classmethod
    def small(cls, v: dict) -> dict:
        if len(json.dumps(v, ensure_ascii=False)) > 2000:
            raise ValueError("props слишком большие")
        return v


class EventsIn(BaseModel):
    events: list[EventIn] = Field(max_length=200)
    platform: str = Field(default="", max_length=20)
    app_version: str = Field(default="", max_length=20)


@router.post("/events", status_code=status.HTTP_204_NO_CONTENT)
async def ingest(body: EventsIn, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> None:
    db.add_all(
        Event(user_id=user.id, name=e.name, props=e.props, client_ts=e.ts,
              platform=body.platform, app_version=body.app_version)
        for e in body.events
    )
    await db.commit()
