import uuid
from datetime import UTC, datetime, timedelta

from tests.conftest import make_user
from tests.test_sync import push, team, up


async def _setup(client, headers):
    tid, pid, sid = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    now = datetime.now(UTC)
    res = await push(
        client, headers,
        up("teams", tid, team("U16 Амкар")),
        up("players", pid, {"team_id": str(tid), "first_name": "Пётр", "last_name": "Сидоров", "number": 7,
                            "position": "MF"}),
        up("training_sessions", sid, {"team_id": str(tid), "title": "Квадраты", "duration_min": 60,
                                      "status": "done", "started_at": now.isoformat()}),
        up("attendance", uuid.uuid4(), {"session_id": str(sid), "player_id": str(pid), "status": "present"}),
        up("matches", uuid.uuid4(), {"team_id": str(tid), "opponent": "Зенит U16",
                                     "starts_at": (now + timedelta(days=3)).isoformat(), "home": False}),
        up("schedule_slots", uuid.uuid4(), {"team_id": str(tid), "title": "Тренировка U16",
                                            "weekdays": [3, 1, 1], "start_time": "10:00", "duration_min": 120}),
        up("development_plans", uuid.uuid4(), {
            "player_id": str(pid), "period": "week", "title": "Левая нога",
            "items": [{"text": "100 передач левой", "kind": "task", "done": True},
                      {"text": "Уверенный приём <левой>", "kind": "goal"}],
            "comment": "Молодец",
        }),
        up("development_plans", uuid.uuid4(), {"player_id": str(pid), "period": "season", "title": "Скрытый план",
                                               "shared": False}),
        up("parent_notes", uuid.uuid4(), {"player_id": str(pid), "category": "nutrition",
                                          "text": "Завтрак за 2 часа до игры", "written_at": now.isoformat()}),
        up("parent_notes", uuid.uuid4(), {"player_id": str(pid), "category": "psychology",
                                          "text": "Только для тренера", "written_at": now.isoformat(),
                                          "shared": False}),
        up("tactic_boards", uuid.uuid4(), {"team_id": str(tid), "title": "4-3-3", "formation": "4-3-3",
                                           "scheme": {"field": "full_v", "items": [
                                               {"type": "player_a", "x": 0.5, "y": 0.9, "label": "Сидоров"},
                                               {"type": "pen", "x": 0.1, "y": 0.1,
                                                "points": [[0.1, 0.1], [0.2, 0.3]], "color": "#FFFFFF"}]}}),
    )
    assert all(r["status"] == "applied" for r in res), res
    return pid


async def test_share_page_shows_only_shared_data(client):
    headers, _ = await make_user(client)
    pid = await _setup(client, headers)

    r = await client.post(f"/players/{pid}/share", headers=headers)
    assert r.status_code == 200, r.text
    token, url = r.json()["token"], r.json()["url"]
    assert url.endswith(f"/p/{token}")
    # Повторный запрос отдаёт ту же ссылку.
    assert (await client.post(f"/players/{pid}/share", headers=headers)).json()["token"] == token

    page = await client.get(f"/p/{token}")
    assert page.status_code == 200
    body = page.text
    assert "Пётр Сидоров" in body and "U16 Амкар" in body
    assert "100%" in body and "Квадраты" in body
    assert "Завтрак за 2 часа до игры" in body and "Питание" in body
    assert "Левая нога" in body and "&lt;левой&gt;" in body
    assert "Зенит U16" in body and "пн, ср 10:00" in body
    assert "Скрытый план" not in body and "Только для тренера" not in body

    r = await client.delete(f"/players/{pid}/share", headers=headers)
    assert r.status_code == 204
    assert (await client.get(f"/p/{token}")).status_code == 404


async def test_share_requires_own_synced_player(client):
    headers, _ = await make_user(client)
    other, _ = await make_user(client, email="other@example.com")
    pid = await _setup(client, headers)
    assert (await client.post(f"/players/{pid}/share", headers=other)).status_code == 404
    assert (await client.post(f"/players/{uuid.uuid4()}/share", headers=headers)).status_code == 404
    assert (await client.get("/p/unknown-token")).status_code == 404


async def test_new_entities_validation(client):
    headers, _ = await make_user(client)
    tid = uuid.uuid4()
    await push(client, headers, up("teams", tid, team()))
    res = await push(
        client, headers,
        up("schedule_slots", uuid.uuid4(), {"team_id": str(tid), "title": "x", "weekdays": [8],
                                            "start_time": "10:00"}),
        up("schedule_slots", uuid.uuid4(), {"team_id": str(tid), "title": "x", "weekdays": [1],
                                            "start_time": "25:00"}),
        up("matches", uuid.uuid4(), {"team_id": str(uuid.uuid4()), "opponent": "X",
                                     "starts_at": datetime.now(UTC).isoformat()}),
        up("parent_notes", uuid.uuid4(), {"player_id": str(uuid.uuid4()), "category": "unknown",
                                          "text": "x", "written_at": datetime.now(UTC).isoformat()}),
    )
    assert [r["status"] for r in res] == ["rejected"] * 4
    assert res[2]["error"] == "invalid_reference:team_id"
