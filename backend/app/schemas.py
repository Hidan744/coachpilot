"""Pydantic-схемы API и полей синхронизируемых сущностей."""

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

ShortStr = Field(max_length=150)
TextStr = Field(default="", max_length=10_000)
StrList = Field(default_factory=list, max_length=50)

# ------------------------------------------------------------------ авторизация


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str = Field(min_length=1, max_length=100)
    consent_personal_data: bool

    @field_validator("consent_personal_data")
    @classmethod
    def consent_required(cls, v: bool) -> bool:
        if not v:
            raise ValueError("Необходимо согласие на обработку персональных данных")
        return v


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str = Field(max_length=200)


class TokensOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    name: str
    role: str
    city: str | None
    coaching_level: str | None
    created_at: datetime


class ProfileUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    city: str | None = Field(default=None, max_length=100)
    coaching_level: str | None = Field(default=None, max_length=50)


class DeleteAccountIn(BaseModel):
    password: str = Field(max_length=128)


# ------------------------------------------------------------ поля сущностей

AgeGroup = str  # U6..U19, adult — свободная строка, проверяется на клиенте
Phase = Literal["warmup", "main", "game", "cooldown"]


class TeamData(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    age_group: str = Field(min_length=1, max_length=20)
    level: str = Field(min_length=1, max_length=30)
    default_players: int = Field(ge=1, le=60)
    field_type: str | None = Field(default=None, max_length=30)
    equipment: list[str] = StrList
    notes: str = TextStr


class PlayerData(BaseModel):
    team_id: uuid.UUID
    first_name: str = Field(min_length=1, max_length=60)
    last_name: str = Field(default="", max_length=60)
    birth_year: int | None = Field(default=None, ge=1940, le=2030)
    position: str | None = Field(default=None, max_length=30)
    number: int | None = Field(default=None, ge=0, le=999)
    notes: str = TextStr
    active: bool = True


class SchemeItem(BaseModel):
    """Элемент схемы поля. Координаты нормированы 0..1 относительно поля."""

    model_config = ConfigDict(extra="allow")

    type: Literal[
        "player_a", "player_b", "neutral", "goalkeeper", "cone", "ball", "goal",
        "mini_goal", "pole", "arrow_pass", "arrow_run", "arrow_dribble", "zone", "label",
    ]
    x: float = Field(ge=-0.1, le=1.1)
    y: float = Field(ge=-0.1, le=1.1)
    x2: float | None = Field(default=None, ge=-0.1, le=1.1)
    y2: float | None = Field(default=None, ge=-0.1, le=1.1)
    label: str | None = Field(default=None, max_length=20)


class Scheme(BaseModel):
    field: Literal["full", "half", "third", "box", "grid"] = "half"
    items: list[SchemeItem] = Field(default_factory=list, max_length=200)


class DrillVariants(BaseModel):
    easier: list[str] = Field(default_factory=list, max_length=10)
    harder: list[str] = Field(default_factory=list, max_length=10)


DRILL_CATEGORIES = (
    "warmup", "technique", "passing", "dribbling", "finishing", "possession",
    "tactics", "transition", "defending", "physical", "game", "cooldown", "goalkeeping",
)


class DrillData(BaseModel):
    source: Literal["user", "ai"] = "user"
    title: str = Field(min_length=1, max_length=150)
    category: Literal[DRILL_CATEGORIES]  # type: ignore[valid-type]
    goal: str = TextStr
    age_min: int = Field(default=6, ge=4, le=99)
    age_max: int = Field(default=99, ge=4, le=99)
    players_min: int = Field(default=1, ge=1, le=60)
    players_max: int = Field(default=30, ge=1, le=60)
    duration_min: int = Field(default=10, ge=1, le=120)
    field_size: str = Field(default="", max_length=50)
    intensity: Literal["low", "medium", "high"] = "medium"
    equipment: list[str] = StrList
    setup: str = TextStr
    steps: list[str] = StrList
    rules: list[str] = StrList
    coaching_points: list[str] = StrList
    success_criteria: list[str] = StrList
    variants: DrillVariants = Field(default_factory=DrillVariants)
    scheme: Scheme | None = None
    tags: list[str] = StrList


class FavoriteData(BaseModel):
    drill_id: uuid.UUID


class TrainingBlock(BaseModel):
    id: str = Field(min_length=1, max_length=64)
    phase: Phase
    title: str = Field(min_length=1, max_length=150)
    duration_min: int = Field(ge=1, le=120)
    drill_id: uuid.UUID | None = None
    # Снимок упражнения на момент добавления: план не ломается, если упражнение
    # в библиотеке потом изменят или удалят, и доступен офлайн.
    drill: dict[str, Any] | None = None
    notes: str = Field(default="", max_length=2000)


class TrainingSessionData(BaseModel):
    team_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=150)
    scheduled_at: datetime | None = None
    goal: str = TextStr
    duration_min: int = Field(ge=5, le=300)
    players_expected: int | None = Field(default=None, ge=1, le=60)
    field_type: str | None = Field(default=None, max_length=30)
    equipment: list[str] = StrList
    status: Literal["draft", "planned", "in_progress", "done", "cancelled"] = "draft"
    ai_generated: bool = False
    ai_assumptions: list[str] = StrList
    blocks: list[TrainingBlock] = Field(default_factory=list, max_length=40)
    started_at: datetime | None = None
    finished_at: datetime | None = None
    actual: dict[str, Any] = Field(default_factory=dict)
    conflict_of: uuid.UUID | None = None


class AttendanceData(BaseModel):
    session_id: uuid.UUID
    player_id: uuid.UUID
    status: Literal["present", "absent", "late", "injured", "excused"]


class SessionNoteData(BaseModel):
    session_id: uuid.UUID
    block_id: str | None = Field(default=None, max_length=64)
    text: str = Field(min_length=1, max_length=5000)
    noted_at: datetime


class SessionReportData(BaseModel):
    session_id: uuid.UUID
    raw_input: str = TextStr
    rating: int | None = Field(default=None, ge=1, le=5)
    went_well: str = TextStr
    to_improve: str = TextStr
    observations: str = TextStr
    ai_suggestions: list[str] = StrList
    coach_confirmed: bool = False
    confirmed_at: datetime | None = None


class PlayerAssessmentData(BaseModel):
    player_id: uuid.UUID
    session_id: uuid.UUID | None = None
    skill: str = Field(min_length=1, max_length=40)
    score: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=2000)
    assessed_at: datetime


# -------------------------------------------------------------------- синхронизация

EntityName = Literal[
    "teams", "players", "drills", "favorites", "training_sessions", "attendance",
    "session_notes", "session_reports", "player_assessments",
]


class Change(BaseModel):
    entity: EntityName
    id: uuid.UUID
    op: Literal["upsert", "delete"]
    # server_seq версии, от которой клиент делал правку; None — запись создана на клиенте.
    base_seq: int | None = None
    data: dict[str, Any] | None = None


class PushIn(BaseModel):
    changes: list[Change]


class SyncRecord(BaseModel):
    entity: EntityName
    id: uuid.UUID
    server_seq: int
    updated_at: datetime
    deleted: bool
    data: dict[str, Any]


class ChangeResult(BaseModel):
    entity: EntityName
    id: uuid.UUID
    status: Literal["applied", "conflict", "rejected"]
    server_seq: int | None = None
    error: str | None = None
    # При конфликте — актуальная серверная версия, чтобы клиент мог её принять.
    server_record: SyncRecord | None = None


class PushOut(BaseModel):
    results: list[ChangeResult]


class PullOut(BaseModel):
    records: list[SyncRecord]
    cursor: int
    has_more: bool
