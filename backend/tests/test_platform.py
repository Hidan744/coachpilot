import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app import models as m
from app import notify
from app.config import get_settings
from app.db import SessionLocal
from tests.conftest import make_user
from tests.test_sync import push, team, up


@pytest.fixture
def settings():
    st = get_settings()
    saved = st.model_dump()
    yield st
    for k, v in saved.items():
        setattr(st, k, v)


class FakeTelegram:
    name = "telegram"

    def __init__(self, fail=False):
        self.sent, self.fail = [], fail

    def configured(self):
        return True

    async def send(self, address, text):
        if self.fail:
            raise notify.SendFailed("down")
        self.sent.append((address, text))


@pytest.fixture
def telegram():
    fake = FakeTelegram()
    real = notify.channel("telegram")
    notify.set_channel("telegram", fake)
    yield fake
    notify.set_channel("telegram", real)


async def test_plans_from_config_and_no_fake_payments(client, settings):
    settings.price_pro_rub_month = 1234
    r = (await client.get("/billing/plans")).json()
    assert r["currency"] == "RUB" and r["payments"] == "off"
    assert {p["code"]: p["price_rub_month"] for p in r["plans"]}["pro"] == 1234
    h, _ = await make_user(client)
    me = (await client.get("/billing/me", headers=h)).json()
    assert me["plan"]["code"] == "free" and me["ai_limit"] == settings.ai_free_quota_month
    r = await client.post("/billing/checkout", headers=h, json={"plan": "pro"})
    assert r.status_code == 503 and "не подключена" in r.json()["detail"]


async def test_test_payments_mode_only_outside_production(client, settings):
    h, _ = await make_user(client)
    settings.payments_mode = "test"
    r = await client.post("/billing/checkout", headers=h, json={"plan": "pro"})
    assert r.status_code == 200 and r.json()["test"] and r.json()["ai_limit"] == settings.ai_pro_quota_month
    assert (await client.get("/ai/quota", headers=h)).json()["plan"] == "pro"
    settings.env = "production"
    r = await client.post("/billing/checkout", headers=h, json={"plan": "academy"})
    assert r.status_code == 503


async def test_integrations_status_is_honest(client, settings):
    h, _ = await make_user(client)
    s = (await client.get("/integrations/status", headers=h)).json()
    assert s["telegram"]["status"] == "not_configured"
    assert s["payments"]["status"] == "not_configured"
    assert s["ai"]["status"] == "not_configured"  # mock-провайдер — не настоящий AI
    r = await client.post("/notifications/telegram/link", headers=h)
    assert r.status_code == 503


async def test_telegram_link_test_message_and_reminders(client, settings, telegram):
    settings.telegram_bot_token, settings.telegram_bot_username = "x", "coachpilot_bot"
    settings.telegram_webhook_secret, settings.cron_secret = "hook", "cron"
    h, _ = await make_user(client)
    assert (await client.post("/notifications/telegram/test", headers=h)).status_code == 409
    url = (await client.post("/notifications/telegram/link", headers=h)).json()["url"]
    code = url.split("start=")[1]
    assert (await client.post("/telegram/webhook/wrong", json={})).status_code == 404
    upd = {"message": {"text": f"/start {code}", "chat": {"id": 555}}}
    assert (await client.post("/telegram/webhook/hook", json=upd)).status_code == 200
    assert (await client.get("/notifications/telegram", headers=h)).json()["linked"] is True
    assert (await client.post("/notifications/telegram/test", headers=h)).json()["sent"]

    tid = uuid.uuid4()
    soon = (datetime.now(UTC) + timedelta(hours=3)).isoformat()
    await push(client, h, up("teams", tid, team()),
               up("training_sessions", uuid.uuid4(), {"team_id": str(tid), "title": "Квадраты", "duration_min": 60,
                                                      "status": "planned", "scheduled_at": soon}),
               up("matches", uuid.uuid4(), {"team_id": str(tid), "opponent": "Динамо", "starts_at": soon}))
    assert (await client.post("/notifications/reminders/run")).status_code == 403
    r = (await client.post("/notifications/reminders/run", headers={"X-Cron-Secret": "cron"})).json()
    assert r["sent"] == 2
    r = (await client.post("/notifications/reminders/run", headers={"X-Cron-Secret": "cron"})).json()
    assert r["sent"] == 0  # повторно не шлём
    texts = [t for _, t in telegram.sent]
    assert any("Квадраты" in t for t in texts) and any("Динамо" in t for t in texts)
    async with SessionLocal() as db:
        actions = [a.action for a in await db.scalars(select(m.AuditLog))]
    assert "telegram_linked" in actions


async def test_failed_send_is_not_reported_as_sent(client, settings):
    settings.telegram_bot_token, settings.cron_secret = "x", "cron"
    fake = FakeTelegram(fail=True)
    real = notify.channel("telegram")
    notify.set_channel("telegram", fake)
    try:
        h, _ = await make_user(client)
        uid = uuid.UUID((await client.get("/me", headers=h)).json()["id"])
        async with SessionLocal() as db:
            db.add(m.TelegramLink(user_id=uid, chat_id=1))
            await db.commit()
        r = await client.post("/notifications/telegram/test", headers=h)
        assert r.status_code == 502
    finally:
        notify.set_channel("telegram", real)


async def test_retention_purge(client, settings):
    from app.maintenance import purge

    h, _ = await make_user(client)
    tid = uuid.uuid4()
    await push(client, h, up("teams", tid, team()))
    await client.post("/sync/push", headers=h, json={"changes": [{"entity": "teams", "id": str(tid), "op": "delete"}]})
    async with SessionLocal() as db:
        assert (await purge(db)).get("teams") is None  # недавно удалено — ещё нужно для синхронизации
        out = await purge(db, now=datetime.now(UTC) + timedelta(days=settings.retention_deleted_days + 1))
        assert out["teams"] == 1
        assert await db.get(m.Team, tid) is None
