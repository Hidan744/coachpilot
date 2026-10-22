"""Кабинеты родителя и игрока.

Тренер выдаёт одноразовый код к карточке игрока; родитель или игрок вводит его в своём аккаунте.
Каждый запрос проверяет связь «аккаунт — игрок» на сервере: подставить чужой id нельзя (404).
Видно только расписание команды игрока и то, что тренер отметил «видно родителям».
"""

import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.audit import audit
from app.db import get_db
from app.routers.shares import _is_minor, _own_player
from app.security import current_user

router = APIRouter(tags=["family"])


class InviteIn(BaseModel):
    role: Literal["parent", "player"] = "parent"


class JoinIn(BaseModel):
    code: str


class RsvpIn(BaseModel):
    kind: Literal["session", "match"]
    id: uuid.UUID
    status: Literal["yes", "no", "maybe"]


# ------------------------------------------------------------------ тренер


@router.post("/players/{player_id}/invite")
async def invite(player_id: uuid.UUID, body: InviteIn, request: Request,
                 user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    player = await _own_player(db, user, player_id)
    if body.role == "parent" and await _is_minor(db, player) and not (player.parent_consent or {}).get("given"):
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Нет отметки о согласии родителя. Отметьте согласие в карточке игрока.")
    code = secrets.token_hex(4).upper()
    db.add(m.PlayerInvite(code=code, owner_id=user.id, player_id=player_id, role=body.role,
                          expires_at=datetime.now(UTC) + timedelta(days=7)))
    await audit(db, user.id, "family_invite_created", request, player_id=player_id, role=body.role)
    await db.commit()
    return {"code": code, "role": body.role, "expires_days": 7}


@router.get("/players/{player_id}/family")
async def family_of_player(player_id: uuid.UUID, user: m.User = Depends(current_user),
                           db: AsyncSession = Depends(get_db)) -> list[dict]:
    await _own_player(db, user, player_id)
    rows = await db.execute(
        select(m.FamilyLink, m.User).join(m.User, m.User.id == m.FamilyLink.user_id)
        .where(m.FamilyLink.player_id == player_id, m.FamilyLink.owner_id == user.id)
    )
    return [{"id": str(fl.id), "role": fl.role, "name": u.name, "since": fl.created_at.isoformat()} for fl, u in rows]


@router.delete("/players/{player_id}/family/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_family(player_id: uuid.UUID, link_id: uuid.UUID, request: Request,
                        user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> None:
    await _own_player(db, user, player_id)
    await db.execute(delete(m.FamilyLink).where(m.FamilyLink.id == link_id, m.FamilyLink.owner_id == user.id,
                                                m.FamilyLink.player_id == player_id))
    await audit(db, user.id, "family_link_revoked", request, player_id=player_id)
    await db.commit()


@router.get("/teams/{team_id}/rsvp")
async def team_rsvp(team_id: uuid.UUID, user: m.User = Depends(current_user),
                    db: AsyncSession = Depends(get_db)) -> dict:
    """Подтверждения на ближайшие события команды: {«session:id»: {yes, no, maybe, players: {id: статус}}}."""
    team = await db.scalar(select(m.Team).where(m.Team.id == team_id, m.Team.owner_id == user.id))
    if team is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Команда не найдена")
    players = {p.id for p in await db.scalars(select(m.Player).where(m.Player.team_id == team_id,
                                                                     m.Player.owner_id == user.id))}
    out: dict[str, dict] = {}
    if not players:
        return out
    for r in await db.scalars(select(m.Rsvp).where(m.Rsvp.player_id.in_(players))):
        e = out.setdefault(f"{r.kind}:{r.ref_id}", {"yes": 0, "no": 0, "maybe": 0, "players": {}})
        e[r.status] += 1
        e["players"][str(r.player_id)] = r.status
    return out


# ------------------------------------------------------------------ родитель и игрок


@router.post("/family/join")
async def join(body: JoinIn, request: Request, user: m.User = Depends(current_user),
               db: AsyncSession = Depends(get_db)) -> dict:
    inv = await db.get(m.PlayerInvite, body.code.strip().upper()[:40])
    if inv is None or inv.expires_at < datetime.now(UTC):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Код не найден или устарел. Попросите у тренера новый.")
    await db.execute(insert(m.FamilyLink).values(id=uuid.uuid4(), user_id=user.id, player_id=inv.player_id,
                                                 owner_id=inv.owner_id, role=inv.role).on_conflict_do_nothing())
    await db.delete(inv)
    await audit(db, user.id, "family_joined", request, player_id=inv.player_id, role=inv.role)
    await db.commit()
    return {"player_id": str(inv.player_id), "role": inv.role}


async def _link(db: AsyncSession, user: m.User, player_id: uuid.UUID) -> tuple[m.FamilyLink, m.Player]:
    link = await db.scalar(select(m.FamilyLink).where(m.FamilyLink.user_id == user.id,
                                                      m.FamilyLink.player_id == player_id))
    player = None if link is None else await db.scalar(
        select(m.Player).where(m.Player.id == player_id, m.Player.owner_id == link.owner_id,
                               m.Player.deleted_at.is_(None)))
    if link is None or player is None:
        # Чужой игрок и несуществующий — одинаковый ответ.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Игрок не найден")
    return link, player


@router.get("/family/children")
async def children(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> list[dict]:
    rows = await db.execute(
        select(m.FamilyLink, m.Player, m.Team)
        .join(m.Player, m.Player.id == m.FamilyLink.player_id)
        .join(m.Team, m.Team.id == m.Player.team_id)
        .where(m.FamilyLink.user_id == user.id, m.Player.deleted_at.is_(None))
    )
    return [{"player_id": str(p.id), "name": f"{p.first_name} {p.last_name}".strip(), "team": t.name, "role": fl.role}
            for fl, p, t in rows]


@router.get("/family/children/{player_id}")
async def child(player_id: uuid.UUID, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    link, p = await _link(db, user, player_id)
    team = await db.get(m.Team, p.team_id)
    now = datetime.now(UTC)
    rsvp = {(r.kind, r.ref_id): r.status for r in await db.scalars(select(m.Rsvp).where(m.Rsvp.player_id == p.id))}
    upcoming = []
    for s in await db.scalars(select(m.TrainingSession).where(
            m.TrainingSession.owner_id == link.owner_id, m.TrainingSession.team_id == p.team_id,
            m.TrainingSession.deleted_at.is_(None), m.TrainingSession.status.in_(["planned", "draft"]),
            m.TrainingSession.scheduled_at > now).order_by(m.TrainingSession.scheduled_at).limit(10)):
        upcoming.append({"kind": "session", "id": str(s.id), "title": s.title, "starts_at": s.scheduled_at.isoformat(),
                         "duration_min": s.duration_min, "rsvp": rsvp.get(("session", s.id))})
    for g in await db.scalars(select(m.Match).where(
            m.Match.owner_id == link.owner_id, m.Match.team_id == p.team_id, m.Match.deleted_at.is_(None),
            m.Match.status == "scheduled", m.Match.starts_at > now).order_by(m.Match.starts_at).limit(5)):
        upcoming.append({"kind": "match", "id": str(g.id), "title": f"Матч с {g.opponent}",
                         "starts_at": g.starts_at.isoformat(), "venue": g.venue, "rsvp": rsvp.get(("match", g.id))})
    upcoming.sort(key=lambda e: e["starts_at"])
    plans = await db.scalars(select(m.DevelopmentPlan).where(
        m.DevelopmentPlan.player_id == p.id, m.DevelopmentPlan.owner_id == link.owner_id,
        m.DevelopmentPlan.deleted_at.is_(None), m.DevelopmentPlan.shared.is_(True)))
    notes = await db.scalars(select(m.ParentNote).where(
        m.ParentNote.player_id == p.id, m.ParentNote.owner_id == link.owner_id, m.ParentNote.deleted_at.is_(None),
        m.ParentNote.shared.is_(True)).order_by(m.ParentNote.written_at.desc()).limit(20))
    att = list(await db.scalars(select(m.Attendance).where(m.Attendance.player_id == p.id,
                                                          m.Attendance.owner_id == link.owner_id,
                                                          m.Attendance.deleted_at.is_(None))))
    marked = [a for a in att if a.status != "excused"]
    return {
        "player": {"name": f"{p.first_name} {p.last_name}".strip(), "position": p.position, "number": p.number},
        "team": team.name if team else "",
        "role": link.role,
        "upcoming": upcoming,
        "plans": [{"title": x.title, "period": x.period, "focus": x.focus, "key_goal": x.key_goal,
                   "items": [i for i in (x.items or []) if isinstance(i, dict)],
                   "weeks": [{"n": w.get("n"), "priority": w.get("priority"), "done": w.get("done")}
                             for w in (x.weeks or []) if isinstance(w, dict)]} for x in plans],
        "notes": [{"category": n.category, "text": n.text, "written_at": n.written_at.isoformat()} for n in notes],
        "attendance": {"present": sum(1 for a in marked if a.status in ("present", "late")), "total": len(marked)},
    }


@router.post("/family/children/{player_id}/rsvp")
async def set_rsvp(player_id: uuid.UUID, body: RsvpIn, user: m.User = Depends(current_user),
                   db: AsyncSession = Depends(get_db)) -> dict:
    link, p = await _link(db, user, player_id)
    now = datetime.now(UTC)
    if body.kind == "session":
        ev = await db.scalar(select(m.TrainingSession).where(
            m.TrainingSession.id == body.id, m.TrainingSession.owner_id == link.owner_id,
            m.TrainingSession.team_id == p.team_id, m.TrainingSession.scheduled_at > now))
    else:
        ev = await db.scalar(select(m.Match).where(m.Match.id == body.id, m.Match.owner_id == link.owner_id,
                                                   m.Match.team_id == p.team_id, m.Match.starts_at > now))
    if ev is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Событие не найдено или уже прошло")
    await db.execute(insert(m.Rsvp).values(player_id=p.id, kind=body.kind, ref_id=body.id, status=body.status,
                                           by_user=user.id, at=now)
                     .on_conflict_do_update(index_elements=["player_id", "kind", "ref_id"],
                                            set_={"status": body.status, "by_user": user.id, "at": now}))
    await db.commit()
    return {"status": body.status}


@router.delete("/family/children/{player_id}", status_code=status.HTTP_204_NO_CONTENT)
async def leave(player_id: uuid.UUID, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> None:
    await db.execute(delete(m.FamilyLink).where(m.FamilyLink.user_id == user.id, m.FamilyLink.player_id == player_id))
    await db.commit()
