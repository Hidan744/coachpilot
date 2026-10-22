"""Движок синхронизации: применение изменений с клиента и выдача изменений клиенту.

Правила конфликтов:
* `lww` — последняя запись побеждает (команды, игроки, заметки, посещаемость...).
* `strict` — если запись изменилась на сервере после версии клиента (`base_seq`),
  изменение не применяется, клиенту возвращается серверная версия, а он сохраняет
  свою правку копией. Так ведут себя план тренировки, отчёт и свои упражнения:
  молча терять правки тренера в них нельзя.
* Удаление побеждает правку: правка удалённой записи возвращается как конфликт.

Все записи одного владельца сериализуются advisory-блокировкой, поэтому порядок
`server_seq` внутри владельца совпадает с порядком коммитов и курсор pull
не пропускает изменений.
"""

import hashlib
import json
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Literal

from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, ValidationError
from sqlalchemy import or_, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app import schemas as s


@dataclass(frozen=True)
class EntitySpec:
    model: type[m.Base]
    schema: type[BaseModel]
    policy: Literal["lww", "strict"] = "lww"
    # поле -> (модель-цель, разрешены ли системные записи без владельца)
    refs: dict[str, tuple[type[m.Base], bool]] = field(default_factory=dict)


REGISTRY: dict[str, EntitySpec] = {
    "teams": EntitySpec(m.Team, s.TeamData),
    "players": EntitySpec(m.Player, s.PlayerData, refs={"team_id": (m.Team, False)}),
    "drills": EntitySpec(m.Drill, s.DrillData, policy="strict"),
    "favorites": EntitySpec(m.Favorite, s.FavoriteData, refs={"drill_id": (m.Drill, True)}),
    "training_sessions": EntitySpec(
        m.TrainingSession, s.TrainingSessionData, policy="strict",
        refs={"team_id": (m.Team, False)},
    ),
    "attendance": EntitySpec(
        m.Attendance, s.AttendanceData,
        refs={"session_id": (m.TrainingSession, False), "player_id": (m.Player, False)},
    ),
    "session_notes": EntitySpec(
        m.SessionNote, s.SessionNoteData, refs={"session_id": (m.TrainingSession, False)}
    ),
    "session_reports": EntitySpec(
        m.SessionReport, s.SessionReportData, policy="strict",
        refs={"session_id": (m.TrainingSession, False)},
    ),
    "player_assessments": EntitySpec(
        m.PlayerAssessment, s.PlayerAssessmentData,
        refs={"player_id": (m.Player, False), "session_id": (m.TrainingSession, False)},
    ),
    "matches": EntitySpec(m.Match, s.MatchData, refs={"team_id": (m.Team, False)}),
    "schedule_slots": EntitySpec(m.ScheduleSlot, s.ScheduleSlotData, refs={"team_id": (m.Team, False)}),
    "development_plans": EntitySpec(
        m.DevelopmentPlan, s.DevelopmentPlanData, refs={"player_id": (m.Player, False)}
    ),
    "tactic_boards": EntitySpec(
        m.TacticBoard, s.TacticBoardData,
        refs={"team_id": (m.Team, False), "match_id": (m.Match, False), "session_id": (m.TrainingSession, False)},
    ),
    "parent_notes": EntitySpec(m.ParentNote, s.ParentNoteData, refs={"player_id": (m.Player, False)}),
    "match_stats": EntitySpec(
        m.MatchStat, s.MatchStatData, refs={"match_id": (m.Match, False), "player_id": (m.Player, False)}
    ),
    "physical_tests": EntitySpec(m.PhysicalTest, s.PhysicalTestData, refs={"player_id": (m.Player, False)}),
    "staff": EntitySpec(m.StaffMember, s.StaffData),
    "advice_decisions": EntitySpec(m.AdviceDecision, s.AdviceDecisionData, refs={"team_id": (m.Team, False)}),
}


def to_record(entity: str, row) -> s.SyncRecord:
    spec = REGISTRY[entity]
    data = {name: getattr(row, name) for name in spec.schema.model_fields}
    return s.SyncRecord(
        entity=entity,
        id=row.id,
        server_seq=row.server_seq,
        updated_at=row.updated_at,
        deleted=row.deleted_at is not None,
        data=jsonable_encoder(data),
    )


async def _next_seq(db: AsyncSession) -> int:
    return await db.scalar(select(m.sync_seq.next_value()))


async def _check_refs(db: AsyncSession, spec: EntitySpec, data: BaseModel, owner_id) -> str | None:
    for name, (target, allow_system) in spec.refs.items():
        ref_id = getattr(data, name)
        if ref_id is None:
            continue
        owner_cond = target.owner_id == owner_id
        if allow_system:
            owner_cond = or_(owner_cond, target.owner_id.is_(None))
        exists = await db.scalar(select(target.id).where(target.id == ref_id, owner_cond))
        if exists is None:
            return f"invalid_reference:{name}"
    return None


async def _apply_one(db: AsyncSession, owner_id: uuid.UUID, ch: s.Change) -> s.ChangeResult:
    spec = REGISTRY[ch.entity]
    model = spec.model
    res = s.ChangeResult(entity=ch.entity, id=ch.id, status="applied")

    row = await db.scalar(select(model).where(model.id == ch.id).with_for_update())
    if row is not None and row.owner_id != owner_id:
        # Не раскрываем, что запись с таким id существует у другого пользователя.
        return res.model_copy(update={"status": "rejected", "error": "not_found"})

    def conflict() -> s.ChangeResult:
        return res.model_copy(
            update={"status": "conflict", "server_seq": row.server_seq,
                    "server_record": to_record(ch.entity, row)}
        )

    stale = (
        row is not None
        and spec.policy == "strict"
        and (ch.base_seq is None or row.server_seq > ch.base_seq)
    )
    now = datetime.now(UTC)

    if ch.op == "delete":
        if row is None:
            return res
        if row.deleted_at is not None:
            return res.model_copy(update={"server_seq": row.server_seq})
        if stale:
            return conflict()
        row.deleted_at = now
        row.updated_at = now
        row.server_seq = await _next_seq(db)
        return res.model_copy(update={"server_seq": row.server_seq})

    try:
        data = spec.schema.model_validate(ch.data or {})
    except ValidationError as e:
        first = e.errors()[0]
        loc = ".".join(str(p) for p in first["loc"])
        return res.model_copy(update={"status": "rejected", "error": f"validation:{loc}"})

    if row is not None and row.deleted_at is not None:
        return conflict()
    if stale:
        return conflict()

    ref_error = await _check_refs(db, spec, data, owner_id)
    if ref_error:
        return res.model_copy(update={"status": "rejected", "error": ref_error})

    values = data.model_dump(mode="python")
    # Вложенные pydantic-структуры (блоки, схема) кладём в JSONB как JSON-совместимые.
    for k, v in values.items():
        if isinstance(v, list | dict):
            values[k] = jsonable_encoder(v)

    if row is None:
        row = model(id=ch.id, owner_id=owner_id, **values)
        db.add(row)
    else:
        for k, v in values.items():
            setattr(row, k, v)
    row.updated_at = now
    row.server_seq = await _next_seq(db)
    await db.flush()
    return res.model_copy(update={"server_seq": row.server_seq})


async def push(db: AsyncSession, owner_id: uuid.UUID, changes: list[s.Change]) -> list[s.ChangeResult]:
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:k))"), {"k": f"sync:{owner_id}"}
    )
    results = []
    for ch in changes:
        try:
            async with db.begin_nested():
                results.append(await _apply_one(db, owner_id, ch))
        except IntegrityError:
            results.append(
                s.ChangeResult(entity=ch.entity, id=ch.id, status="rejected", error="integrity")
            )
    await db.commit()
    return results


async def pull(db: AsyncSession, owner_id: uuid.UUID, since: int, limit: int) -> s.PullOut:
    collected: list[tuple[int, str, object]] = []
    for entity, spec in REGISTRY.items():
        model = spec.model
        rows = await db.scalars(
            select(model)
            .where(model.owner_id == owner_id, model.server_seq > since)
            .order_by(model.server_seq)
            .limit(limit + 1)
        )
        collected.extend((r.server_seq, entity, r) for r in rows)
    collected.sort(key=lambda t: t[0])
    has_more = len(collected) > limit
    page = collected[:limit]
    records = [to_record(entity, row) for _, entity, row in page]
    cursor = page[-1][0] if page else since
    return s.PullOut(records=records, cursor=cursor, has_more=has_more)


async def export_all(db: AsyncSession, owner_id: uuid.UUID) -> dict[str, list[dict]]:
    out = {}
    for entity, spec in REGISTRY.items():
        rows = await db.scalars(
            select(spec.model)
            .where(spec.model.owner_id == owner_id, spec.model.deleted_at.is_(None))
            .order_by(spec.model.created_at)
        )
        out[entity] = [to_record(entity, r).model_dump(mode="json") for r in rows]
    return out


async def system_catalog(db: AsyncSession) -> tuple[str, list[dict]]:
    """Системная библиотека и её версия — хеш содержимого.

    Хеш не зависит от счётчиков конкретной БД, поэтому каталог, встроенный
    в приложение, корректно сравнивается с каталогом любого сервера."""
    rows = await db.scalars(
        select(m.Drill)
        .where(m.Drill.owner_id.is_(None), m.Drill.deleted_at.is_(None))
        .order_by(m.Drill.id)
    )
    drills = [to_record("drills", r).model_dump(mode="json") for r in rows]
    digest = hashlib.sha256()
    for d in drills:
        digest.update(json.dumps([d["id"], d["data"]], ensure_ascii=False, sort_keys=True).encode())
    return (digest.hexdigest()[:16] if drills else ""), drills
