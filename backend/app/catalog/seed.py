"""Загрузка системной библиотеки в БД и экспорт для встраивания в приложение.

    python -m app.catalog.seed                     # загрузить/обновить в БД
    python -m app.catalog.seed --export FILE.json  # выгрузить каталог для приложения

Обновляются только изменившиеся упражнения: версия каталога (max server_seq)
меняется только при реальных правках, и клиенты не перекачивают его зря.
"""

import argparse
import asyncio
import json
import uuid
from pathlib import Path

from fastapi.encoders import jsonable_encoder
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import models as m
from app.catalog.drills import DRILLS
from app.schemas import DrillData
from app.sync import system_catalog

NAMESPACE = uuid.UUID("0b5e8a52-6f0e-4c2b-9a2e-1c7c9d1f7a10")


def drill_id(slug: str) -> uuid.UUID:
    return uuid.uuid5(NAMESPACE, slug)


def validated() -> list[tuple[uuid.UUID, dict]]:
    """Проверяет упражнения той же схемой, что и пользовательские."""
    out, slugs = [], set()
    for d in DRILLS:
        d = dict(d)
        slug = d.pop("slug")
        if slug in slugs:
            raise ValueError(f"дубликат slug {slug}")
        slugs.add(slug)
        data = DrillData.model_validate(
            {"license": "catalog", "source_ref": "Каталог CoachPilot", **d, "source": "user"}
        ).model_dump(mode="json")
        data["source"] = "system"
        out.append((drill_id(slug), data))
    return out


async def seed(db: AsyncSession) -> tuple[int, int]:
    """Возвращает (создано или обновлено, всего)."""
    changed = 0
    items = validated()
    for did, data in items:
        row = await db.get(m.Drill, did)
        if row is not None:
            current = jsonable_encoder({k: getattr(row, k) for k in data})
            if current == data and row.deleted_at is None:
                continue
        else:
            row = m.Drill(id=did, owner_id=None)
            db.add(row)
        for k, v in data.items():
            setattr(row, k, v)
        row.deleted_at = None
        row.server_seq = await db.scalar(select(m.sync_seq.next_value()))
        changed += 1
    # Упражнения, удалённые из каталога, помечаем удалёнными.
    ids = {did for did, _ in items}
    active = select(m.Drill).where(m.Drill.owner_id.is_(None), m.Drill.deleted_at.is_(None))
    for row in await db.scalars(active):
        if row.id not in ids:
            row.deleted_at = row.updated_at
            row.server_seq = await db.scalar(select(m.sync_seq.next_value()))
            changed += 1
    await db.commit()
    return changed, len(items)


async def export(db: AsyncSession, path: str) -> None:
    version, drills = await system_catalog(db)
    payload = json.dumps({"version": version, "drills": drills}, ensure_ascii=False, separators=(",", ":"))
    Path(path).write_text(payload, encoding="utf-8")  # noqa: ASYNC240 — разовая CLI-операция
    print(f"экспортировано {len(drills)} упражнений, версия {version} → {path}")


async def main() -> None:
    from app.db import SessionLocal

    ap = argparse.ArgumentParser()
    ap.add_argument("--export")
    args = ap.parse_args()
    async with SessionLocal() as db:
        changed, total = await seed(db)
        print(f"каталог: {total} упражнений, обновлено {changed}")
        if args.export:
            await export(db, args.export)


if __name__ == "__main__":
    asyncio.run(main())
