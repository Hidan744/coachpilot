from app.catalog.seed import seed
from app.db import SessionLocal
from tests.conftest import make_user


async def test_seed_is_idempotent_and_versioned(client):
    h, _ = await make_user(client)
    async with SessionLocal() as db:
        changed, total = await seed(db)
    assert total >= 80 and changed == total

    r = (await client.get("/catalog/drills", headers=h)).json()
    assert r["changed"] and len(r["drills"]) == total
    version = r["version"]
    d = r["drills"][0]["data"]
    assert d["source"] == "system" and d["steps"] and d["scheme"]["items"]

    # повторный запуск ничего не меняет — версия та же, клиент не перекачивает каталог
    async with SessionLocal() as db:
        changed, _ = await seed(db)
    assert changed == 0
    r2 = (await client.get(f"/catalog/drills?version={version}", headers=h)).json()
    assert r2 == {"version": version, "changed": False, "drills": []}


async def test_system_drill_can_be_favorited_not_modified(client):
    h, _ = await make_user(client)
    async with SessionLocal() as db:
        await seed(db)
    drill = (await client.get("/catalog/drills", headers=h)).json()["drills"][0]
    import uuid
    res = (await client.post("/sync/push", headers=h, json={"changes": [
        {"entity": "favorites", "id": str(uuid.uuid4()), "op": "upsert", "data": {"drill_id": drill["id"]}},
        {"entity": "drills", "id": drill["id"], "op": "upsert", "data": {**drill["data"], "source": "user"}},
    ]})).json()["results"]
    assert res[0]["status"] == "applied"
    assert res[1]["status"] == "rejected" and res[1]["error"] == "not_found"
