"""AI-генерация плана тренировки.

1. Отбор 20–40 подходящих упражнений из библиотеки (возраст, состав, инвентарь, цель).
2. Контекст команды: последние подтверждённые отчёты, имена игроков вычищены.
3. Запрос к модели со строгим JSON-форматом; кандидаты передаются под короткими id (c1, c2…).
4. Проверка ответа кодом. При ошибках — одна попытка исправления моделью, затем автопочинка.
5. Если модель недоступна или исчерпан лимит — план по правилам (app.ai.rules).
"""

import json
import logging
import re
import time
import uuid
from typing import Annotated, Literal

from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.ai import quota, rules
from app.ai.providers import LLMProvider, ProviderError
from app.schemas import DRILL_CATEGORIES, DrillData, TrainingBlock

log = logging.getLogger("coachpilot.ai")

ALWAYS_AVAILABLE = {"balls", "cones"}
FORBIDDEN = re.compile(
    r"гарантир\w*|предотвра\w*\s+травм\w*|исключа\w*\s+травм\w*|100\s*%\s*(результат|эффект)|"
    r"вылечи\w*|диагно\w*",
    re.IGNORECASE,
)
AGE_BY_GROUP = {"adult": 18}

# ------------------------------------------------------------------ запрос/ответ API


class PlanRequest(BaseModel):
    team_id: uuid.UUID | None = None
    age_group: str = Field(max_length=20)
    level: str = Field(default="amateur", max_length=30)
    players: int = Field(ge=1, le=60)
    duration_min: int = Field(ge=20, le=180)
    goal: str = Field(min_length=3, max_length=300)
    field_type: str | None = Field(default=None, max_length=30)
    equipment: list[str] = Field(default_factory=list, max_length=20)
    focus: list[Literal["technique", "tactics", "physical", "game"]] = Field(default_factory=list)
    constraints: str = Field(default="", max_length=500)
    answer: str = Field(default="", max_length=500)  # ответ на уточняющий вопрос модели
    use_ai: bool = True
    # Формат (командная / групповая / индивидуальная), интенсивность и позиции для акцента.
    format: Literal["team", "group", "individual"] = "team"
    intensity: Literal["low", "medium", "high"] = "medium"
    positions: list[Literal["GK", "DF", "MF", "FW"]] = Field(default_factory=list, max_length=4)
    # Приоритеты команды из истории (отчёты, цели сезона, программы игроков) — текстом, с источником.
    priorities: list[Annotated[str, Field(max_length=200)]] = Field(default_factory=list, max_length=6)


class PlanOut(BaseModel):
    title: str
    blocks: list[TrainingBlock]
    assumptions: list[str]
    clarifying_question: str | None
    source: Literal["ai", "rules"]
    warnings: list[str]


# ------------------------------------------------------------------ формат ответа модели


class AINewDrill(BaseModel):
    title: str = Field(min_length=3, max_length=150)
    category: Literal[DRILL_CATEGORIES]  # type: ignore[valid-type]
    goal: str = Field(default="", max_length=1000)
    setup: str = Field(min_length=10, max_length=2000)
    steps: list[str] = Field(min_length=2, max_length=12)
    rules: list[str] = Field(default_factory=list, max_length=10)
    coaching_points: list[str] = Field(min_length=1, max_length=10)
    success_criteria: list[str] = Field(default_factory=list, max_length=10)
    easier: list[str] = Field(default_factory=list, max_length=6)
    harder: list[str] = Field(default_factory=list, max_length=6)
    equipment: list[str] = Field(default_factory=list, max_length=10)
    players_min: int = Field(default=1, ge=1, le=60)
    players_max: int = Field(default=30, ge=1, le=60)


class AIBlock(BaseModel):
    phase: Literal["warmup", "main", "game", "cooldown"]
    duration_min: int = Field(ge=1, le=120)
    drill_id: str | None = None
    adaptation: str = Field(default="", max_length=600)
    new_drill: AINewDrill | None = None


class AIAnswer(BaseModel):
    title: str = Field(default="Тренировка", max_length=150)
    assumptions: list[str] = Field(default_factory=list, max_length=10)
    clarifying_question: str | None = Field(default=None, max_length=500)
    blocks: list[AIBlock] = Field(default_factory=list, max_length=12)


SYSTEM_PROMPT = """Ты — помощник футбольного тренера. Составляешь план тренировочного занятия на русском языке.
Тренер принимает решения сам: твой план — черновик, который он отредактирует.

Правила:
1. В первую очередь используй упражнения из списка candidates (поле drill_id = их id, например "c3").
   Новое упражнение (new_drill) придумывай, только если подходящего кандидата нет; тогда опиши его полностью:
   организация, шаги (не меньше 2), подсказки тренера.
2. Структура: разминка (warmup) → основная часть (main, 1–3 упражнения) → игровая часть (game) → заминка (cooldown).
   Для занятий короче 45 минут заминку можно не включать.
3. Сумма duration_min всех блоков должна в точности равняться длительности занятия.
4. Упражнения должны подходить по возрасту, числу игроков и доступному инвентарю.
   В adaptation сначала одной фразой объясни, почему упражнение подходит под цель занятия,
   затем кратко — как адаптировать его к этой группе (размер зоны, группы, правила).
5. Не придумывай фактические показатели игроков. Не обещай гарантированный результат,
   не утверждай, что упражнения предотвращают травмы, не давай медицинских советов.
6. Учитывай format (individual — без игровой части, упражнения для 1–4 человек; group — малые группы;
   team — вся команда), intensity (low / medium / high — для основной и игровой части)
   и positions (акцент упражнений на эти линии: GK — вратари, DF — оборона, MF — передачи и владение,
   FW — удары и обводка).
7. История команды (history) и team_priorities — главное: не повторяй упражнения последних занятий без причины,
   направь основную часть на приоритеты команды и в assumptions назови, какой приоритет учтён.
8. Если данных недостаточно, перечисли допущения в assumptions. Если без ответа тренера план
   составить нельзя, задай один вопрос в clarifying_question и верни пустой список blocks.

Ответь строго одним JSON-объектом без пояснений:
{"title": "...", "assumptions": ["..."], "clarifying_question": null,
 "blocks": [{"phase": "warmup", "duration_min": 12, "drill_id": "c1", "adaptation": "...", "new_drill": null}]}"""


# ------------------------------------------------------------------ контекст


def team_age(age_group: str) -> int:
    if age_group in AGE_BY_GROUP:
        return AGE_BY_GROUP[age_group]
    try:
        return int(age_group.lstrip("Uu"))
    except ValueError:
        return 14


def drill_fits(d: m.Drill, age: int, players: int, equipment: set[str]) -> bool:
    return (
        d.age_min <= age <= d.age_max
        and d.players_min <= players
        and set(d.equipment) <= equipment | ALWAYS_AVAILABLE
    )


async def select_candidates(db: AsyncSession, owner_id, req: PlanRequest, limit: int = 36) -> list[m.Drill]:
    rows = await db.scalars(
        select(m.Drill).where(
            or_(m.Drill.owner_id.is_(None), m.Drill.owner_id == owner_id),
            m.Drill.deleted_at.is_(None),
        )
    )
    age = team_age(req.age_group)
    fitting = [d for d in rows if drill_fits(d, age, req.players, set(req.equipment))]
    main = rules.main_categories(req.goal, req.focus)

    def score(d: m.Drill) -> tuple:
        rel = main.index(d.category) if d.category in main else len(main) + 1
        return (d.owner_id is None, rel, d.title)  # свои упражнения тренера — первыми

    fitting.sort(key=score)
    # Гарантируем кандидатов для всех фаз занятия.
    picked: list[m.Drill] = []
    for cat, n in (("warmup", 4), ("game", 4), ("cooldown", 2)):
        picked += [d for d in fitting if d.category == cat][:n]
    for d in fitting:
        if len(picked) >= limit:
            break
        if d not in picked:
            picked.append(d)
    return picked


def stem(word: str) -> str:
    """Основа имени для поиска падежных форм: «Саша» → «Саш» (Сашу, Саше, Сашей)."""
    return word[:-1] if len(word) >= 4 and word[-1].lower() in "аяйьео" else word


def name_scrubber(names: list[str]):
    """Заменяет имена игроков на «игрок», чтобы персональные данные не уходили в AI."""
    words = sorted({stem(n.strip()) for n in names if len(n.strip()) >= 3}, key=len, reverse=True)
    if not words:
        return lambda s: s
    rx = re.compile(r"\b(" + "|".join(re.escape(w) for w in words) + r")\w*", re.IGNORECASE)
    return lambda s: rx.sub("игрок", s)


async def team_history(db: AsyncSession, owner_id, team_id) -> tuple[list[dict], set[uuid.UUID], list[str]]:
    """Сводка последних занятий команды: отчёты (без имён), недавние упражнения, имена игроков."""
    if team_id is None:
        return [], set(), []
    players = await db.scalars(select(m.Player).where(m.Player.owner_id == owner_id, m.Player.team_id == team_id))
    names = [n for p in players for n in (p.first_name, p.last_name)]
    scrub = name_scrubber(names)
    sessions = list(await db.scalars(
        select(m.TrainingSession)
        .where(m.TrainingSession.owner_id == owner_id, m.TrainingSession.team_id == team_id,
               m.TrainingSession.deleted_at.is_(None), m.TrainingSession.status == "done")
        .order_by(m.TrainingSession.finished_at.desc().nulls_last(), m.TrainingSession.updated_at.desc())
        .limit(3)
    ))
    recent: set[uuid.UUID] = set()
    for s in sessions[:2]:
        for b in s.blocks or []:
            if b.get("drill_id"):
                recent.add(uuid.UUID(b["drill_id"]))
    history = []
    for s in sessions:
        rep = await db.scalar(select(m.SessionReport).where(
            m.SessionReport.session_id == s.id, m.SessionReport.deleted_at.is_(None),
            m.SessionReport.coach_confirmed.is_(True)))
        item = {"goal": scrub(s.goal), "date": (s.finished_at or s.updated_at).date().isoformat()}
        if rep:
            item |= {"went_well": scrub(rep.went_well)[:400], "to_improve": scrub(rep.to_improve)[:400],
                     "observations": scrub(rep.observations)[:400]}
        history.append(item)
    return history, recent, names


def build_prompt(req: PlanRequest, aliases: dict[str, m.Drill], history: list[dict], scrub) -> str:
    payload = {
        "session": {
            "age_group": req.age_group,
            "level": req.level,
            "players": req.players,
            "duration_min": req.duration_min,
            "goal": scrub(req.goal),
            "field": req.field_type,
            "equipment": req.equipment,
            "focus": req.focus,
            "format": req.format,
            "intensity": req.intensity,
            "positions": req.positions,
            "constraints": scrub(req.constraints),
            "coach_answer": scrub(req.answer),
            "team_priorities": [scrub(p) for p in req.priorities],
        },
        "candidates": [
            {"id": a, "title": d.title, "category": d.category, "goal": d.goal[:160],
             "duration_min": d.duration_min, "players": [d.players_min, d.players_max],
             "equipment": d.equipment, "intensity": d.intensity}
            for a, d in aliases.items()
        ],
        "history": history,
    }
    return "Составь план занятия по данным ниже.\nДАННЫЕ:" + json.dumps(payload, ensure_ascii=False)


# ------------------------------------------------------------------ проверка ответа


def extract_json(text: str) -> dict:
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fence:
        text = fence.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < 0:
        raise ValueError("в ответе нет JSON")
    return json.loads(text[start:end + 1])


def _texts(ans: AIAnswer) -> list[str]:
    out = [ans.title, *ans.assumptions]
    for b in ans.blocks:
        out.append(b.adaptation)
        if b.new_drill:
            nd = b.new_drill
            out += [nd.title, nd.goal, nd.setup, *nd.steps, *nd.rules, *nd.coaching_points,
                    *nd.success_criteria, *nd.easier, *nd.harder]
    return out


def validate_answer(raw: str, req: PlanRequest, aliases: dict[str, m.Drill]) -> tuple[AIAnswer | None, list[str]]:
    try:
        ans = AIAnswer.model_validate(extract_json(raw))
    except (ValueError, ValidationError) as e:
        return None, [f"Ответ не соответствует формату JSON: {str(e)[:300]}"]
    errors = []
    if not ans.blocks and not ans.clarifying_question:
        errors.append("Нет ни одного блока и нет уточняющего вопроса.")
    for i, b in enumerate(ans.blocks, 1):
        if (b.drill_id is None) == (b.new_drill is None):
            errors.append(f"Блок {i}: укажи либо drill_id из кандидатов, либо new_drill.")
        elif b.drill_id is not None:
            d = aliases.get(b.drill_id)
            if d is None:
                errors.append(f"Блок {i}: drill_id {b.drill_id} нет среди кандидатов.")
            elif d.players_min > req.players:
                errors.append(
                    f"Блок {i}: упражнению нужно минимум {d.players_min} игроков, а на занятии {req.players}."
                )
        else:
            nd = b.new_drill
            missing = set(nd.equipment) - set(req.equipment) - ALWAYS_AVAILABLE
            if missing:
                errors.append(f"Блок {i}: нет инвентаря {', '.join(sorted(missing))}.")
            if nd.players_min > req.players:
                errors.append(f"Блок {i}: новому упражнению нужно больше игроков, чем есть.")
    if ans.blocks:
        total = sum(b.duration_min for b in ans.blocks)
        if abs(total - req.duration_min) > max(2, round(req.duration_min * 0.05)):
            errors.append(f"Сумма длительностей блоков {total} мин, а занятие длится {req.duration_min} мин.")
    bad = sorted({mt.group(0) for t in _texts(ans) for mt in FORBIDDEN.finditer(t)})
    if bad:
        errors.append(
            f"Недопустимые формулировки: {', '.join(bad)}. "
            "Не обещай результат и не делай медицинских утверждений."
        )
    return ans, errors


def autofix(ans: AIAnswer, req: PlanRequest, aliases: dict[str, m.Drill]) -> tuple[AIAnswer, list[str]]:
    """Исправление кодом того, что модель не исправила сама."""
    warnings = []
    blocks = []
    for b in ans.blocks:
        ok = (b.drill_id in aliases and aliases[b.drill_id].players_min <= req.players and b.new_drill is None) or (
            b.drill_id is None and b.new_drill is not None
            and not (set(b.new_drill.equipment) - set(req.equipment) - ALWAYS_AVAILABLE)
            and b.new_drill.players_min <= req.players
        )
        if ok:
            blocks.append(b)
    if len(blocks) < len(ans.blocks):
        warnings.append("Часть предложенных блоков не подошла и была убрана.")
    total = sum(b.duration_min for b in blocks)
    if blocks and total != req.duration_min:
        scale = req.duration_min / total
        for b in blocks:
            b.duration_min = max(1, round(b.duration_min * scale))
        diff = req.duration_min - sum(b.duration_min for b in blocks)
        main = max(blocks, key=lambda b: b.duration_min)
        main.duration_min = max(1, main.duration_min + diff)
        warnings.append("Длительности блоков пересчитаны под длительность занятия.")

    def clean(s: str) -> str:
        parts = re.split(r"(?<=[.!?])\s+", s)
        return " ".join(p for p in parts if not FORBIDDEN.search(p))

    ans.title = clean(ans.title) or "Тренировка"
    ans.assumptions = [clean(a) for a in ans.assumptions if clean(a)]
    for b in blocks:
        b.adaptation = clean(b.adaptation)
        if b.new_drill:
            nd = b.new_drill
            nd.goal, nd.setup = clean(nd.goal), clean(nd.setup)
            for f in ("steps", "rules", "coaching_points", "success_criteria", "easier", "harder"):
                setattr(nd, f, [clean(x) for x in getattr(nd, f) if clean(x)])
    ans.blocks = blocks
    return ans, warnings


# ------------------------------------------------------------------ сборка результата


def drill_snapshot(d: m.Drill) -> dict:
    return jsonable_encoder({k: getattr(d, k) for k in DrillData.model_fields})


def to_blocks(ans: AIAnswer, aliases: dict[str, m.Drill]) -> list[TrainingBlock]:
    out = []
    for i, b in enumerate(ans.blocks, 1):
        if b.drill_id:
            d = aliases[b.drill_id]
            out.append(TrainingBlock(id=f"b{i}", phase=b.phase, title=d.title, duration_min=b.duration_min,
                                     drill_id=d.id, drill=drill_snapshot(d), notes=b.adaptation))
        else:
            nd = b.new_drill
            data = DrillData.model_validate({
                **nd.model_dump(exclude={"easier", "harder"}),
                "source": "ai", "duration_min": b.duration_min,
                "variants": {"easier": nd.easier, "harder": nd.harder},
            }).model_dump(mode="json")
            out.append(TrainingBlock(id=f"b{i}", phase=b.phase, title=nd.title, duration_min=b.duration_min,
                                     drill=data, notes=b.adaptation))
    return out


async def generate_plan(db: AsyncSession, provider: LLMProvider, owner_id, req: PlanRequest) -> PlanOut:
    candidates = await select_candidates(db, owner_id, req)
    history, recent, names = await team_history(db, owner_id, req.team_id)
    scrub = name_scrubber(names)
    aliases = {f"c{i}": d for i, d in enumerate(candidates, 1)}
    warnings: list[str] = []

    def by_rules(reason: str | None) -> PlanOut:
        recent_alias = {a for a, d in aliases.items() if d.id in recent}
        plan = rules.plan_by_rules(
            {"duration_min": req.duration_min, "goal": req.goal, "focus": req.focus},
            [{"id": a, "category": d.category} for a, d in aliases.items()],
            recent_alias,
        )
        ans = AIAnswer.model_validate(plan)
        return PlanOut(title=ans.title, blocks=to_blocks(ans, aliases), assumptions=ans.assumptions,
                       clarifying_question=None, source="rules", warnings=warnings + ([reason] if reason else []))

    if not aliases:
        raise ValueError("В библиотеке нет упражнений под эти параметры. Уменьшите требования к инвентарю или составу.")
    if not req.use_ai:
        return by_rules(None)

    reserved = await quota.reserve(db, owner_id)
    if reserved is False:
        return by_rules("Лимит AI-генераций на этот месяц исчерпан — план собран по правилам из библиотеки.")

    user_prompt = build_prompt(req, aliases, history, scrub)
    entry = m.AIRequest(user_id=owner_id, kind="plan", provider=provider.name, model="")
    started = time.monotonic()
    try:
        comp = await provider.complete(SYSTEM_PROMPT, user_prompt)
        entry.model, entry.tokens_in, entry.tokens_out = comp.model, comp.tokens_in, comp.tokens_out
        ans, errors = validate_answer(comp.text, req, aliases)
        if errors:
            entry.attempts = 2
            fix_prompt = (user_prompt + "\n\nТвой предыдущий ответ:\n" + comp.text[:6000]
                          + "\n\nИсправь ошибки и верни полный JSON заново:\n- " + "\n- ".join(errors))
            comp2 = await provider.complete(SYSTEM_PROMPT, fix_prompt, temperature=0.2)
            entry.tokens_in += comp2.tokens_in
            entry.tokens_out += comp2.tokens_out
            ans2, errors2 = validate_answer(comp2.text, req, aliases)
            if ans2 is not None:
                ans, errors = ans2, errors2
        if ans is None:
            raise ProviderError("invalid json after repair: " + "; ".join(errors))
        if errors:
            ans, fix_warnings = autofix(ans, req, aliases)
            warnings += fix_warnings
            entry.error = "; ".join(errors)[:1000]
        if not ans.blocks and not ans.clarifying_question:
            raise ProviderError("empty plan after autofix")
        entry.valid = True
        return PlanOut(title=ans.title, blocks=to_blocks(ans, aliases), assumptions=ans.assumptions,
                       clarifying_question=ans.clarifying_question if not ans.blocks else None,
                       source="ai", warnings=warnings)
    except ProviderError as e:
        log.warning("AI plan failed: %s", e)
        entry.error = str(e)[:1000]
        return by_rules("AI сейчас недоступен — план собран по правилам из библиотеки. Попробуйте позже.")
    finally:
        entry.latency_ms = int((time.monotonic() - started) * 1000)
        if reserved and not entry.valid:
            await quota.release(db, owner_id)
        db.add(entry)
        await db.commit()
