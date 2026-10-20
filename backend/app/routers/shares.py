"""Ссылка для игрока и родителей.

Тренер создаёт ссылку на карточку игрока; по ней без входа в приложение открывается
страница только для чтения: посещаемость, план развития, сообщения тренера, расписание.
В ссылку попадает только то, что тренер отметил «видно родителям»; ссылку можно отозвать.
"""

import html
import secrets
import uuid
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.config import get_settings
from app.db import get_db
from app.schemas import ShareOut
from app.security import current_user

router = APIRouter(tags=["shares"])

ATTENDANCE_LABELS = {
    "present": "был",
    "late": "опоздал",
    "absent": "не был",
    "injured": "травма",
    "excused": "уважительная причина",
}
CATEGORY_LABELS = {
    "general": "Общее",
    "psychology": "Психология",
    "nutrition": "Питание",
    "extra_training": "Дополнительные тренировки",
    "health": "Здоровье и восстановление",
    "behavior": "Дисциплина и поведение",
}
PERIOD_LABELS = {
    "week": "на неделю", "month": "на месяц", "season": "на сезон", "cycle4": "на 4 недели", "cycle6": "на 6 недель",
}
POSITION_LABELS = {"GK": "Вратарь", "DF": "Защитник", "MF": "Полузащитник", "FW": "Нападающий"}
SKILL_LABELS = {
    "technique": "Техника",
    "passing": "Передачи",
    "dribbling": "Дриблинг",
    "finishing": "Завершение",
    "positioning": "Позиционирование",
    "decision": "Принятие решений",
    "physical": "Физика",
    "attitude": "Отношение",
}
WEEKDAYS = ["", "пн", "вт", "ср", "чт", "пт", "сб", "вс"]
MONTHS = ["", "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
          "октября", "ноября", "декабря"]


def _url(request: Request, token: str) -> str:
    base = get_settings().public_base_url.rstrip("/") or str(request.base_url).rstrip("/")
    return f"{base}/p/{token}"


async def _own_player(db: AsyncSession, user: m.User, player_id: uuid.UUID) -> m.Player:
    player = await db.scalar(
        select(m.Player).where(
            m.Player.id == player_id, m.Player.owner_id == user.id, m.Player.deleted_at.is_(None)
        )
    )
    if player is None:
        # Игрок ещё не синхронизирован или чужой — для клиента одно и то же.
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Игрок не найден на сервере. Дождитесь синхронизации.")
    return player


@router.post("/players/{player_id}/share", response_model=ShareOut)
async def create_share(
    player_id: uuid.UUID,
    request: Request,
    user: m.User = Depends(current_user),
    db: AsyncSession = Depends(get_db),
) -> ShareOut:
    await _own_player(db, user, player_id)
    share = await db.scalar(
        select(m.PlayerShare).where(
            m.PlayerShare.player_id == player_id,
            m.PlayerShare.owner_id == user.id,
            m.PlayerShare.revoked_at.is_(None),
        )
    )
    if share is None:
        share = m.PlayerShare(token=secrets.token_urlsafe(16), owner_id=user.id, player_id=player_id)
        db.add(share)
        await db.commit()
    return ShareOut(token=share.token, url=_url(request, share.token))


@router.delete("/players/{player_id}/share", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_share(
    player_id: uuid.UUID, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> None:
    shares = await db.scalars(
        select(m.PlayerShare).where(
            m.PlayerShare.player_id == player_id,
            m.PlayerShare.owner_id == user.id,
            m.PlayerShare.revoked_at.is_(None),
        )
    )
    for sh in shares:
        sh.revoked_at = datetime.now(UTC)
    await db.commit()


def _alive(model):
    return model.deleted_at.is_(None)


async def player_card(db: AsyncSession, token: str) -> dict | None:
    """Данные страницы для родителей. None — ссылки нет, она отозвана или игрок удалён."""
    share = await db.scalar(
        select(m.PlayerShare).where(m.PlayerShare.token == token, m.PlayerShare.revoked_at.is_(None))
    )
    if share is None:
        return None
    owner = share.owner_id
    player = await db.scalar(
        select(m.Player).where(m.Player.id == share.player_id, m.Player.owner_id == owner, _alive(m.Player))
    )
    if player is None:
        return None
    team = await db.scalar(select(m.Team).where(m.Team.id == player.team_id, _alive(m.Team)))
    coach = await db.get(m.User, owner)

    rows = (
        await db.execute(
            select(m.Attendance, m.TrainingSession)
            .join(m.TrainingSession, m.TrainingSession.id == m.Attendance.session_id)
            .where(
                m.Attendance.player_id == player.id,
                m.Attendance.owner_id == owner,
                _alive(m.Attendance),
                _alive(m.TrainingSession),
            )
        )
    ).all()
    visits = sorted(
        (
            {
                "date": (s.started_at or s.scheduled_at or s.finished_at or a.updated_at),
                "title": s.title,
                "status": a.status,
            }
            for a, s in rows
        ),
        key=lambda v: v["date"],
        reverse=True,
    )
    total = len(visits)
    present = sum(1 for v in visits if v["status"] in ("present", "late"))

    plans = (
        await db.scalars(
            select(m.DevelopmentPlan)
            .where(
                m.DevelopmentPlan.player_id == player.id,
                m.DevelopmentPlan.owner_id == owner,
                m.DevelopmentPlan.shared.is_(True),
                _alive(m.DevelopmentPlan),
            )
            .order_by(m.DevelopmentPlan.updated_at.desc())
        )
    ).all()
    notes = (
        await db.scalars(
            select(m.ParentNote)
            .where(
                m.ParentNote.player_id == player.id,
                m.ParentNote.owner_id == owner,
                m.ParentNote.shared.is_(True),
                _alive(m.ParentNote),
            )
            .order_by(m.ParentNote.written_at.desc())
            .limit(30)
        )
    ).all()
    assessments = (
        await db.scalars(
            select(m.PlayerAssessment)
            .where(
                m.PlayerAssessment.player_id == player.id,
                m.PlayerAssessment.owner_id == owner,
                _alive(m.PlayerAssessment),
            )
            .order_by(m.PlayerAssessment.assessed_at.desc())
        )
    ).all()
    skills: dict[str, int] = {}
    for a in assessments:
        skills.setdefault(a.skill, a.score)

    now = datetime.now(UTC)
    matches = (
        await db.scalars(
            select(m.Match)
            .where(
                m.Match.team_id == player.team_id,
                m.Match.owner_id == owner,
                m.Match.starts_at >= now - timedelta(hours=3),
                m.Match.starts_at <= now + timedelta(days=45),
                m.Match.status != "cancelled",
                _alive(m.Match),
            )
            .order_by(m.Match.starts_at)
            .limit(10)
        )
    ).all()
    today = datetime.now(ZoneInfo(get_settings().display_tz)).date().isoformat()
    slots = [
        s
        for s in (
            await db.scalars(
                select(m.ScheduleSlot).where(
                    m.ScheduleSlot.team_id == player.team_id,
                    m.ScheduleSlot.owner_id == owner,
                    _alive(m.ScheduleSlot),
                )
            )
        ).all()
        if (s.valid_to is None or s.valid_to >= today)
    ]

    return {
        "player": {
            "name": f"{player.first_name} {player.last_name}".strip(),
            "number": player.number,
            "position": POSITION_LABELS.get(player.position or "", player.position),
            "birth_year": player.birth_year,
        },
        "team": team.name if team else "",
        "coach": coach.name if coach else "",
        "attendance": {
            "total": total,
            "present": present,
            "rate": round(present * 100 / total) if total else None,
            "recent": visits[:12],
        },
        "skills": skills,
        "season": await _season(db, owner, player.id),
        "plans": plans,
        "notes": notes,
        "matches": matches,
        "slots": slots,
    }


async def _season(db: AsyncSession, owner, player_id) -> dict:
    rows = (
        await db.scalars(
            select(m.MatchStat).where(
                m.MatchStat.player_id == player_id,
                m.MatchStat.owner_id == owner,
                m.MatchStat.minutes > 0,
                _alive(m.MatchStat),
            )
        )
    ).all()
    ratings = [r.rating for r in rows if r.rating is not None]
    return {
        "games": len(rows),
        "minutes": sum(r.minutes for r in rows),
        "goals": round(sum(r.stats.get("goals", 0) for r in rows)),
        "assists": round(sum(r.stats.get("assists", 0) for r in rows)),
        "rating": sum(ratings) / len(ratings) if ratings else None,
    }


def _d(d: datetime | date | None, with_time: bool = False) -> str:
    if d is None:
        return ""
    if isinstance(d, datetime):
        local = d.astimezone(ZoneInfo(get_settings().display_tz))
        s = f"{local.day} {MONTHS[local.month]}"
        return f"{s}, {WEEKDAYS[local.isoweekday()]} {local:%H:%M}" if with_time else s
    return f"{d.day} {MONTHS[d.month]}"


def _iso_d(s: str | None) -> str:
    if not s:
        return ""
    try:
        return _d(date.fromisoformat(s))
    except ValueError:
        return s


def _num(v) -> str:
    if v is None:
        return "—"
    return str(int(v)) if float(v).is_integer() else f"{v:.2f}".rstrip("0").replace(".", ",")


def _targets(targets: list[dict]) -> str:
    """Показатели программы: сейчас → цель и полоса прогресса."""
    rows = ""
    for t in targets:
        cur, tgt = t.get("current"), t.get("target")
        pct = 0
        if cur and tgt:
            pct = round(min(1.0, (tgt / cur) if tgt < cur else (cur / tgt)) * 100)
        rows += (
            f"<li><div class='meta'><b>{html.escape(t.get('name', ''))}</b>"
            f"<span>сейчас {_num(cur)} → цель {_num(tgt)} {html.escape(t.get('unit', ''))}</span></div>"
            f"<span class='bar'><i style='width:{pct}%'></i></span></li>"
        )
    return f"<h4>Показатели</h4><ul class='targets'>{rows}</ul>" if rows else ""


def render_card(card: dict) -> str:
    e = html.escape
    p = card["player"]
    att = card["attendance"]
    sub = " · ".join(
        x for x in [
            card["team"],
            f"№{p['number']}" if p["number"] is not None else "",
            p["position"] or "",
            f"{p['birth_year']} г.р." if p["birth_year"] else "",
        ] if x
    )

    parts: list[str] = []
    rate = "—" if att["rate"] is None else f"{att['rate']}%"
    parts.append(
        f"""<section class="stats">
  <div><b>{rate}</b><span>посещаемость</span></div>
  <div><b>{att['present']} из {att['total']}</b><span>занятий посещено</span></div>
</section>"""
    )

    if card["notes"]:
        items = "".join(
            f"""<li><div class="meta"><span class="tag">{e(CATEGORY_LABELS.get(n.category, n.category))}</span>
<span>{_d(n.written_at)}</span></div><p>{e(n.text).replace(chr(10), '<br>')}</p></li>"""
            for n in card["notes"]
        )
        parts.append(f"<section><h2>Сообщения тренера</h2><ul class='notes'>{items}</ul></section>")

    for plan in card["plans"]:
        period = PERIOD_LABELS.get(plan.period, "")
        dates = " — ".join(x for x in [_iso_d(plan.starts_on), _iso_d(plan.ends_on)] if x)
        goals = [i for i in plan.items if i.get("kind") == "goal"]
        tasks = [i for i in plan.items if i.get("kind") != "goal"]

        def lst(items: list[dict]) -> str:
            return "".join(
                f"<li class='{'done' if i.get('done') else ''}'><span class='box'>{'✓' if i.get('done') else ''}</span>"
                f"{e(i.get('text', ''))}</li>"
                for i in items
            )

        focus = ", ".join(SKILL_LABELS.get(f, f) for f in plan.focus)
        parts.append(
            f"""<section><h2>План развития {e(period)}</h2>
<div class="card"><h3>{e(plan.title)}</h3>
{f'<div class="meta">{e(dates)}</div>' if dates else ''}
{f'<div class="meta">Фокус: {e(focus)}</div>' if focus else ''}
{f'<p><b>Ключевая цель:</b> {e(plan.key_goal)}</p>' if plan.key_goal else ''}
{_targets(plan.targets)}
{f'<h4>Цели</h4><ul class="check">{lst(goals)}</ul>' if goals else ''}
{f'<h4>Задания</h4><ul class="check">{lst(tasks)}</ul>' if tasks else ''}
{f'<p class="comment">{e(plan.comment)}</p>' if plan.comment else ''}
</div></section>"""
        )

    season = card.get("season")
    if season and season["games"]:
        cells = [("Матчи", season["games"]), ("Минуты", season["minutes"]), ("Голы", season["goals"]),
                 ("Голевые", season["assists"])]
        if season["rating"] is not None:
            cells.append(("Ср. оценка", f"{season['rating']:.1f}"))
        items = "".join(f"<div><b>{v}</b><span>{k}</span></div>" for k, v in cells)
        parts.append(f"<section><h2>Игровая статистика</h2><div class='grid'>{items}</div></section>")

    if card["skills"]:
        rows = "".join(
            f"<li><span>{e(SKILL_LABELS.get(k, k))}</span><span class='bar'><i style='width:{v * 20}%'></i></span>"
            f"<b>{v}/5</b></li>"
            for k, v in card["skills"].items()
        )
        parts.append(f"<section><h2>Оценки тренера</h2><ul class='skills'>{rows}</ul></section>")

    if card["matches"] or card["slots"]:
        rows = ""
        for s in card["slots"]:
            days = ", ".join(WEEKDAYS[d] for d in s.weekdays if 1 <= d <= 7)
            place = f" · {e(s.location)}" if s.location else ""
            rows += f"<li><b>{e(days)} {e(s.start_time)}</b> {e(s.title)}{place}</li>"
        for mt in card["matches"]:
            side = "дома" if mt.home else "в гостях"
            comp = f" · {e(mt.competition)}" if mt.competition else ""
            rows += f"<li class='match'><b>{_d(mt.starts_at, True)}</b> Матч: {e(mt.opponent)} ({side}){comp}</li>"
        parts.append(f"<section><h2>Расписание</h2><ul class='plain'>{rows}</ul></section>")

    if att["recent"]:
        rows = "".join(
            f"<li class='{v['status']}'><span>{_d(v['date'])}</span><span>{e(v['title'])}</span>"
            f"<b>{ATTENDANCE_LABELS.get(v['status'], v['status'])}</b></li>"
            for v in att["recent"]
        )
        parts.append(f"<section><h2>Последние занятия</h2><ul class='visits'>{rows}</ul></section>")

    coach = f"Тренер: {e(card['coach'])}" if card["coach"] else ""
    return PAGE.format(
        title=e(p["name"]), sub=e(sub), body="\n".join(parts), coach=coach
    )


PAGE = """<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>{title} — карточка игрока</title>
<style>
:root{{--red:#E30613;--bg:#0B0B0C;--card:#17171A;--line:#2A2A2F;--text:#F2F2F2;--muted:#A0A0AA}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--text);
font:16px/1.45 -apple-system,Segoe UI,Roboto,sans-serif}}
header{{background:linear-gradient(135deg,var(--red),#7a0009);padding:28px 16px 22px}}
header h1{{margin:0;font-size:28px;text-transform:uppercase;letter-spacing:.5px}}
header p{{margin:4px 0 0;opacity:.9}}main{{max-width:720px;margin:0 auto;padding:8px 16px 40px}}
h2{{font-size:15px;text-transform:uppercase;letter-spacing:1px;color:var(--muted);margin:24px 0 8px}}
h3{{margin:0 0 4px}}h4{{margin:12px 0 4px;color:var(--muted);font-size:14px}}
ul{{list-style:none;margin:0;padding:0}}.card,.notes li,.stats div{{background:var(--card);
border:1px solid var(--line);border-radius:14px;padding:14px}}
.stats{{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}}
.stats b{{display:block;font-size:26px}}.stats span,.meta{{color:var(--muted);font-size:14px}}
.notes li{{margin-bottom:10px}}.notes p{{margin:6px 0 0}}.meta{{display:flex;gap:10px;flex-wrap:wrap}}
.tag{{background:var(--red);color:#fff;border-radius:6px;padding:1px 8px;font-size:13px}}
.check li{{display:flex;gap:10px;padding:6px 0;border-bottom:1px solid var(--line)}}
.check li.done{{color:var(--muted);text-decoration:line-through}}
.box{{flex:none;width:22px;height:22px;border:2px solid var(--red);border-radius:6px;
display:inline-flex;align-items:center;justify-content:center;font-size:14px;text-decoration:none}}
.done .box{{background:var(--red);color:#fff}}.comment{{border-left:3px solid var(--red);padding-left:10px}}
.skills li{{display:grid;grid-template-columns:1fr 1fr auto;gap:10px;align-items:center;padding:6px 0}}
.bar{{height:8px;background:var(--line);border-radius:4px;overflow:hidden}}.bar i{{display:block;height:100%;
background:var(--red)}}.plain li,.visits li{{padding:8px 0;border-bottom:1px solid var(--line)}}
.match b{{color:var(--red)}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(90px,1fr));gap:10px}}
.grid div{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px}}
.grid b{{display:block;font-size:22px}}.grid span{{color:var(--muted);font-size:13px}}
.visits li{{display:grid;grid-template-columns:90px 1fr auto;gap:8px}}
.targets li{{padding:6px 0}}.targets .bar{{display:block;margin-top:4px}}
.visits .absent b{{color:#ff8a80}}.visits .present b{{color:#69f0ae}}footer{{color:var(--muted);
text-align:center;font-size:13px;padding:16px}}
</style></head><body>
<header><h1>{title}</h1><p>{sub}</p></header>
<main>{body}</main>
<footer>{coach}<br>Страница только для просмотра · CoachPilot</footer>
</body></html>"""

GONE = """<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Ссылка недействительна</title></head>
<body style="font-family:sans-serif;background:#0B0B0C;color:#eee;padding:40px;text-align:center">
<h1>Ссылка недействительна</h1><p>Попросите тренера прислать новую ссылку.</p></body></html>"""


@router.get("/p/{token}", response_class=HTMLResponse, include_in_schema=False)
async def public_page(token: str, db: AsyncSession = Depends(get_db)) -> HTMLResponse:
    card = await player_card(db, token[:64])
    if card is None:
        return HTMLResponse(GONE, status_code=404)
    return HTMLResponse(
        render_card(card),
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )
