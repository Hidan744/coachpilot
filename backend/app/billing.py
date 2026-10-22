"""Тарифы и подписка. Цены и лимиты — только в конфигурации (Settings), интерфейс берёт их отсюда.

Оплата не имитируется: при payments_mode=off смена тарифа доступна только администратору (CLI),
в тестовом режиме — без денег и только вне production.

    python -m app.billing set-plan coach@example.com pro   # назначить тариф вручную
"""

import argparse
import asyncio
from dataclasses import asdict, dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.config import Settings, get_settings


@dataclass(frozen=True)
class Plan:
    code: str
    title: str
    price_rub_month: int
    ai_quota_month: int
    audience: str
    features: tuple[str, ...]


def plans(settings: Settings | None = None) -> dict[str, Plan]:
    st = settings or get_settings()
    return {
        "free": Plan("free", "Бесплатный", 0, st.ai_free_quota_month, "Попробовать с одной командой",
                     ("Конструктор тренировок по правилам", "Календарь, посещаемость, отчёты", "Офлайн-режим")),
        "pro": Plan("pro", "Pro", st.price_pro_rub_month, st.ai_pro_quota_month, "Индивидуальный тренер",
                    ("Всё из бесплатного", "AI-генерация планов и отчётов", "Программы развития и видеоразбор")),
        "academy": Plan("academy", "Academy", st.price_academy_rub_month, st.ai_academy_quota_month,
                        "Футбольная школа или академия",
                        ("Всё из Pro", "Несколько тренеров и команд", "Отчёты по школе")),
    }


def plan_out(p: Plan) -> dict:
    return asdict(p) | {"features": list(p.features)}


async def set_plan(db: AsyncSession, user_id, code: str, status: str = "active") -> m.Subscription:
    p = plans()[code]
    sub = await db.get(m.Subscription, user_id)
    if sub is None:
        sub = m.Subscription(user_id=user_id)
        db.add(sub)
    sub.plan, sub.status, sub.ai_quota_month = p.code, status, p.ai_quota_month
    return sub


async def _cli() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("set-plan")
    sp.add_argument("email")
    sp.add_argument("plan", choices=list(plans()))
    args = ap.parse_args()
    from app.audit import audit
    from app.db import SessionLocal

    async with SessionLocal() as db:
        user = await db.scalar(select(m.User).where(m.User.email == args.email.lower()))
        if user is None:
            raise SystemExit(f"нет пользователя {args.email}")
        await set_plan(db, user.id, args.plan)
        await audit(db, user.id, "plan_changed", plan=args.plan, by="admin_cli")
        await db.commit()
        print(f"{args.email}: тариф {args.plan}")


if __name__ == "__main__":
    asyncio.run(_cli())
