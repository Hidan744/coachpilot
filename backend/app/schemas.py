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


class TeamGoal(BaseModel):
    text: str = Field(min_length=1, max_length=300)
    done: bool = False


class TeamData(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    age_group: str = Field(min_length=1, max_length=20)
    level: str = Field(min_length=1, max_length=30)
    default_players: int = Field(ge=1, le=60)
    field_type: str | None = Field(default=None, max_length=30)
    equipment: list[str] = StrList
    notes: str = TextStr
    formation: str = Field(default="", max_length=20)
    season_goals: list[TeamGoal] = Field(default_factory=list, max_length=20)


class PlayerData(BaseModel):
    team_id: uuid.UUID
    first_name: str = Field(min_length=1, max_length=60)
    last_name: str = Field(default="", max_length=60)
    birth_year: int | None = Field(default=None, ge=1940, le=2030)
    position: str | None = Field(default=None, max_length=30)
    number: int | None = Field(default=None, ge=0, le=999)
    notes: str = TextStr
    active: bool = True
    dominant_foot: Literal["right", "left", "both"] | None = None
    level: str | None = Field(default=None, max_length=30)
    strengths: str = TextStr
    weaknesses: str = TextStr
    goals: str = TextStr


class SchemeItem(BaseModel):
    """Элемент схемы поля. Координаты нормированы 0..1 относительно поля."""

    model_config = ConfigDict(extra="allow")

    type: Literal[
        "player_a", "player_b", "neutral", "goalkeeper", "cone", "ball", "goal",
        "mini_goal", "pole", "arrow_pass", "arrow_run", "arrow_dribble", "zone", "label", "pen",
    ]
    x: float = Field(ge=-0.1, le=1.1)
    y: float = Field(ge=-0.1, le=1.1)
    x2: float | None = Field(default=None, ge=-0.1, le=1.1)
    y2: float | None = Field(default=None, ge=-0.1, le=1.1)
    label: str | None = Field(default=None, max_length=30)
    # Линия от руки (тактическая доска): точки [[x, y], ...] в тех же координатах.
    points: list[list[float]] | None = Field(default=None, max_length=500)
    color: str | None = Field(default=None, max_length=9)
    # Шаг анимации для стрелок движения: стрелки одного шага проигрываются одновременно.
    step: int | None = Field(default=None, ge=1, le=20)


class Scheme(BaseModel):
    field: Literal["full", "full_v", "half", "third", "box", "grid"] = "half"
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
    # Конструктор: почему упражнение выбрано, дозировка, вариант сложности.
    why: str = Field(default="", max_length=1000)
    dosage: str = Field(default="", max_length=300)
    variant: Literal["base", "easier", "harder"] = "base"


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
    # Параметры конструктора (формат, интенсивность, позиции, уровень) — для пересборки плана.
    params: dict[str, Any] = Field(default_factory=dict)


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
    rpe: int | None = Field(default=None, ge=1, le=10)
    # Комментарии по игрокам {player_id: текст} и что изменить в следующий раз.
    player_notes: dict[str, str] = Field(default_factory=dict, max_length=60)
    next_time: str = TextStr

    @field_validator("player_notes")
    @classmethod
    def _notes(cls, v: dict[str, str]) -> dict[str, str]:
        for k, text in v.items():
            uuid.UUID(k)  # ключ — id игрока
            if len(text) > 2000:
                raise ValueError("player note too long")
        return {k: t for k, t in v.items() if t.strip()}


class PlayerAssessmentData(BaseModel):
    player_id: uuid.UUID
    session_id: uuid.UUID | None = None
    skill: str = Field(min_length=1, max_length=40)
    score: int = Field(ge=1, le=5)
    comment: str = Field(default="", max_length=2000)
    assessed_at: datetime


DateStr = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")


class MatchData(BaseModel):
    team_id: uuid.UUID
    opponent: str = Field(min_length=1, max_length=100)
    starts_at: datetime
    duration_min: int = Field(default=90, ge=10, le=240)
    home: bool = True
    venue: str = Field(default="", max_length=150)
    competition: str = Field(default="", max_length=100)
    status: Literal["scheduled", "played", "cancelled"] = "scheduled"
    score_for: int | None = Field(default=None, ge=0, le=99)
    score_against: int | None = Field(default=None, ge=0, le=99)
    notes: str = TextStr


class ScheduleSlotData(BaseModel):
    team_id: uuid.UUID
    title: str = Field(min_length=1, max_length=100)
    weekdays: list[int] = Field(min_length=1, max_length=7)
    start_time: str = Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    duration_min: int = Field(default=90, ge=10, le=300)
    location: str = Field(default="", max_length=150)
    valid_from: str | None = DateStr
    valid_to: str | None = DateStr
    notes: str = TextStr

    @field_validator("weekdays")
    @classmethod
    def _days(cls, v: list[int]) -> list[int]:
        if any(d < 1 or d > 7 for d in v):
            raise ValueError("weekday must be 1..7")
        return sorted(set(v))


class PlanItem(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    kind: Literal["goal", "task"] = "task"
    done: bool = False


class PlanTarget(BaseModel):
    """Показатель программы: сейчас → цель, как измеряем."""

    name: str = Field(min_length=1, max_length=100)
    current: float | None = Field(default=None, ge=-1000, le=100000)
    target: float | None = Field(default=None, ge=-1000, le=100000)
    unit: str = Field(default="", max_length=20)
    measure: str = Field(default="", max_length=500)
    comment: str = Field(default="", max_length=1000)
    priority: Literal["high", "medium", "low"] = "medium"


class PlanWeek(BaseModel):
    """Неделя индивидуальной программы: приоритет, упражнения, нагрузка, ожидаемый результат."""

    n: int = Field(ge=1, le=12)
    priority: str = Field(min_length=1, max_length=200)
    drills: list[str] = Field(default_factory=list, max_length=10)
    sessions: int = Field(default=2, ge=0, le=14)
    load: str = Field(default="", max_length=300)
    expected: str = Field(default="", max_length=500)
    criteria: str = Field(default="", max_length=500)
    done: bool = False
    comment: str = Field(default="", max_length=1000)


class DevelopmentPlanData(BaseModel):
    player_id: uuid.UUID
    period: Literal["week", "month", "season", "cycle4", "cycle6", "cycle8", "cycle12"]
    title: str = Field(min_length=1, max_length=150)
    starts_on: str | None = DateStr
    ends_on: str | None = DateStr
    focus: list[str] = StrList
    items: list[PlanItem] = Field(default_factory=list, max_length=60)
    comment: str = TextStr
    shared: bool = True
    key_goal: str = Field(default="", max_length=1000)
    targets: list[PlanTarget] = Field(default_factory=list, max_length=12)
    weeks: list[PlanWeek] = Field(default_factory=list, max_length=12)


class TacticBoardData(BaseModel):
    team_id: uuid.UUID | None = None
    match_id: uuid.UUID | None = None
    title: str = Field(min_length=1, max_length=150)
    formation: str = Field(default="", max_length=20)
    scheme: Scheme = Field(default_factory=Scheme)
    notes: str = TextStr


class ParentNoteData(BaseModel):
    player_id: uuid.UUID
    category: Literal["general", "psychology", "nutrition", "extra_training", "health", "behavior"]
    text: str = Field(min_length=1, max_length=5000)
    written_at: datetime
    shared: bool = True


class MatchStatData(BaseModel):
    match_id: uuid.UUID
    player_id: uuid.UUID
    started: bool = False
    minutes: int = Field(default=0, ge=0, le=150)
    rating: float | None = Field(default=None, ge=1, le=10)
    stats: dict[str, float] = Field(default_factory=dict, max_length=40)

    @field_validator("stats")
    @classmethod
    def _stats(cls, v: dict[str, float]) -> dict[str, float]:
        for k, x in v.items():
            if len(k) > 40 or x < 0 or x > 9999:
                raise ValueError("bad stat")
        return v


class PhysicalTestData(BaseModel):
    player_id: uuid.UUID
    tested_on: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    results: dict[str, float] = Field(default_factory=dict, max_length=30)
    notes: str = TextStr


class StaffData(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    role: Literal["head", "assistant", "goalkeeper", "fitness", "doctor", "analyst", "other"]
    phone: str = Field(default="", max_length=30)
    email: str = Field(default="", max_length=120)
    team_ids: list[uuid.UUID] = Field(default_factory=list, max_length=50)
    notes: str = TextStr


class ShareOut(BaseModel):
    token: str
    url: str


# -------------------------------------------------------------------- синхронизация

EntityName = Literal[
    "teams", "players", "drills", "favorites", "training_sessions", "attendance",
    "session_notes", "session_reports", "player_assessments",
    "matches", "schedule_slots", "development_plans", "tactic_boards", "parent_notes",
    "match_stats", "physical_tests", "staff",
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
