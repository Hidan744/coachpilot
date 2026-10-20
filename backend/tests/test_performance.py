import uuid
from datetime import UTC, datetime

from tests.conftest import make_user
from tests.test_sync import push, team, up


async def test_stats_tests_staff_and_plan_targets(client):
    headers, _ = await make_user(client)
    tid, pid, mid = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    res = await push(
        client, headers,
        up("teams", tid, team()),
        up("players", pid, {"team_id": str(tid), "first_name": "Иван", "position": "FW"}),
        up("matches", mid, {"team_id": str(tid), "opponent": "Зенит", "starts_at": datetime.now(UTC).isoformat()}),
        up("match_stats", uuid.uuid4(), {"match_id": str(mid), "player_id": str(pid), "started": True, "minutes": 90,
                                         "rating": 7.5, "stats": {"goals": 2, "shots": 5, "shots_on": 3}}),
        up("physical_tests", uuid.uuid4(), {"player_id": str(pid), "tested_on": "2026-10-01",
                                            "results": {"sprint_10m": 1.82, "yoyo": 1480}}),
        up("staff", uuid.uuid4(), {"name": "Пётр Иванов", "role": "fitness", "team_ids": [str(tid)]}),
        up("development_plans", uuid.uuid4(), {
            "player_id": str(pid), "period": "cycle6", "title": "Скорость", "key_goal": "Быстрее на первых метрах",
            "targets": [{"name": "Бег 10 м", "current": 1.92, "target": 1.80, "unit": "с", "priority": "high"}],
        }),
    )
    assert [r["status"] for r in res] == ["applied"] * 7, res
    recs = {r["entity"]: r["data"] for r in (await client.get("/sync/pull", headers=headers)).json()["records"]}
    assert recs["match_stats"]["stats"]["goals"] == 2
    assert recs["physical_tests"]["results"]["yoyo"] == 1480
    assert recs["development_plans"]["targets"][0]["target"] == 1.8


async def test_bad_stats_rejected(client):
    headers, _ = await make_user(client)
    tid, pid, mid = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    await push(
        client, headers,
        up("teams", tid, team()),
        up("players", pid, {"team_id": str(tid), "first_name": "Иван"}),
        up("matches", mid, {"team_id": str(tid), "opponent": "Зенит", "starts_at": datetime.now(UTC).isoformat()}),
    )
    res = await push(
        client, headers,
        up("match_stats", uuid.uuid4(), {"match_id": str(mid), "player_id": str(pid), "stats": {"goals": -1}}),
        up("match_stats", uuid.uuid4(), {"match_id": str(mid), "player_id": str(pid), "minutes": 300}),
        up("physical_tests", uuid.uuid4(), {"player_id": str(pid), "tested_on": "01.10.2026"}),
        up("staff", uuid.uuid4(), {"name": "X", "role": "boss"}),
    )
    assert [r["status"] for r in res] == ["rejected"] * 4
