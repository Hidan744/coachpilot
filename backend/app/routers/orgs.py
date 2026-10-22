"""Футбольная школа: тренеры, роли, сводка по командам, передача команды другому тренеру.

Данные остаются у тренера-владельца; руководитель видит сводные показатели по командам школы,
а не карточки детей. Одна школа не видит другую: каждый запрос проверяет членство на сервере.
"""

import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.audit import audit
from app.db import get_db
from app.security import current_user
from app.sync import REGISTRY

router = APIRouter(prefix="/orgs", tags=["orgs"])

MANAGERS = {"owner", "admin"}
VIEWERS = {"owner", "admin", "head_coach"}


class OrgIn(BaseModel):
    name: str = Field(min_length=1, max_length=150)


class OrgInviteIn(BaseModel):
    role: Literal["admin", "head_coach", "coach"] = "coach"


class JoinIn(BaseModel):
    code: str


class TransferIn(BaseModel):
    team_id: uuid.UUID
    to_user_id: uuid.UUID


async def _member(db: AsyncSession, org_id: uuid.UUID, user: m.User, roles: set[str] | None = None) -> m.OrgMember:
    mem = await db.get(m.OrgMember, (org_id, user.id))
    if mem is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Школа не найдена")
    if roles is not None and mem.role not in roles:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Недостаточно прав")
    return mem


@router.post("")
async def create(body: OrgIn, request: Request, user: m.User = Depends(current_user),
                 db: AsyncSession = Depends(get_db)) -> dict:
    org = m.Organization(name=body.name.strip())
    db.add(org)
    await db.flush()
    db.add(m.OrgMember(org_id=org.id, user_id=user.id, role="owner"))
    await audit(db, user.id, "org_created", request, org_id=org.id)
    await db.commit()
    return {"id": str(org.id), "name": org.name, "role": "owner"}


@router.get("/mine")
async def mine(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> list[dict]:
    rows = await db.execute(select(m.Organization, m.OrgMember).join(m.OrgMember)
                            .where(m.OrgMember.user_id == user.id))
    return [{"id": str(o.id), "name": o.name, "role": mem.role} for o, mem in rows]


@router.post("/{org_id}/invites")
async def create_invite(org_id: uuid.UUID, body: OrgInviteIn, user: m.User = Depends(current_user),
                        db: AsyncSession = Depends(get_db)) -> dict:
    await _member(db, org_id, user, MANAGERS)
    code = secrets.token_hex(4).upper()
    db.add(m.OrgInvite(code=code, org_id=org_id, role=body.role, expires_at=datetime.now(UTC) + timedelta(days=7)))
    await db.commit()
    return {"code": code, "role": body.role, "expires_days": 7}


@router.post("/join")
async def join(body: JoinIn, request: Request, user: m.User = Depends(current_user),
               db: AsyncSession = Depends(get_db)) -> dict:
    inv = await db.get(m.OrgInvite, body.code.strip().upper()[:40])
    if inv is None or inv.expires_at < datetime.now(UTC):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Код не найден или устарел")
    if await db.get(m.OrgMember, (inv.org_id, user.id)) is None:
        db.add(m.OrgMember(org_id=inv.org_id, user_id=user.id, role=inv.role))
    await db.delete(inv)
    await audit(db, user.id, "org_joined", request, org_id=inv.org_id, role=inv.role)
    await db.commit()
    return {"org_id": str(inv.org_id), "role": inv.role}


@router.get("/{org_id}/members")
async def members(org_id: uuid.UUID, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> list:
    await _member(db, org_id, user)
    rows = await db.execute(select(m.OrgMember, m.User).join(m.User).where(m.OrgMember.org_id == org_id))
    return [{"user_id": str(u.id), "name": u.name, "email": u.email, "role": mem.role} for mem, u in rows]


@router.delete("/{org_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(org_id: uuid.UUID, user_id: uuid.UUID, user: m.User = Depends(current_user),
                        db: AsyncSession = Depends(get_db)) -> None:
    await _member(db, org_id, user, MANAGERS)
    target = await db.get(m.OrgMember, (org_id, user_id))
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Не участник школы")
    if target.role == "owner":
        raise HTTPException(status.HTTP_409_CONFLICT, "Владельца школы удалить нельзя")
    await db.delete(target)
    await db.commit()


@router.get("/{org_id}/overview")
async def overview(org_id: uuid.UUID, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    """Сводка по командам тренеров школы за 28 дней: игроки, занятия, отчёты, посещаемость."""
    await _member(db, org_id, user, VIEWERS)
    since = datetime.now(UTC) - timedelta(days=28)
    org = await db.get(m.Organization, org_id)
    teams_out = []
    for mem, coach in await db.execute(select(m.OrgMember, m.User).join(m.User).where(m.OrgMember.org_id == org_id)):
        for t in await db.scalars(select(m.Team).where(m.Team.owner_id == coach.id, m.Team.deleted_at.is_(None))):
            players = (await db.scalars(select(m.Player.id).where(
                m.Player.team_id == t.id, m.Player.deleted_at.is_(None), m.Player.active.is_(True)))).all()
            sessions = (await db.scalars(select(m.TrainingSession).where(
                m.TrainingSession.team_id == t.id, m.TrainingSession.deleted_at.is_(None),
                m.TrainingSession.status == "done", m.TrainingSession.scheduled_at >= since))).all()
            ids = [s.id for s in sessions]
            reports = 0 if not ids else len((await db.scalars(select(m.SessionReport.id).where(
                m.SessionReport.session_id.in_(ids), m.SessionReport.coach_confirmed.is_(True),
                m.SessionReport.deleted_at.is_(None)))).all())
            att = [] if not ids else (await db.scalars(select(m.Attendance.status).where(
                m.Attendance.session_id.in_(ids), m.Attendance.deleted_at.is_(None)))).all()
            marked = [a for a in att if a != "excused"]
            teams_out.append({
                "team_id": str(t.id), "team": t.name, "age_group": t.age_group,
                "coach": coach.name, "coach_id": str(coach.id), "coach_role": mem.role,
                "players": len(players), "sessions_28d": len(sessions),
                "reports_filled_pct": round(reports * 100 / len(sessions)) if sessions else None,
                "attendance_pct": round(sum(1 for a in marked if a in ("present", "late")) * 100 / len(marked))
                if marked else None,
            })
    return {"org": org.name, "period_days": 28, "teams": teams_out}


@router.post("/{org_id}/transfer")
async def transfer_team(org_id: uuid.UUID, body: TransferIn, request: Request,
                        user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    """Передать команду со всеми данными другому тренеру школы."""
    await _member(db, org_id, user, MANAGERS)
    team = await db.get(m.Team, body.team_id)
    if team is None or team.deleted_at is not None or await db.get(m.OrgMember, (org_id, team.owner_id)) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Команда не найдена в школе")
    if await db.get(m.OrgMember, (org_id, body.to_user_id)) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Тренер не состоит в школе")
    old, new = team.owner_id, body.to_user_id
    if old == new:
        return {"moved": 0}
    # Всё, что относится к команде: игроки, занятия, матчи и всё, что ссылается на них.
    players = set((await db.scalars(select(m.Player.id).where(m.Player.team_id == team.id,
                                                              m.Player.owner_id == old))).all())
    sessions = set((await db.scalars(select(m.TrainingSession.id).where(m.TrainingSession.team_id == team.id,
                                                                        m.TrainingSession.owner_id == old))).all())
    matches = set((await db.scalars(select(m.Match.id).where(m.Match.team_id == team.id,
                                                             m.Match.owner_id == old))).all())
    by_entity: dict[str, tuple] = {
        "teams": (m.Team.id, {team.id}),
        "players": (m.Player.id, players),
        "training_sessions": (m.TrainingSession.id, sessions),
        "matches": (m.Match.id, matches),
        "schedule_slots": (m.ScheduleSlot.team_id, {team.id}),
        "tactic_boards": (m.TacticBoard.team_id, {team.id}),
        "advice_decisions": (m.AdviceDecision.team_id, {team.id}),
        "attendance": (m.Attendance.session_id, sessions),
        "session_notes": (m.SessionNote.session_id, sessions),
        "session_reports": (m.SessionReport.session_id, sessions),
        "player_assessments": (m.PlayerAssessment.player_id, players),
        "development_plans": (m.DevelopmentPlan.player_id, players),
        "parent_notes": (m.ParentNote.player_id, players),
        "physical_tests": (m.PhysicalTest.player_id, players),
        "match_stats": (m.MatchStat.match_id, matches),
    }
    moved = 0
    for entity, (col, ids) in by_entity.items():
        if not ids:
            continue
        model = REGISTRY[entity].model
        rows = (await db.scalars(select(model).where(col.in_(ids), model.owner_id == old))).all()
        for row in rows:
            seq = await db.scalar(select(m.sync_seq.next_value()))
            db.add(m.OwnershipMove(old_owner=old, entity=entity, record_id=row.id, seq=seq))
            row.owner_id = new
            row.server_seq = await db.scalar(select(m.sync_seq.next_value()))
            moved += 1
    await db.execute(update(m.PlayerShare).where(m.PlayerShare.player_id.in_(players or {uuid.uuid4()}),
                                                 m.PlayerShare.owner_id == old).values(owner_id=new))
    await db.execute(update(m.FamilyLink).where(m.FamilyLink.player_id.in_(players or {uuid.uuid4()}),
                                                m.FamilyLink.owner_id == old).values(owner_id=new))
    await audit(db, user.id, "team_transferred", request, team_id=team.id, from_user=old, to_user=new)
    await db.commit()
    return {"moved": moved}
