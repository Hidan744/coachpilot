"""ORM-модели.

Синхронизируемые сущности наследуют SyncMixin: клиент сам генерирует UUID,
а сервер при каждой записи присваивает `server_seq` из глобальной последовательности.
По `server_seq` клиент инкрементально забирает изменения (`/sync/pull`).
Удаление мягкое (`deleted_at`), чтобы удаление дошло до других устройств.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    Sequence,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, declared_attr, mapped_column

from app.db import Base

sync_seq = Sequence("sync_seq", metadata=Base.metadata)


def _uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


def _now_col(**kw) -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now(), **kw)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = _uuid_pk()
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    name: Mapped[str] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(20), default="coach")
    # Профиль тренера
    city: Mapped[str | None] = mapped_column(String(100))
    coaching_level: Mapped[str | None] = mapped_column(String(50))
    consent_version: Mapped[str] = mapped_column(String(20))
    consent_at: Mapped[datetime] = _now_col()
    created_at: Mapped[datetime] = _now_col()
    updated_at: Mapped[datetime] = _now_col(onupdate=func.now())


class Club(Base):
    """Задел под клубную версию; в MVP не используется в интерфейсе."""

    __tablename__ = "clubs"

    id: Mapped[uuid.UUID] = _uuid_pk()
    name: Mapped[str] = mapped_column(String(150))
    created_at: Mapped[datetime] = _now_col()


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _now_col()


class Subscription(Base):
    __tablename__ = "subscriptions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    plan: Mapped[str] = mapped_column(String(20), default="free")
    status: Mapped[str] = mapped_column(String(20), default="active")
    ai_quota_month: Mapped[int] = mapped_column(Integer, default=10)
    ai_used: Mapped[int] = mapped_column(Integer, default=0)
    period_start: Mapped[datetime] = _now_col()


class AIRequest(Base):
    """Журнал AI-операций. Персональные данные игроков сюда не пишем."""

    __tablename__ = "ai_requests"

    id: Mapped[uuid.UUID] = _uuid_pk()
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    kind: Mapped[str] = mapped_column(String(30))
    provider: Mapped[str] = mapped_column(String(30))
    model: Mapped[str] = mapped_column(String(60))
    tokens_in: Mapped[int] = mapped_column(Integer, default=0)
    tokens_out: Mapped[int] = mapped_column(Integer, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    attempts: Mapped[int] = mapped_column(Integer, default=1)
    valid: Mapped[bool] = mapped_column(Boolean, default=False)
    error: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = _now_col()


class Event(Base):
    """Продуктовая аналитика и ошибки клиента. Хранится у себя (152-ФЗ), без сторонних SDK."""

    __tablename__ = "events"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    name: Mapped[str] = mapped_column(String(50), index=True)
    props: Mapped[dict] = mapped_column(JSONB, default=dict)
    platform: Mapped[str] = mapped_column(String(20), default="")
    app_version: Mapped[str] = mapped_column(String(20), default="")
    client_ts: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _now_col()


# ---------------------------------------------------------------- синхронизируемые


class SyncMixin:
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)

    @declared_attr
    def owner_id(cls) -> Mapped[uuid.UUID]:
        return mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    @declared_attr
    def club_id(cls) -> Mapped[uuid.UUID | None]:
        return mapped_column(ForeignKey("clubs.id", ondelete="SET NULL"), nullable=True)

    server_seq: Mapped[int] = mapped_column(BigInteger, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    @declared_attr.directive
    def __table_args__(cls):
        return (Index(f"ix_{cls.__tablename__}_owner_seq", "owner_id", "server_seq"),)


class Team(SyncMixin, Base):
    __tablename__ = "teams"

    name: Mapped[str] = mapped_column(String(100))
    age_group: Mapped[str] = mapped_column(String(20))
    level: Mapped[str] = mapped_column(String(30))
    default_players: Mapped[int] = mapped_column(Integer)
    field_type: Mapped[str | None] = mapped_column(String(30))
    equipment: Mapped[list] = mapped_column(JSONB, default=list)
    notes: Mapped[str] = mapped_column(Text, default="")
    formation: Mapped[str] = mapped_column(String(20), default="", server_default="")
    season_goals: Mapped[list] = mapped_column(JSONB, default=list, server_default="[]")


class Player(SyncMixin, Base):
    __tablename__ = "players"

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"))
    first_name: Mapped[str] = mapped_column(String(60))
    last_name: Mapped[str] = mapped_column(String(60), default="")
    birth_year: Mapped[int | None] = mapped_column(Integer)
    position: Mapped[str | None] = mapped_column(String(30))
    number: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str] = mapped_column(Text, default="")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    dominant_foot: Mapped[str | None] = mapped_column(String(10))
    level: Mapped[str | None] = mapped_column(String(30))
    strengths: Mapped[str] = mapped_column(Text, default="", server_default="")
    weaknesses: Mapped[str] = mapped_column(Text, default="", server_default="")
    goals: Mapped[str] = mapped_column(Text, default="", server_default="")


class Drill(SyncMixin, Base):
    """Упражнение. owner_id = NULL — системная библиотека (раздаётся через /catalog)."""

    __tablename__ = "drills"

    @declared_attr
    def owner_id(cls) -> Mapped[uuid.UUID | None]:
        return mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=True)

    source: Mapped[str] = mapped_column(String(10))  # system | user | ai
    title: Mapped[str] = mapped_column(String(150))
    category: Mapped[str] = mapped_column(String(30))
    goal: Mapped[str] = mapped_column(Text, default="")
    age_min: Mapped[int] = mapped_column(Integer, default=6)
    age_max: Mapped[int] = mapped_column(Integer, default=99)
    players_min: Mapped[int] = mapped_column(Integer, default=1)
    players_max: Mapped[int] = mapped_column(Integer, default=30)
    duration_min: Mapped[int] = mapped_column(Integer, default=10)
    field_size: Mapped[str] = mapped_column(String(50), default="")
    intensity: Mapped[str] = mapped_column(String(10), default="medium")
    equipment: Mapped[list] = mapped_column(JSONB, default=list)
    setup: Mapped[str] = mapped_column(Text, default="")
    steps: Mapped[list] = mapped_column(JSONB, default=list)
    rules: Mapped[list] = mapped_column(JSONB, default=list)
    coaching_points: Mapped[list] = mapped_column(JSONB, default=list)
    success_criteria: Mapped[list] = mapped_column(JSONB, default=list)
    variants: Mapped[dict] = mapped_column(JSONB, default=dict)  # {"easier": [], "harder": []}
    scheme: Mapped[dict | None] = mapped_column(JSONB)
    tags: Mapped[list] = mapped_column(JSONB, default=list)


class Favorite(SyncMixin, Base):
    __tablename__ = "favorites"

    drill_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("drills.id", ondelete="CASCADE"))


class TrainingSession(SyncMixin, Base):
    """Тренировка. План (блоки) хранится документом в `blocks`, чтобы правка плана
    была атомарной и конфликт разрешался целиком по занятию."""

    __tablename__ = "training_sessions"

    team_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("teams.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(150))
    scheduled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    goal: Mapped[str] = mapped_column(Text, default="")
    duration_min: Mapped[int] = mapped_column(Integer)
    players_expected: Mapped[int | None] = mapped_column(Integer)
    field_type: Mapped[str | None] = mapped_column(String(30))
    equipment: Mapped[list] = mapped_column(JSONB, default=list)
    status: Mapped[str] = mapped_column(String(20), default="draft")
    ai_generated: Mapped[bool] = mapped_column(Boolean, default=False)
    ai_assumptions: Mapped[list] = mapped_column(JSONB, default=list)
    blocks: Mapped[list] = mapped_column(JSONB, default=list)
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    actual: Mapped[dict] = mapped_column(JSONB, default=dict)
    conflict_of: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    # Параметры конструктора (формат, интенсивность, позиции, уровень) — для пересборки плана.
    params: Mapped[dict] = mapped_column(JSONB, default=dict, server_default="{}")


class Attendance(SyncMixin, Base):
    """id на клиенте = uuid5(session_id, player_id), поэтому две отметки одного
    игрока на одном занятии с разных устройств сходятся в одну запись."""

    __tablename__ = "attendance"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("training_sessions.id", ondelete="CASCADE")
    )
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(10))


class SessionNote(SyncMixin, Base):
    __tablename__ = "session_notes"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("training_sessions.id", ondelete="CASCADE")
    )
    block_id: Mapped[str | None] = mapped_column(String(64))
    text: Mapped[str] = mapped_column(Text)
    noted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SessionReport(SyncMixin, Base):
    __tablename__ = "session_reports"

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("training_sessions.id", ondelete="CASCADE")
    )
    raw_input: Mapped[str] = mapped_column(Text, default="")
    rating: Mapped[int | None] = mapped_column(Integer)
    went_well: Mapped[str] = mapped_column(Text, default="")
    to_improve: Mapped[str] = mapped_column(Text, default="")
    observations: Mapped[str] = mapped_column(Text, default="")
    # Предложения модели хранятся отдельно от наблюдений тренера.
    ai_suggestions: Mapped[list] = mapped_column(JSONB, default=list)
    coach_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Субъективная нагрузка занятия (RPE 1–10): нагрузка = RPE × минуты.
    rpe: Mapped[int | None] = mapped_column(Integer)
    player_notes: Mapped[dict] = mapped_column(JSONB, default=dict, server_default="{}")
    next_time: Mapped[str] = mapped_column(Text, default="", server_default="")


class PlayerAssessment(SyncMixin, Base):
    __tablename__ = "player_assessments"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("training_sessions.id", ondelete="SET NULL")
    )
    skill: Mapped[str] = mapped_column(String(40))
    score: Mapped[int] = mapped_column(Integer)
    comment: Mapped[str] = mapped_column(Text, default="")
    assessed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Match(SyncMixin, Base):
    """Матч в календаре сезона."""

    __tablename__ = "matches"

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"))
    opponent: Mapped[str] = mapped_column(String(100))
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_min: Mapped[int] = mapped_column(Integer, default=90)
    home: Mapped[bool] = mapped_column(Boolean, default=True)
    venue: Mapped[str] = mapped_column(String(150), default="")
    competition: Mapped[str] = mapped_column(String(100), default="")
    status: Mapped[str] = mapped_column(String(20), default="scheduled")
    score_for: Mapped[int | None] = mapped_column(Integer)
    score_against: Mapped[int | None] = mapped_column(Integer)
    notes: Mapped[str] = mapped_column(Text, default="")


class ScheduleSlot(SyncMixin, Base):
    """Регулярная тренировка: дни недели и время, действует в пределах дат сезона."""

    __tablename__ = "schedule_slots"

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(100))
    weekdays: Mapped[list] = mapped_column(JSONB, default=list)  # 1 = понедельник … 7 = воскресенье
    start_time: Mapped[str] = mapped_column(String(5))  # HH:MM
    duration_min: Mapped[int] = mapped_column(Integer, default=90)
    location: Mapped[str] = mapped_column(String(150), default="")
    valid_from: Mapped[str | None] = mapped_column(String(10))  # YYYY-MM-DD
    valid_to: Mapped[str | None] = mapped_column(String(10))
    notes: Mapped[str] = mapped_column(Text, default="")


class DevelopmentPlan(SyncMixin, Base):
    """Индивидуальный план развития игрока на неделю, месяц или сезон."""

    __tablename__ = "development_plans"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    period: Mapped[str] = mapped_column(String(10))
    title: Mapped[str] = mapped_column(String(150))
    starts_on: Mapped[str | None] = mapped_column(String(10))
    ends_on: Mapped[str | None] = mapped_column(String(10))
    focus: Mapped[list] = mapped_column(JSONB, default=list)
    items: Mapped[list] = mapped_column(JSONB, default=list)  # [{text, kind: goal|task, done}]
    comment: Mapped[str] = mapped_column(Text, default="")
    shared: Mapped[bool] = mapped_column(Boolean, default=True)
    # Программа на 4–6 недель: ключевая цель и показатели «сейчас → цель».
    key_goal: Mapped[str] = mapped_column(Text, default="", server_default="")
    targets: Mapped[list] = mapped_column(JSONB, default=list, server_default="[]")
    weeks: Mapped[list] = mapped_column(JSONB, default=list, server_default="[]")


class TacticBoard(SyncMixin, Base):
    """Тактическая доска: расстановка и движения на схеме поля."""

    __tablename__ = "tactic_boards"

    team_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("teams.id", ondelete="SET NULL"))
    match_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("matches.id", ondelete="SET NULL"))
    title: Mapped[str] = mapped_column(String(150))
    formation: Mapped[str] = mapped_column(String(20), default="")
    scheme: Mapped[dict] = mapped_column(JSONB, default=dict)
    notes: Mapped[str] = mapped_column(Text, default="")


class ParentNote(SyncMixin, Base):
    """Сообщение тренера родителям об игроке: питание, психология, доп. тренировки и т.п."""

    __tablename__ = "parent_notes"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    category: Mapped[str] = mapped_column(String(20))
    text: Mapped[str] = mapped_column(Text)
    written_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    shared: Mapped[bool] = mapped_column(Boolean, default=True)


class PlayerShare(Base):
    """Ссылка для игрока и родителей: страница только для чтения без входа в приложение."""

    __tablename__ = "player_shares"

    token: Mapped[str] = mapped_column(String(64), primary_key=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = _now_col()
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MatchStat(SyncMixin, Base):
    """Статистика игрока в матче. id на клиенте = uuid5(match_id, player_id)."""

    __tablename__ = "match_stats"

    match_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("matches.id", ondelete="CASCADE"))
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    started: Mapped[bool] = mapped_column(Boolean, default=False)
    minutes: Mapped[int] = mapped_column(Integer, default=0)
    rating: Mapped[float | None] = mapped_column(Float)
    stats: Mapped[dict] = mapped_column(JSONB, default=dict)  # голы, передачи, отборы…


class PhysicalTest(SyncMixin, Base):
    """Тестирование ОФП игрока: результаты по тестам на дату."""

    __tablename__ = "physical_tests"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"))
    tested_on: Mapped[str] = mapped_column(String(10))  # YYYY-MM-DD
    results: Mapped[dict] = mapped_column(JSONB, default=dict)
    notes: Mapped[str] = mapped_column(Text, default="")


class StaffMember(SyncMixin, Base):
    """Тренерский штаб: ассистенты, тренер вратарей, тренер по ОФП, врач."""

    __tablename__ = "staff"

    name: Mapped[str] = mapped_column(String(100))
    role: Mapped[str] = mapped_column(String(30))
    phone: Mapped[str] = mapped_column(String(30), default="")
    email: Mapped[str] = mapped_column(String(120), default="")
    team_ids: Mapped[list] = mapped_column(JSONB, default=list)
    notes: Mapped[str] = mapped_column(Text, default="")


class AdviceDecision(SyncMixin, Base):
    """Решение тренера по рекомендации: принять, отклонить или изменить (своя формулировка действия)."""

    __tablename__ = "advice_decisions"

    team_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("teams.id", ondelete="CASCADE"))
    key: Mapped[str] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(String(10))
    note: Mapped[str] = mapped_column(Text, default="")
    title: Mapped[str] = mapped_column(String(300), default="")
    decided_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
