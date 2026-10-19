import uuid

from tests.conftest import make_user


def team(name="U12 Звезда"):
    return {"name": name, "age_group": "U12", "level": "amateur", "default_players": 14}


def session_data(team_id=None, title="Тренировка"):
    return {
        "team_id": team_id,
        "title": title,
        "duration_min": 60,
        "blocks": [
            {"id": "b1", "phase": "warmup", "title": "Разминка", "duration_min": 15},
            {"id": "b2", "phase": "main", "title": "Квадрат 4v2", "duration_min": 45},
        ],
    }


async def push(client, headers, *changes):
    r = await client.post("/sync/push", headers=headers, json={"changes": list(changes)})
    assert r.status_code == 200, r.text
    return r.json()["results"]


def up(entity, id_, data, base_seq=None):
    return {"entity": entity, "id": str(id_), "op": "upsert", "data": data, "base_seq": base_seq}


async def test_push_and_pull_roundtrip(client):
    h, _ = await make_user(client)
    t_id, p_id = uuid.uuid4(), uuid.uuid4()
    res = await push(
        client, h,
        up("teams", t_id, team()),
        up("players", p_id, {"team_id": str(t_id), "first_name": "Саша", "birth_year": 2014}),
    )
    assert [r["status"] for r in res] == ["applied", "applied"]
    assert res[1]["server_seq"] > res[0]["server_seq"]

    r = (await client.get("/sync/pull?since=0", headers=h)).json()
    assert [x["entity"] for x in r["records"]] == ["teams", "players"]
    assert r["records"][1]["data"]["first_name"] == "Саша"
    assert r["cursor"] == res[1]["server_seq"]

    # инкрементально — ничего нового
    r2 = (await client.get(f"/sync/pull?since={r['cursor']}", headers=h)).json()
    assert r2["records"] == [] and r2["cursor"] == r["cursor"]


async def test_pull_pagination(client):
    h, _ = await make_user(client)
    await push(client, h, *[up("teams", uuid.uuid4(), team(f"T{i}")) for i in range(5)])
    page1 = (await client.get("/sync/pull?since=0&limit=3", headers=h)).json()
    assert len(page1["records"]) == 3 and page1["has_more"]
    page2 = (await client.get(f"/sync/pull?since={page1['cursor']}&limit=3", headers=h)).json()
    assert len(page2["records"]) == 2 and not page2["has_more"]


async def test_data_isolation_between_users(client):
    ha, _ = await make_user(client, email="a@example.com")
    hb, _ = await make_user(client, email="b@example.com")
    t_id = uuid.uuid4()
    await push(client, ha, up("teams", t_id, team("Команда A")))

    # B не видит данные A
    assert (await client.get("/sync/pull", headers=hb)).json()["records"] == []
    # B не может перезаписать или удалить запись A по известному id
    res = await push(client, hb, up("teams", t_id, team("Захват")),
                     {"entity": "teams", "id": str(t_id), "op": "delete"})
    assert [r["status"] for r in res] == ["rejected", "rejected"]
    assert all(r["error"] == "not_found" for r in res)
    # B не может сослаться на команду A
    res = await push(client, hb, up("players", uuid.uuid4(), {"team_id": str(t_id), "first_name": "X"}))
    assert res[0]["status"] == "rejected" and res[0]["error"] == "invalid_reference:team_id"

    recs = (await client.get("/sync/pull", headers=ha)).json()["records"]
    assert recs[0]["data"]["name"] == "Команда A" and not recs[0]["deleted"]


async def test_validation_rejects_bad_data(client):
    h, _ = await make_user(client)
    bad = team()
    bad["default_players"] = 0
    res = await push(client, h, up("teams", uuid.uuid4(), bad), up("teams", uuid.uuid4(), team()))
    assert res[0]["status"] == "rejected" and res[0]["error"].startswith("validation:")
    # одна плохая запись не ломает остальные в пачке
    assert res[1]["status"] == "applied"


async def test_lww_for_teams(client):
    h, _ = await make_user(client)
    t_id = uuid.uuid4()
    [r1] = await push(client, h, up("teams", t_id, team("v1")))
    # два устройства правят от одной версии — последняя запись побеждает
    await push(client, h, up("teams", t_id, team("device1"), base_seq=r1["server_seq"]))
    [r3] = await push(client, h, up("teams", t_id, team("device2"), base_seq=r1["server_seq"]))
    assert r3["status"] == "applied"
    recs = (await client.get("/sync/pull", headers=h)).json()["records"]
    assert recs[-1]["data"]["name"] == "device2"


async def test_strict_conflict_for_training_plan(client):
    h, _ = await make_user(client)
    s_id = uuid.uuid4()
    [r1] = await push(client, h, up("training_sessions", s_id, session_data(title="v1")))
    base = r1["server_seq"]
    [r2] = await push(client, h, up("training_sessions", s_id, session_data(title="phone"), base))
    assert r2["status"] == "applied"
    # планшет правил ту же версию офлайн — конфликт, сервер возвращает актуальную версию
    [r3] = await push(client, h, up("training_sessions", s_id, session_data(title="tablet"), base))
    assert r3["status"] == "conflict"
    assert r3["server_record"]["data"]["title"] == "phone"
    assert r3["server_record"]["data"]["blocks"][1]["title"] == "Квадрат 4v2"
    # правка от актуальной версии проходит
    [r4] = await push(client, h, up("training_sessions", s_id, session_data(title="merged"),
                                    r2["server_seq"]))
    assert r4["status"] == "applied"


async def test_delete_wins_over_edit(client):
    h, _ = await make_user(client)
    t_id = uuid.uuid4()
    [r1] = await push(client, h, up("teams", t_id, team()))
    [d] = await push(client, h, {"entity": "teams", "id": str(t_id), "op": "delete",
                                 "base_seq": r1["server_seq"]})
    assert d["status"] == "applied"
    [e] = await push(client, h, up("teams", t_id, team("offline edit"), r1["server_seq"]))
    assert e["status"] == "conflict" and e["server_record"]["deleted"]
    # удаление доходит до других устройств через pull
    recs = (await client.get("/sync/pull", headers=h)).json()["records"]
    assert recs[-1]["deleted"] is True
    # повторное удаление идемпотентно
    [d2] = await push(client, h, {"entity": "teams", "id": str(t_id), "op": "delete"})
    assert d2["status"] == "applied"


async def test_full_session_flow_and_export(client):
    h, _ = await make_user(client)
    t, p, s = uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    att = uuid.uuid5(s, str(p))
    res = await push(
        client, h,
        up("teams", t, team()),
        up("players", p, {"team_id": str(t), "first_name": "Миша"}),
        up("training_sessions", s, session_data(str(t))),
        up("attendance", att, {"session_id": str(s), "player_id": str(p), "status": "present"}),
        up("session_notes", uuid.uuid4(), {"session_id": str(s), "block_id": "b2",
                                           "text": "Слабо открываются", "noted_at": "2026-10-19T10:00:00Z"}),
        up("session_reports", uuid.uuid4(), {"session_id": str(s), "went_well": "Темп",
                                             "to_improve": "Первое касание", "coach_confirmed": True}),
        up("player_assessments", uuid.uuid4(), {"player_id": str(p), "session_id": str(s),
                                                "skill": "passing", "score": 4,
                                                "assessed_at": "2026-10-19T11:00:00Z"}),
    )
    assert all(r["status"] == "applied" for r in res), res

    exp = (await client.get("/account/export", headers=h)).json()
    assert exp["user"]["email"] == "coach@example.com"
    assert len(exp["data"]["session_notes"]) == 1
    assert exp["data"]["training_sessions"][0]["data"]["blocks"][0]["id"] == "b1"


async def test_delete_account_removes_data(client):
    h, _ = await make_user(client)
    await push(client, h, up("teams", uuid.uuid4(), team()))
    r = await client.post("/account/delete", headers=h, json={"password": "wrong"})
    assert r.status_code == 403
    r = await client.post("/account/delete", headers=h, json={"password": "secret123"})
    assert r.status_code == 204
    assert (await client.get("/me", headers=h)).status_code == 401
    # email снова свободен, данных нет
    h2, _ = await make_user(client)
    assert (await client.get("/sync/pull", headers=h2)).json()["records"] == []


async def test_catalog_empty_and_versioned(client):
    h, _ = await make_user(client)
    r = (await client.get("/catalog/drills", headers=h)).json()
    assert r == {"version": 0, "changed": False, "drills": []}
