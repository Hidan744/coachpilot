from app.ratelimit import RateLimiter
from tests.conftest import make_user


async def test_events_ingest(client):
    h, _ = await make_user(client)
    body = {"platform": "android", "app_version": "0.1.0", "events": [
        {"name": "plan_saved", "props": {"ai": True, "edited": 2}, "ts": "2026-10-19T10:00:00Z"},
        {"name": "app_error", "props": {"message": "boom"}, "ts": "2026-10-19T10:01:00Z"},
    ]}
    assert (await client.post("/events", headers=h, json=body)).status_code == 204
    bad = {"events": [{"name": "Bad Name!", "ts": "2026-10-19T10:00:00Z"}]}
    assert (await client.post("/events", headers=h, json=bad)).status_code == 422
    huge = {"events": [{"name": "x_y", "props": {"s": "a" * 3000}, "ts": "2026-10-19T10:00:00Z"}]}
    assert (await client.post("/events", headers=h, json=huge)).status_code == 422
    assert (await client.post("/events", json=body)).status_code == 401


async def test_login_rate_limited(client):
    await make_user(client)
    for _ in range(10):
        r = await client.post("/auth/login", json={"email": "coach@example.com", "password": "wrong-pass"})
        assert r.status_code == 401
    r = await client.post("/auth/login", json={"email": "coach@example.com", "password": "secret123"})
    assert r.status_code == 429


def test_rate_limiter_window():
    rl = RateLimiter(limit=2, window_sec=60)
    assert rl.hit("k") and rl.hit("k") and not rl.hit("k")
    rl.reset("k")
    assert rl.hit("k")


async def test_request_id_header(client):
    r = await client.get("/health")
    assert len(r.headers["x-request-id"]) >= 8


def test_prod_settings_reject_wildcard_cors():
    import pytest

    from app.config import Settings
    from app.main import check_prod_settings

    secret = "x" * 40
    check_prod_settings(Settings(env="dev", cors_origins=["*"]))
    check_prod_settings(Settings(env="prod", jwt_secret=secret, cors_origins=["https://app.example.ru"]))
    with pytest.raises(RuntimeError, match="CORS"):
        check_prod_settings(Settings(env="prod", jwt_secret=secret, cors_origins=["*"]))
    with pytest.raises(RuntimeError, match="JWT"):
        check_prod_settings(Settings(env="prod", cors_origins=["https://app.example.ru"]))
