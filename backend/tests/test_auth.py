from tests.conftest import make_user


async def test_health(client):
    r = await client.get("/health")
    assert r.json() == {"status": "ok"}


async def test_register_login_me(client):
    headers, _ = await make_user(client, email="Coach@Example.com")
    r = await client.get("/me", headers=headers)
    assert r.status_code == 200
    assert r.json()["email"] == "coach@example.com"

    r = await client.post("/auth/login", json={"email": "COACH@example.com", "password": "secret123"})
    assert r.status_code == 200


async def test_register_requires_consent(client):
    r = await client.post(
        "/auth/register",
        json={"email": "a@b.ru", "password": "secret123", "name": "A", "consent_personal_data": False},
    )
    assert r.status_code == 422


async def test_duplicate_email(client):
    await make_user(client)
    r = await client.post(
        "/auth/register",
        json={"email": "coach@example.com", "password": "secret123", "name": "B",
              "consent_personal_data": True},
    )
    assert r.status_code == 409


async def test_wrong_password_and_unknown_email(client):
    await make_user(client)
    for email, pw in [("coach@example.com", "wrong-pass"), ("nobody@example.com", "secret123")]:
        r = await client.post("/auth/login", json={"email": email, "password": pw})
        assert r.status_code == 401


async def test_protected_requires_token(client):
    assert (await client.get("/me")).status_code == 401
    r = await client.get("/me", headers={"Authorization": "Bearer garbage"})
    assert r.status_code == 401


async def test_refresh_rotation(client):
    _, tokens = await make_user(client)
    r = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    # старый refresh-токен одноразовый
    r2 = await client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r2.status_code == 401
    # logout отзывает новый
    new_refresh = r.json()["refresh_token"]
    assert (await client.post("/auth/logout", json={"refresh_token": new_refresh})).status_code == 204
    r3 = await client.post("/auth/refresh", json={"refresh_token": new_refresh})
    assert r3.status_code == 401


async def test_update_profile(client):
    headers, _ = await make_user(client)
    r = await client.patch("/me", headers=headers, json={"city": "Казань", "coaching_level": "UEFA C"})
    assert r.status_code == 200
    assert r.json()["city"] == "Казань"


def test_rate_limiter_overflow_keeps_active_keys():
    from app.ratelimit import RateLimiter

    rl = RateLimiter(limit=2, window_sec=60, max_keys=3)
    assert rl.hit("victim") and rl.hit("victim")
    for i in range(10):  # атакующий заваливает словарь новыми ключами
        rl.hit(f"junk{i}")
    assert not rl.hit("victim")  # счётчик жертвы не сброшен


async def _login_from(ip: str, email: str):
    from httpx import ASGITransport, AsyncClient

    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app, client=(ip, 1234)), base_url="http://test") as c:
        return (await c.post("/auth/login", json={"email": email, "password": "wrong-pass"})).status_code


async def test_login_limited_by_ip_across_emails(client):
    codes = [await _login_from("10.0.0.1", f"u{i}@example.com") for i in range(21)]
    assert codes[:20] == [401] * 20 and codes[20] == 429
    assert await _login_from("10.0.0.2", "u0@example.com") == 401  # другой адрес не заблокирован


async def test_login_email_limit_is_short_and_does_not_lock_owner_for_long(client):
    import app.ratelimit as rl

    await make_user(client, email="coach2@example.com")
    codes = [await _login_from(f"10.1.0.{i}", "coach2@example.com") for i in range(11)]
    assert codes[:10] == [401] * 10 and codes[10] == 429
    assert rl.login_email_limiter.window <= 60
