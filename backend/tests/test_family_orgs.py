import uuid
from datetime import UTC, datetime, timedelta

from tests.conftest import make_user
from tests.test_sync import push, team, up


def future(days=2):
    return (datetime.now(UTC) + timedelta(days=days)).isoformat()


async def _coach_with_child(client, email):
    h, _ = await make_user(client, email=email)
    tid, pid, sid, mid = uuid.uuid4(), uuid.uuid4(), uuid.uuid4(), uuid.uuid4()
    res = await push(
        client, h, up("teams", tid, team("U12")),
        up("players", pid, {"team_id": str(tid), "first_name": "Миша", "last_name": "Иванов",
                            "parent_consent": {"given": True, "by": "Иванова"}}),
        up("training_sessions", sid, {"team_id": str(tid), "title": "Квадраты", "duration_min": 60,
                                      "status": "planned", "scheduled_at": future()}),
        up("matches", mid, {"team_id": str(tid), "opponent": "Динамо", "starts_at": future(5)}),
        up("parent_notes", uuid.uuid4(), {"player_id": str(pid), "category": "nutrition", "text": "Завтрак",
                                          "written_at": datetime.now(UTC).isoformat(), "shared": True}),
        up("parent_notes", uuid.uuid4(), {"player_id": str(pid), "category": "health", "text": "Секрет тренера",
                                          "written_at": datetime.now(UTC).isoformat(), "shared": False}),
    )
    assert all(r["status"] == "applied" for r in res), res
    return h, tid, pid, sid, mid


async def _parent(client, coach_h, pid, email):
    code = (await client.post(f"/players/{pid}/invite", headers=coach_h, json={"role": "parent"})).json()["code"]
    r = await client.post("/auth/register", json={"email": email, "password": "secret123", "name": "Мама",
                                                  "consent_personal_data": True, "role": "parent"})
    ph = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert (await client.post("/family/join", headers=ph, json={"code": code})).status_code == 200
    return ph


async def test_parent_sees_only_own_child_and_shared_data(client):
    ch, tid, pid, sid, mid = await _coach_with_child(client, "c1@example.com")
    ch2, _, pid2, sid2, _ = await _coach_with_child(client, "c2@example.com")
    ph = await _parent(client, ch, pid, "mom@example.com")

    kids = (await client.get("/family/children", headers=ph)).json()
    assert [k["player_id"] for k in kids] == [str(pid)]
    d = (await client.get(f"/family/children/{pid}", headers=ph)).json()
    assert [e["kind"] for e in d["upcoming"]] == ["session", "match"]
    assert [n["text"] for n in d["notes"]] == ["Завтрак"]  # закрытая заметка не видна

    # Подстановка чужого id — 404, как для несуществующего.
    assert (await client.get(f"/family/children/{pid2}", headers=ph)).status_code == 404
    assert (await client.post(f"/family/children/{pid2}/rsvp", headers=ph,
                              json={"kind": "session", "id": str(sid2), "status": "yes"})).status_code == 404
    # Чужое событие для своего ребёнка — 404.
    assert (await client.post(f"/family/children/{pid}/rsvp", headers=ph,
                              json={"kind": "session", "id": str(sid2), "status": "yes"})).status_code == 404
    # Синхронизация тренера родителю ничего не отдаёт.
    assert (await client.get("/sync/pull?since=0", headers=ph)).json()["records"] == []
    # Родитель не может выдать код к игроку.
    assert (await client.post(f"/players/{pid}/invite", headers=ph, json={"role": "parent"})).status_code == 404


async def test_rsvp_reaches_coach(client):
    ch, tid, pid, sid, mid = await _coach_with_child(client, "c1@example.com")
    ph = await _parent(client, ch, pid, "mom@example.com")
    url = f"/family/children/{pid}/rsvp"
    r = await client.post(url, headers=ph, json={"kind": "session", "id": str(sid), "status": "yes"})
    assert r.status_code == 200
    await client.post(url, headers=ph, json={"kind": "match", "id": str(mid), "status": "no"})
    rs = (await client.get(f"/teams/{tid}/rsvp", headers=ch)).json()
    assert rs[f"session:{sid}"]["yes"] == 1 and rs[f"match:{mid}"]["no"] == 1
    fam = (await client.get(f"/players/{pid}/family", headers=ch)).json()
    assert fam[0]["name"] == "Мама"
    await client.delete(f"/players/{pid}/family/{fam[0]['id']}", headers=ch)
    assert (await client.get(f"/family/children/{pid}", headers=ph)).status_code == 404


async def test_invite_for_minor_requires_consent(client):
    h, _ = await make_user(client)
    tid, pid = uuid.uuid4(), uuid.uuid4()
    await push(client, h, up("teams", tid, team("U10")),
               up("players", pid, {"team_id": str(tid), "first_name": "Ваня"}))
    assert (await client.post(f"/players/{pid}/invite", headers=h, json={"role": "parent"})).status_code == 409
    assert (await client.post(f"/players/{pid}/invite", headers=h, json={"role": "player"})).status_code == 200


async def test_org_isolation_roles_and_overview(client):
    owner, *_ = await _coach_with_child(client, "boss@example.com")
    coach, tid, *_ = await _coach_with_child(client, "coach@example.com")
    stranger, *_ = await _coach_with_child(client, "other@example.com")
    org = (await client.post("/orgs", headers=owner, json={"name": "СШ Сочи"})).json()
    other_org = (await client.post("/orgs", headers=stranger, json={"name": "Чужая школа"})).json()
    code = (await client.post(f"/orgs/{org['id']}/invites", headers=owner, json={"role": "coach"})).json()["code"]
    assert (await client.post("/orgs/join", headers=coach, json={"code": code})).status_code == 200

    ov = (await client.get(f"/orgs/{org['id']}/overview", headers=owner)).json()
    assert {t["coach"] for t in ov["teams"]} == {"Иван"}  # обе команды — owner и coach
    assert len(ov["teams"]) == 2
    # Чужая школа не видна; рядовой тренер не видит сводку и не управляет.
    assert (await client.get(f"/orgs/{other_org['id']}/overview", headers=owner)).status_code == 404
    assert (await client.get(f"/orgs/{org['id']}/overview", headers=stranger)).status_code == 404
    assert (await client.get(f"/orgs/{org['id']}/overview", headers=coach)).status_code == 403
    assert (await client.post(f"/orgs/{org['id']}/invites", headers=coach, json={})).status_code == 403


async def test_team_transfer_moves_data_and_removes_it_from_old_coach(client):
    owner, *_ = await _coach_with_child(client, "boss@example.com")
    coach, tid, pid, sid, mid = await _coach_with_child(client, "coach@example.com")
    org = (await client.post("/orgs", headers=owner, json={"name": "СШ"})).json()
    code = (await client.post(f"/orgs/{org['id']}/invites", headers=owner, json={"role": "coach"})).json()["code"]
    await client.post("/orgs/join", headers=coach, json={"code": code})
    me = (await client.get("/me", headers=owner)).json()["id"]
    before = (await client.get("/sync/pull?since=0", headers=coach)).json()["cursor"]

    # Рядовой тренер передать не может.
    r = await client.post(f"/orgs/{org['id']}/transfer", headers=coach, json={"team_id": str(tid), "to_user_id": me})
    assert r.status_code == 403
    r = await client.post(f"/orgs/{org['id']}/transfer", headers=owner, json={"team_id": str(tid), "to_user_id": me})
    assert r.status_code == 200 and r.json()["moved"] >= 6

    got = (await client.get("/sync/pull?since=0", headers=owner)).json()["records"]
    assert {x["id"] for x in got if not x["deleted"]} >= {str(tid), str(pid), str(sid), str(mid)}
    gone = (await client.get(f"/sync/pull?since={before}", headers=coach)).json()["records"]
    assert {x["id"] for x in gone} >= {str(tid), str(pid), str(sid), str(mid)}
    assert all(x["deleted"] for x in gone)
