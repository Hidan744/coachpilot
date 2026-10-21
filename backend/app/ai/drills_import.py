"""AI-разбор описаний упражнений (из Word, Excel, текста) в структурированные карточки библиотеки.

Модель раскладывает текст тренера по полям упражнения, ничего не придумывая сверх описания.
Результат проверяется той же схемой, что и пользовательские упражнения. Если AI недоступен
или исчерпан лимит, клиент разбирает текст сам, по правилам.
"""

import time

from pydantic import BaseModel, Field, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.ai.planner import FORBIDDEN, extract_json
from app.ai.providers import LLMProvider, ProviderError
from app.ai.quota import quota_ok
from app.schemas import DRILL_CATEGORIES, DrillData

SYSTEM_PROMPT = f"""Ты помогаешь футбольному тренеру перенести его упражнения в библиотеку приложения.
В тексте может быть одно или несколько упражнений. Для каждого заполни поля строго по тексту тренера:
не придумывай того, чего нет; если поля нет в тексте — оставь пустым или значение по умолчанию.
Категория — одна из: {", ".join(DRILL_CATEGORIES)}.
Шаги (steps) — последовательность действий, 2–8 коротких пунктов. Не обещай результат, не давай медицинских советов.
Ответь строго JSON: {{"drills": [{{"title": "...", "category": "passing", "goal": "...", "setup": "...",
"steps": ["..."], "rules": ["..."], "coaching_points": ["..."], "success_criteria": ["..."],
"easier": ["..."], "harder": ["..."],
"equipment": ["balls", "cones", "bibs", "goals", "mini_goals", "poles", "ladder", "hurdles"],
"duration_min": 15, "players_min": 4, "players_max": 16, "age_min": 8, "age_max": 99}}]}}"""


class ParseRequest(BaseModel):
    text: str = Field(min_length=10, max_length=30000)


class ParseOut(BaseModel):
    drills: list[DrillData]
    source: str
    warnings: list[str] = []


class _AIDrill(BaseModel):
    title: str = Field(min_length=2, max_length=150)
    category: str = "technique"
    goal: str = ""
    setup: str = ""
    steps: list[str] = Field(default_factory=list)
    rules: list[str] = Field(default_factory=list)
    coaching_points: list[str] = Field(default_factory=list)
    success_criteria: list[str] = Field(default_factory=list)
    easier: list[str] = Field(default_factory=list)
    harder: list[str] = Field(default_factory=list)
    equipment: list[str] = Field(default_factory=list)
    duration_min: int = 15
    players_min: int = 2
    players_max: int = 30
    age_min: int = 6
    age_max: int = 99


EQUIPMENT = {"balls", "cones", "bibs", "goals", "mini_goals", "poles", "ladder", "hurdles"}


def _clip(v: int, lo: int, hi: int) -> int:
    return max(lo, min(hi, v))


def _to_drill(d: _AIDrill) -> DrillData | None:
    def clean(items: list[str]) -> list[str]:
        return [x.strip()[:500] for x in items if x.strip() and not FORBIDDEN.search(x)][:12]

    try:
        return DrillData(
            source="user",
            title=d.title.strip()[:150],
            category=d.category if d.category in DRILL_CATEGORIES else "technique",
            goal=d.goal.strip()[:2000],
            setup=d.setup.strip()[:2000],
            steps=clean(d.steps),
            rules=clean(d.rules),
            coaching_points=clean(d.coaching_points),
            success_criteria=clean(d.success_criteria),
            variants={"easier": clean(d.easier)[:10], "harder": clean(d.harder)[:10]},
            equipment=[e for e in d.equipment if e in EQUIPMENT],
            duration_min=_clip(d.duration_min, 1, 120),
            players_min=_clip(d.players_min, 1, 60),
            players_max=_clip(max(d.players_max, d.players_min), 1, 60),
            age_min=_clip(d.age_min, 4, 99),
            age_max=_clip(max(d.age_max, d.age_min), 4, 99),
            tags=["импорт"],
        )
    except ValidationError:
        return None


async def parse_drills(db: AsyncSession, provider: LLMProvider, owner_id, req: ParseRequest) -> ParseOut:
    entry = m.AIRequest(user_id=owner_id, kind="drills_import", provider=provider.name, model="")
    started = time.monotonic()
    try:
        ok, sub = await quota_ok(db, owner_id)
        if not ok:
            entry.error = "quota"
            warning = "Лимит AI на месяц исчерпан — текст разобран без AI."
            return ParseOut(drills=[], source="manual", warnings=[warning])
        comp = await provider.complete(SYSTEM_PROMPT, "УПРАЖНЕНИЯ:\n" + req.text, temperature=0.2)
        entry.model, entry.tokens_in, entry.tokens_out = comp.model, comp.tokens_in, comp.tokens_out
        try:
            raw = extract_json(comp.text).get("drills", [])
            items = [_AIDrill.model_validate(x) for x in raw if isinstance(x, dict)]
        except (ValueError, ValidationError) as e:
            raise ProviderError(f"invalid drills json: {e}") from e
        drills = [d for d in map(_to_drill, items) if d is not None]
        if not drills:
            raise ProviderError("no drills parsed")
        entry.valid = True
        if sub is not None:
            sub.ai_used += 1
        return ParseOut(drills=drills, source="ai")
    except ProviderError as e:
        entry.error = str(e)[:1000]
        return ParseOut(drills=[], source="manual", warnings=["AI сейчас недоступен — текст разобран без AI."])
    finally:
        entry.latency_ms = int((time.monotonic() - started) * 1000)
        db.add(entry)
        await db.commit()
