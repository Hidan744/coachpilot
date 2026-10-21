"""AI-оформление отчёта после тренировки.

Тренер отвечает на вопросы или диктует заметку — модель раскладывает текст по разделам
и отдельно предлагает следующие шаги. Наблюдения тренера и предположения модели
хранятся раздельно (ai_suggestions), отчёт подтверждает тренер.

Имена игроков заменяются псевдонимами (Игрок_1…) и восстанавливаются в ответе:
в AI-сервис персональные данные не уходят, а в отчёте остаются понятными тренеру.
"""

import re
import time
import uuid

from pydantic import BaseModel, Field, ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.ai.planner import FORBIDDEN, extract_json, stem
from app.ai.providers import LLMProvider, ProviderError
from app.ai.quota import quota_ok

SYSTEM_PROMPT = """Ты помогаешь футбольному тренеру оформить отчёт о проведённом занятии на русском языке.
Используй только то, что написал тренер, и данные о занятии. Не придумывай факты, оценки и показатели игроков.
Разложи текст тренера по разделам:
- went_well: что получилось;
- to_improve: что нужно улучшить;
- observations: прочие наблюдения (по игрокам, группе, условиям).
Пиши кратко, списком через «• » с новой строки, сохраняя смысл слов тренера.
Отдельно в suggestions предложи 2–4 конкретных шага для следующих тренировок. Это твои предположения,
формулируй их как предложения («Можно…», «Стоит попробовать…»). Не обещай результат, не давай медицинских советов.
Обозначения вида Игрок_1 оставляй без изменений.
Ответь строго JSON: {"went_well": "...", "to_improve": "...", "observations": "...", "suggestions": ["..."]}"""


class ReportRequest(BaseModel):
    session_id: uuid.UUID
    raw_input: str = Field(default="", max_length=6000)
    went_well: str = Field(default="", max_length=3000)
    to_improve: str = Field(default="", max_length=3000)
    observations: str = Field(default="", max_length=3000)
    rating: int | None = Field(default=None, ge=1, le=5)


class ReportOut(BaseModel):
    went_well: str
    to_improve: str
    observations: str
    suggestions: list[str]
    source: str
    warnings: list[str] = []


class _AIReport(BaseModel):
    went_well: str = Field(default="", max_length=3000)
    to_improve: str = Field(default="", max_length=3000)
    observations: str = Field(default="", max_length=3000)
    suggestions: list[str] = Field(default_factory=list, max_length=6)


class Pseudonymizer:
    """Обратимая замена имён игроков на «Игрок_N»."""

    def __init__(self, players: list[m.Player]):
        self.forward: list[tuple[re.Pattern, str]] = []
        self.back: dict[str, str] = {}
        for i, p in enumerate(players, 1):
            token = f"Игрок_{i}"
            self.back[token] = p.first_name if not p.last_name else f"{p.first_name} {p.last_name}"
            words = [w for w in (f"{p.first_name} {p.last_name}".strip(), p.last_name, p.first_name) if len(w) >= 3]
            for w in words:
                # Имя и его падежные формы: «Саша», «Саше», «Сашей».
                self.forward.append((re.compile(rf"\b{re.escape(stem(w))}\w*", re.IGNORECASE), token))

    def hide(self, s: str) -> str:
        for rx, token in self.forward:
            s = rx.sub(token, s)
        return s

    def restore(self, s: str) -> str:
        return re.sub(r"Игрок_\d+", lambda mt: self.back.get(mt.group(0), mt.group(0)), s)


def _clean(s: str) -> str:
    parts = re.split(r"(?<=[.!?\n])\s*", s)
    return " ".join(p for p in parts if p and not FORBIDDEN.search(p)).strip() if FORBIDDEN.search(s) else s


async def structure_report(db: AsyncSession, provider: LLMProvider, owner_id, req: ReportRequest) -> ReportOut:
    s = await db.scalar(select(m.TrainingSession).where(
        m.TrainingSession.id == req.session_id, m.TrainingSession.owner_id == owner_id))
    if s is None:
        raise LookupError("Занятие не найдено. Дождитесь синхронизации и попробуйте снова.")
    players = []
    if s.team_id:
        players = list(await db.scalars(select(m.Player).where(m.Player.owner_id == owner_id,
                                                               m.Player.team_id == s.team_id)))
    ps = Pseudonymizer(players)
    notes = list(await db.scalars(select(m.SessionNote).where(
        m.SessionNote.session_id == s.id, m.SessionNote.deleted_at.is_(None)).order_by(m.SessionNote.noted_at)))
    actual = (s.actual or {}).get("blocks", {})
    skipped = set((s.actual or {}).get("skipped", []))
    blocks = [
        f"- {b['title']}: план {b['duration_min']} мин"
        + (f", факт {round(actual[b['id']] / 60)} мин" if b["id"] in actual else "")
        + (" (пропущен)" if b["id"] in skipped else "")
        for b in s.blocks or []
    ]
    user_prompt = "\n".join([
        f"Цель занятия: {ps.hide(s.goal) or 'не указана'}",
        "Блоки занятия:", *blocks,
        "Заметки во время занятия:", *([f"- {ps.hide(n.text)}" for n in notes] or ["- нет"]),
        f"Оценка занятия тренером: {req.rating or 'нет'} из 5",
        f"Что получилось (тренер): {ps.hide(req.went_well) or '—'}",
        f"Что улучшить (тренер): {ps.hide(req.to_improve) or '—'}",
        f"Наблюдения (тренер): {ps.hide(req.observations) or '—'}",
        f"Свободная заметка тренера: {ps.hide(req.raw_input) or '—'}",
    ])

    entry = m.AIRequest(user_id=owner_id, kind="report", provider=provider.name, model="")
    started = time.monotonic()
    try:
        ok, sub = await quota_ok(db, owner_id)
        if not ok:
            entry.error = "quota"
            return ReportOut(went_well=req.went_well, to_improve=req.to_improve, observations=req.observations,
                             suggestions=[], source="manual",
                             warnings=["Лимит AI-генераций на этот месяц исчерпан — заполните отчёт вручную."])
        comp = await provider.complete(SYSTEM_PROMPT, user_prompt, temperature=0.3)
        entry.model, entry.tokens_in, entry.tokens_out = comp.model, comp.tokens_in, comp.tokens_out
        try:
            rep = _AIReport.model_validate(extract_json(comp.text))
        except (ValueError, ValidationError) as e:
            raise ProviderError(f"invalid report json: {e}") from e
        entry.valid = True
        if sub is not None:
            sub.ai_used += 1
        return ReportOut(
            went_well=ps.restore(_clean(rep.went_well)),
            to_improve=ps.restore(_clean(rep.to_improve)),
            observations=ps.restore(_clean(rep.observations)),
            suggestions=[ps.restore(_clean(x)) for x in rep.suggestions if _clean(x)],
            source="ai",
        )
    except ProviderError as e:
        entry.error = str(e)[:1000]
        return ReportOut(went_well=req.went_well, to_improve=req.to_improve,
                         observations="\n".join(filter(None, [req.observations, req.raw_input])),
                         suggestions=[], source="manual",
                         warnings=["AI сейчас недоступен — текст перенесён в отчёт без обработки."])
    finally:
        entry.latency_ms = int((time.monotonic() - started) * 1000)
        db.add(entry)
        await db.commit()
