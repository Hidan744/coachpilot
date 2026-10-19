"""Оценка качества AI-планов на наборе из 20 запросов с текущим провайдером.

    CP_AI_PROVIDER=yandexgpt CP_AI_API_KEY=... CP_AI_FOLDER_ID=... python -m app.ai.eval

Выводит для каждого запроса: прошёл ли ответ проверку с первой попытки, понадобилась ли
починка, источник плана (ai/rules), время и токены. Нужна БД с загруженным каталогом.
"""

import asyncio
import itertools
import time
import uuid

from sqlalchemy import select

from app import models as m
from app.ai.planner import PlanRequest, generate_plan
from app.ai.providers import build_provider
from app.config import get_settings
from app.db import SessionLocal

CASES = list(itertools.islice(itertools.product(
    ["U8", "U10", "U12", "U14", "U16", "adult"],
    [8, 14, 20],
    [60, 90],
    ["Передачи в одно касание", "Удары по воротам после паса", "Обводка 1×1 на фланге",
     "Оборона вдвоём: давление и страховка", "Быстрые переходы после отбора"],
), 0, None, 9))[:20]


async def main() -> None:
    provider = build_provider(get_settings())
    async with SessionLocal() as db:
        user = m.User(email=f"eval-{uuid.uuid4().hex[:6]}@local", password_hash="-", name="eval", consent_version="-")
        db.add(user)
        await db.flush()
        ok = repaired = rules = 0
        for age, players, duration, goal in CASES:
            req = PlanRequest(age_group=age, players=players, duration_min=duration, goal=goal,
                              equipment=["balls", "cones", "bibs", "goals", "mini_goals"])
            t = time.monotonic()
            out = await generate_plan(db, provider, user.id, req)
            log = (await db.scalars(select(m.AIRequest).where(m.AIRequest.user_id == user.id)
                                    .order_by(m.AIRequest.created_at.desc()))).first()
            total = sum(b.duration_min for b in out.blocks)
            first_try = out.source == "ai" and log.attempts == 1 and not log.error
            ok += first_try
            repaired += out.source == "ai" and not first_try
            rules += out.source == "rules"
            print(f"{age:5} {players:2} игр {duration:3} мин | {goal[:32]:32} | {out.source:5} "
                  f"попыток {log.attempts} | Σ{total} | {time.monotonic() - t:5.1f} с | "
                  f"токены {log.tokens_in}/{log.tokens_out} | {log.error or ''}"[:220])
        print(f"\nС первой попытки: {ok}/20, после починки: {repaired}/20, запасной план по правилам: {rules}/20")
        await db.delete(user)
        await db.commit()


if __name__ == "__main__":
    asyncio.run(main())
