import itertools
import json
import uuid

import pytest
from sqlalchemy import select

from app import models as m
from app.ai.planner import AGE_BY_GROUP, team_age
from app.ai.providers import MockProvider
from app.catalog.seed import seed
from app.db import SessionLocal
from app.main import app
from app.routers.ai import get_provider
from tests.conftest import make_user


@pytest.fixture
async def seeded():
    async with SessionLocal() as db:
        await seed(db)


@pytest.fixture
def provider():
    p = MockProvider()
    app.dependency_overrides[get_provider] = lambda: p
    yield p
    app.dependency_overrides.pop(get_provider, None)


def req(**kw):
    base = {"age_group": "U12", "players": 14, "duration_min": 75, "goal": "Передачи в одно касание",
            "equipment": ["balls", "cones", "bibs", "goals", "mini_goals"]}
    return base | kw


async def plan(client, h, **kw):
    r = await client.post("/ai/plan", headers=h, json=req(**kw))
    assert r.status_code == 200, r.text
    return r.json()


def candidate_ids(provider) -> dict[str, dict]:
    payload = json.loads(provider.calls[-1][1].split("ДАННЫЕ:", 1)[1])
    return {c["id"]: c for c in payload["candidates"]}


async def test_plan_valid(client, seeded, provider):
    h, _ = await make_user(client)
    p = await plan(client, h)
    assert p["source"] == "ai" and p["warnings"] == []
    assert sum(b["duration_min"] for b in p["blocks"]) == 75
    assert p["blocks"][0]["phase"] == "warmup"
    assert any(b["phase"] == "main" and b["drill"]["category"] in ("passing", "possession") for b in p["blocks"])
    for b in p["blocks"]:
        assert b["drill"]["steps"] and b["drill_id"]
    async with SessionLocal() as db:
        log = (await db.scalars(select(m.AIRequest))).all()
        sub = (await db.scalars(select(m.Subscription))).one()
    assert log[0].valid and log[0].provider == "mock"
    assert sub.ai_used == 1


@pytest.mark.parametrize("case", list(itertools.islice(itertools.product(
    ["U7", "U9", "U12", "U15", "adult"],
    [6, 10, 16, 22],
    [45, 60, 90],
    ["Удары по воротам", "Владение мячом", "Обводка 1×1", "Оборона и отбор", "Переходы"],
), 0, None, 15)))
async def test_quality_20_requests(client, seeded, provider, case):
    """Набор разных запросов: каждый план проходит проверки качества."""
    age_group, players, duration, goal = case
    h, _ = await make_user(client, email=f"q{uuid.uuid4().hex[:8]}@t.ru")
    equipment = ["balls", "cones", "bibs"] if players < 10 else ["balls", "cones", "bibs", "goals", "mini_goals"]
    p = await plan(client, h, age_group=age_group, players=players, duration_min=duration, goal=goal,
                   equipment=equipment)
    assert p["blocks"], p
    assert sum(b["duration_min"] for b in p["blocks"]) == duration
    age = team_age(age_group)
    for b in p["blocks"]:
        d = b["drill"]
        assert d["age_min"] <= age <= d["age_max"], (b["title"], age)
        assert d["players_min"] <= players, (b["title"], players)
        assert set(d["equipment"]) <= set(equipment) | {"balls", "cones"}
        assert d["steps"] and d["coaching_points"]


async def test_repair_then_valid(client, seeded, provider):
    h, _ = await make_user(client)
    await plan(client, h)  # заполняет кандидатов для ответа
    ids = list(candidate_ids(provider))
    bad = {"title": "T", "blocks": [{"phase": "warmup", "duration_min": 10, "drill_id": "c999"},
                                    {"phase": "main", "duration_min": 10, "drill_id": ids[5]}]}
    good = {"title": "Передачи", "blocks": [{"phase": "warmup", "duration_min": 15, "drill_id": ids[0]},
                                            {"phase": "main", "duration_min": 60, "drill_id": ids[5]}]}
    provider.scripted = [json.dumps(bad), json.dumps(good)]
    p = await plan(client, h)
    assert p["source"] == "ai" and p["warnings"] == [] and len(p["blocks"]) == 2
    fix_prompt = provider.calls[-1][1]
    assert "c999 нет среди кандидатов" in fix_prompt and "Сумма длительностей блоков 20 мин" in fix_prompt
    async with SessionLocal() as db:
        last = (await db.scalars(select(m.AIRequest).order_by(m.AIRequest.created_at.desc()))).first()
    assert last.attempts == 2 and last.valid


async def test_autofix_after_failed_repair(client, seeded, provider):
    h, _ = await make_user(client)
    await plan(client, h)
    ids = list(candidate_ids(provider))
    bad = {"title": "T", "blocks": [
        {"phase": "warmup", "duration_min": 10, "drill_id": ids[0],
         "adaptation": "Темп средний. Упражнение гарантирует прогресс."},
        {"phase": "main", "duration_min": 20, "drill_id": ids[4]},
        {"phase": "main", "duration_min": 20, "drill_id": "c404"},
    ]}
    provider.scripted = [json.dumps(bad), json.dumps(bad)]
    p = await plan(client, h)
    assert p["source"] == "ai"
    assert len(p["blocks"]) == 2
    assert sum(b["duration_min"] for b in p["blocks"]) == 75
    assert "гарантир" not in json.dumps(p, ensure_ascii=False)
    assert p["blocks"][0]["notes"] == "Темп средний."
    assert any("пересчитаны" in w for w in p["warnings"])


async def test_new_drill_from_model(client, seeded, provider):
    h, _ = await make_user(client)
    await plan(client, h)
    ids = list(candidate_ids(provider))
    ans = {"title": "T", "blocks": [
        {"phase": "warmup", "duration_min": 15, "drill_id": ids[0]},
        {"phase": "main", "duration_min": 60, "new_drill": {
            "title": "Квадрат с переменой фланга", "category": "passing", "setup": "Квадрат 20×20, две команды.",
            "steps": ["Пас по кругу", "Смена фланга по сигналу"], "coaching_points": ["Открывание"],
            "equipment": ["balls", "cones"], "players_min": 8}},
    ]}
    provider.scripted = [json.dumps(ans)]
    p = await plan(client, h)
    nd = p["blocks"][1]
    assert nd["drill_id"] is None and nd["drill"]["source"] == "ai" and nd["title"] == "Квадрат с переменой фланга"


async def test_clarifying_question(client, seeded, provider):
    h, _ = await make_user(client)
    provider.scripted = [json.dumps({"clarifying_question": "Сколько вратарей будет на занятии?", "blocks": []})]
    p = await plan(client, h)
    assert p["clarifying_question"] == "Сколько вратарей будет на занятии?" and p["blocks"] == []


async def test_provider_failure_falls_back_to_rules(client, seeded):
    app.dependency_overrides[get_provider] = lambda: MockProvider(fail=True)
    try:
        h, _ = await make_user(client)
        p = await plan(client, h)
    finally:
        app.dependency_overrides.pop(get_provider, None)
    assert p["source"] == "rules" and "недоступен" in p["warnings"][0]
    assert sum(b["duration_min"] for b in p["blocks"]) == 75
    async with SessionLocal() as db:
        log = (await db.scalars(select(m.AIRequest))).one()
        sub = (await db.scalars(select(m.Subscription))).one()
    assert not log.valid and "mock failure" in log.error and sub.ai_used == 0


async def test_garbage_twice_falls_back(client, seeded, provider):
    h, _ = await make_user(client)
    provider.scripted = ["не json", "{тоже нет"]
    p = await plan(client, h)
    assert p["source"] == "rules" and p["blocks"]


async def test_quota_exceeded(client, seeded, provider):
    h, tokens = await make_user(client)
    async with SessionLocal() as db:
        sub = (await db.scalars(select(m.Subscription))).one()
        sub.ai_used = sub.ai_quota_month
        await db.commit()
    p = await plan(client, h)
    assert p["source"] == "rules" and "Лимит" in p["warnings"][0]
    assert provider.calls == []
    q = (await client.get("/ai/quota", headers=h)).json()
    assert q["used"] == q["limit"] == 30


async def test_rules_mode_without_ai(client, seeded, provider):
    h, _ = await make_user(client)
    p = await plan(client, h, use_ai=False)
    assert p["source"] == "rules" and provider.calls == []


async def test_player_names_not_sent_to_ai(client, seeded, provider):
    h, _ = await make_user(client)
    t, pl, s = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    changes = [
        {"entity": "teams", "id": str(t), "op": "upsert",
         "data": {"name": "T", "age_group": "U12", "level": "amateur", "default_players": 14}},
        {"entity": "players", "id": str(pl), "op": "upsert",
         "data": {"team_id": str(t), "first_name": "Святослав", "last_name": "Пономарёв"}},
        {"entity": "training_sessions", "id": str(s), "op": "upsert",
         "data": {"team_id": str(t), "title": "S", "duration_min": 60, "status": "done", "goal": "Передачи"}},
        {"entity": "session_reports", "id": str(uuid.uuid4()), "op": "upsert",
         "data": {"session_id": str(s), "coach_confirmed": True, "went_well": "Святослав хорошо открывался",
                  "to_improve": "Пономарёву — первое касание"}},
    ]
    res = (await client.post("/sync/push", headers=h, json={"changes": changes})).json()["results"]
    assert all(r["status"] == "applied" for r in res)
    await plan(client, h, team_id=str(t), constraints="Святослав после травмы, без рывков; Святославу без контакта")
    prompt = provider.calls[-1][1]
    assert "Святослав" not in prompt and "Пономар" not in prompt
    assert "игрок хорошо открывался" in prompt and "игрок после травмы" in prompt


async def test_validation_errors(client, seeded, provider):
    h, _ = await make_user(client)
    r = await client.post("/ai/plan", headers=h, json=req(goal="", duration_min=5))
    assert r.status_code == 422


def test_team_age():
    assert team_age("U9") == 9 and team_age("adult") == AGE_BY_GROUP["adult"]


async def _session_with_players(client, h):
    t, p1, p2, s = uuid.uuid4(), uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    changes = [
        {"entity": "teams", "id": str(t), "op": "upsert",
         "data": {"name": "T", "age_group": "U12", "level": "amateur", "default_players": 14}},
        {"entity": "players", "id": str(p1), "op": "upsert", "data": {"team_id": str(t), "first_name": "Саша",
                                                                        "last_name": "Петров"}},
        {"entity": "players", "id": str(p2), "op": "upsert", "data": {"team_id": str(t), "first_name": "Миша"}},
        {"entity": "training_sessions", "id": str(s), "op": "upsert", "data": {
            "team_id": str(t), "title": "S", "duration_min": 60, "status": "done", "goal": "Передачи",
            "blocks": [{"id": "b1", "phase": "main", "title": "Рондо", "duration_min": 60}],
            "actual": {"blocks": {"b1": 3300}, "skipped": []}}},
        {"entity": "session_notes", "id": str(uuid.uuid4()), "op": "upsert", "data": {
            "session_id": str(s), "block_id": "b1", "text": "Мише тяжело в отборе",
            "noted_at": "2026-10-19T18:20:00Z"}},
    ]
    res = (await client.post("/sync/push", headers=h, json={"changes": changes})).json()["results"]
    assert all(r["status"] == "applied" for r in res), res
    return s


async def test_report_pseudonymized_and_restored(client, provider):
    h, _ = await make_user(client)
    s = await _session_with_players(client, h)
    r = await client.post("/ai/report", headers=h, json={
        "session_id": str(s), "went_well": "Саша Петров отлично открывался", "to_improve": "Первое касание",
        "raw_input": "Сашу хвалил за темп", "rating": 4})
    assert r.status_code == 200, r.text
    out = r.json()
    prompt = provider.calls[-1][1]
    for name in ("Саша", "Сашу", "Петров", "Мише"):
        assert name not in prompt, name
    assert "Игрок_1 отлично открывался" in prompt and "факт 55 мин" in prompt
    # имена вернулись в текст отчёта
    assert "Саша Петров отлично открывался" in out["went_well"]
    assert "Миша" in out["observations"]
    assert out["source"] == "ai" and out["suggestions"]


async def test_report_fallback_and_unknown_session(client):
    app.dependency_overrides[get_provider] = lambda: MockProvider(fail=True)
    try:
        h, _ = await make_user(client)
        s = await _session_with_players(client, h)
        out = (await client.post("/ai/report", headers=h, json={
            "session_id": str(s), "went_well": "Темп", "raw_input": "Сыро в обороне"})).json()
        assert out["source"] == "manual" and out["went_well"] == "Темп" and "Сыро" in out["observations"]
        assert out["warnings"]
        r = await client.post("/ai/report", headers=h, json={"session_id": str(uuid.uuid4())})
        assert r.status_code == 404
    finally:
        app.dependency_overrides.pop(get_provider, None)


async def test_drills_parse_ai_and_fallback(client, provider):
    h, _ = await make_user(client)
    text = "Квадрат 4 на 2\nЧетверо держат мяч\nДвое отбирают\n\nУдары после обводки\nОбвести стойку и ударить"
    out = (await client.post("/ai/drills/parse", headers=h, json={"text": text})).json()
    assert out["source"] == "ai"
    assert [d["title"] for d in out["drills"]] == ["Квадрат 4 на 2", "Удары после обводки"]
    assert out["drills"][0]["steps"] == ["Четверо держат мяч", "Двое отбирают"]
    assert out["drills"][0]["source"] == "user"

    # модель вернула мусор и недопустимые значения — категория и поля нормализуются
    provider.scripted = [json.dumps({"drills": [{"title": "Рывки", "category": "unknown", "steps": ["Старт"],
                                                  "duration_min": 500, "equipment": ["balls", "laser"],
                                                  "coaching_points": ["Гарантирует рост скорости",
                                                                      "Наклон корпуса"]}]})]
    d = (await client.post("/ai/drills/parse", headers=h, json={"text": text})).json()["drills"][0]
    assert d["category"] == "technique" and d["duration_min"] == 120 and d["equipment"] == ["balls"]
    assert d["coaching_points"] == ["Наклон корпуса"]

    provider.scripted = ["не json"]
    out = (await client.post("/ai/drills/parse", headers=h, json={"text": text})).json()
    assert out["source"] == "manual" and out["drills"] == [] and out["warnings"]
