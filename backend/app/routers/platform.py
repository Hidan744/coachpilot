"""Тарифы, статусы интеграций, журнал действий и уведомления в Telegram."""

import secrets
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app import billing, notify
from app import models as m
from app.audit import audit
from app.config import get_settings
from app.db import get_db
from app.security import current_user

router = APIRouter(tags=["platform"])


# ------------------------------------------------------------------ тарифы


@router.get("/billing/plans")
async def billing_plans() -> dict:
    st = get_settings()
    return {
        "currency": "RUB",
        "payments": _payments_status(),
        "plans": [billing.plan_out(p) for p in billing.plans(st).values()],
    }


@router.get("/billing/me")
async def billing_me(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    sub = await db.get(m.Subscription, user.id)
    plan = billing.plans().get(sub.plan if sub else "free", billing.plans()["free"])
    return {
        "plan": billing.plan_out(plan),
        "status": sub.status if sub else "active",
        "ai_used": sub.ai_used if sub else 0,
        "ai_limit": sub.ai_quota_month if sub else 0,
        "payments": _payments_status(),
    }


class CheckoutIn(BaseModel):
    plan: str


@router.post("/billing/checkout")
async def checkout(
    body: CheckoutIn, request: Request, user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    if body.plan not in billing.plans():
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Неизвестный тариф")
    mode = _payments_status()
    if mode != "test":
        # Платёжный провайдер не подключён — оплату не имитируем.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            "Оплата пока не подключена. Чтобы сменить тариф, напишите в поддержку.")
    sub = await billing.set_plan(db, user.id, body.plan, status="test")
    await audit(db, user.id, "plan_changed", request, plan=body.plan, mode="test")
    await db.commit()
    return {"plan": sub.plan, "status": sub.status, "ai_limit": sub.ai_quota_month, "test": True}


def _payments_status() -> str:
    st = get_settings()
    if st.payments_mode == "test" and st.env != "production":
        return "test"
    return "off" if st.payments_mode in ("off", "test") else st.payments_mode


# ------------------------------------------------------------------ интеграции


@router.get("/integrations/status")
async def integrations(user: m.User = Depends(current_user)) -> dict:
    st = get_settings()
    ai_on = st.ai_provider != "mock" and bool(st.ai_api_key)
    return {
        "ai": {"status": "connected" if ai_on else "not_configured",
               "detail": f"Провайдер: {st.ai_provider}" if ai_on else "AI не подключён: планы собираются по правилам"},
        "telegram": {"status": "connected" if notify.channel("telegram").configured() else "not_configured",
                     "detail": "Бот подключён" if st.telegram_bot_token else "Нужен токен бота на сервере"},
        "payments": {"status": {"test": "test", "off": "not_configured"}.get(_payments_status(), "connected"),
                     "detail": {"test": "Тестовый режим, без денег", "off": "Платёжный провайдер не подключён"}
                     .get(_payments_status(), _payments_status())},
        "email": {"status": "not_configured", "detail": "Почтовые уведомления не подключены"},
    }


# ------------------------------------------------------------------ журнал действий


@router.get("/account/audit")
async def my_audit(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> list[dict]:
    rows = await db.scalars(
        select(m.AuditLog).where(m.AuditLog.user_id == user.id).order_by(m.AuditLog.at.desc()).limit(100)
    )
    return [{"action": r.action, "details": r.details, "at": r.at.isoformat()} for r in rows]


# ------------------------------------------------------------------ Telegram


@router.get("/notifications/telegram")
async def telegram_state(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    link = await db.get(m.TelegramLink, user.id)
    return {
        "configured": notify.channel("telegram").configured(),
        "linked": link is not None,
        "bot": get_settings().telegram_bot_username,
    }


@router.post("/notifications/telegram/link")
async def telegram_link(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    st = get_settings()
    if not notify.channel("telegram").configured() or not st.telegram_bot_username:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Telegram не подключён на сервере")
    code = secrets.token_urlsafe(16)
    db.add(m.TelegramLinkCode(code=code, user_id=user.id, expires_at=datetime.now(UTC) + timedelta(minutes=30)))
    await db.commit()
    return {"url": f"https://t.me/{st.telegram_bot_username}?start={code}", "expires_min": 30}


@router.delete("/notifications/telegram", status_code=status.HTTP_204_NO_CONTENT)
async def telegram_unlink(request: Request, user: m.User = Depends(current_user),
                          db: AsyncSession = Depends(get_db)) -> None:
    await db.execute(delete(m.TelegramLink).where(m.TelegramLink.user_id == user.id))
    await audit(db, user.id, "telegram_unlinked", request)
    await db.commit()


@router.post("/notifications/telegram/test")
async def telegram_test(user: m.User = Depends(current_user), db: AsyncSession = Depends(get_db)) -> dict:
    link = await db.get(m.TelegramLink, user.id)
    if link is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Сначала привяжите Telegram")
    await _send(link.chat_id, "CoachPilot: уведомления работают ✅")
    return {"sent": True}


@router.post("/telegram/webhook/{secret}", include_in_schema=False)
async def telegram_webhook(secret: str, update: dict, db: AsyncSession = Depends(get_db)) -> dict:
    st = get_settings()
    if not st.telegram_webhook_secret or not secrets.compare_digest(secret, st.telegram_webhook_secret):
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    msg = update.get("message") or {}
    text, chat = str(msg.get("text") or ""), (msg.get("chat") or {}).get("id")
    if not text.startswith("/start ") or not isinstance(chat, int):
        return {"ok": True}
    code = await db.get(m.TelegramLinkCode, text.split(" ", 1)[1].strip()[:40])
    if code is None or code.expires_at < datetime.now(UTC):
        await _send(chat, "Ссылка устарела. Получите новую в приложении: Профиль → Уведомления.", quiet=True)
        return {"ok": True}
    await db.execute(insert(m.TelegramLink).values(user_id=code.user_id, chat_id=chat)
                     .on_conflict_do_update(index_elements=["user_id"], set_={"chat_id": chat}))
    await db.delete(code)
    await audit(db, code.user_id, "telegram_linked")
    await db.commit()
    await _send(chat, "Готово! Сюда будут приходить напоминания о тренировках и матчах.", quiet=True)
    return {"ok": True}


@router.post("/notifications/reminders/run")
async def run_reminders(x_cron_secret: str = Header(default=""), db: AsyncSession = Depends(get_db)) -> dict:
    """Напоминания о тренировках и матчах в ближайшие 24 часа. Вызывается по расписанию (cron)."""
    st = get_settings()
    if not st.cron_secret or not secrets.compare_digest(x_cron_secret, st.cron_secret):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Нет доступа")
    if not notify.channel("telegram").configured():
        return {"sent": 0, "status": "not_configured"}
    now = datetime.now(UTC)
    soon = now + timedelta(hours=24)
    sent = failed = 0
    for link in await db.scalars(select(m.TelegramLink)):
        items: list[tuple[str, uuid.UUID, str]] = []
        for s in await db.scalars(select(m.TrainingSession).where(
                m.TrainingSession.owner_id == link.user_id, m.TrainingSession.deleted_at.is_(None),
                m.TrainingSession.status.in_(["planned", "draft"]),
                m.TrainingSession.scheduled_at.between(now, soon))):
            items.append(("session", s.id, f"Тренировка «{s.title}» — {_local(s.scheduled_at)}"))
        for g in await db.scalars(select(m.Match).where(
                m.Match.owner_id == link.user_id, m.Match.deleted_at.is_(None), m.Match.status == "scheduled",
                m.Match.starts_at.between(now, soon))):
            items.append(("match", g.id, f"Матч с {g.opponent} — {_local(g.starts_at)}"))
        # Родителю и игроку — события команды привязанного ребёнка.
        children = await db.execute(
            select(m.FamilyLink, m.Player).join(m.Player, m.Player.id == m.FamilyLink.player_id)
            .where(m.FamilyLink.user_id == link.user_id, m.Player.deleted_at.is_(None))
        )
        for fl, p in children:
            for s in await db.scalars(select(m.TrainingSession).where(
                    m.TrainingSession.owner_id == fl.owner_id, m.TrainingSession.team_id == p.team_id,
                    m.TrainingSession.deleted_at.is_(None), m.TrainingSession.status.in_(["planned", "draft"]),
                    m.TrainingSession.scheduled_at.between(now, soon))):
                items.append(("f_session", s.id, f"{p.first_name}: тренировка {_local(s.scheduled_at)}. "
                                                  "Подтвердите участие в приложении."))
            for g in await db.scalars(select(m.Match).where(
                    m.Match.owner_id == fl.owner_id, m.Match.team_id == p.team_id, m.Match.deleted_at.is_(None),
                    m.Match.status == "scheduled", m.Match.starts_at.between(now, soon))):
                items.append(("f_match", g.id, f"{p.first_name}: матч с {g.opponent} {_local(g.starts_at)}"))
        for kind, ref, text in items:
            claimed = await db.execute(insert(m.NotificationLog).values(user_id=link.user_id, kind=kind, ref=str(ref))
                                       .on_conflict_do_nothing().returning(m.NotificationLog.id))
            if claimed.scalar() is None:
                continue  # уже отправляли
            try:
                await _send(link.chat_id, f"Напоминание: {text}")
                sent += 1
                await db.commit()
            except HTTPException:
                failed += 1
                await db.rollback()
    return {"sent": sent, "failed": failed, "status": "ok"}


def _local(dt: datetime) -> str:
    from zoneinfo import ZoneInfo

    d = dt.astimezone(ZoneInfo(get_settings().display_tz))
    return d.strftime("%d.%m в %H:%M")


async def _send(chat_id: int, text: str, quiet: bool = False) -> None:
    try:
        await notify.channel("telegram").send(str(chat_id), text)
    except notify.NotConfigured as e:
        if not quiet:
            raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e)) from e
    except notify.SendFailed as e:
        if not quiet:
            raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(e)) from e
