"""План тренировки по правилам — без языковой модели.

Используется, когда AI недоступен или исчерпан лимит, и как mock-провайдер в тестах.
Та же логика продублирована в приложении (lib/core/plan_rules.dart) для офлайн-режима.
"""

import hashlib
import json
import re

# Ключевые слова цели → категории основной части.
GOAL_KEYWORDS: list[tuple[str, list[str]]] = [
    (r"пас|передач|перевод", ["passing", "possession"]),
    (r"удар|заверш|забив|голев", ["finishing"]),
    (r"владен|контрол[ья] мяч|рондо", ["possession", "passing"]),
    (r"обводк|дриблинг|финт|1\s*[×xх]\s*1|один в один", ["dribbling"]),
    (r"оборон|отбор|защит", ["defending"]),
    (r"переход|контратак|контрпрессинг", ["transition", "tactics"]),
    (r"прессинг|тактик|позицион|выход из обороны|стандарт", ["tactics"]),
    (r"техник|приём|прием|первое касание|ведени", ["technique", "dribbling"]),
    (r"физ|выносл|скорост|ловкост|координац", ["physical"]),
    (r"вратар", ["goalkeeping"]),
]

FOCUS_CATEGORIES = {
    "technique": ["technique", "passing", "dribbling"],
    "tactics": ["tactics", "possession", "transition"],
    "physical": ["physical"],
    "game": ["game"],
}

DEFAULT_MAIN = ["passing", "possession", "technique", "dribbling", "finishing"]


def main_categories(goal: str, focus: list[str] | None = None) -> list[str]:
    g = goal.lower()
    cats: list[str] = []
    for pattern, cs in GOAL_KEYWORDS:
        if re.search(pattern, g):
            cats += [c for c in cs if c not in cats]
    for f in focus or []:
        cats += [c for c in FOCUS_CATEGORIES.get(f, []) if c not in cats]
    return cats or DEFAULT_MAIN


def split_durations(total: int, with_cooldown: bool = True) -> dict[str, list[int]]:
    """Длительности по фазам; сумма ровно равна total."""
    warm = max(8, min(20, round(total * 0.18)))
    cool = max(5, min(10, round(total * 0.08))) if with_cooldown and total >= 45 else 0
    game = max(8, round(total * 0.27)) if total >= 40 else 0
    main = total - warm - cool - game
    mains = [main] if main < 30 else [main // 2 + main % 2, main // 2]
    out = {"warmup": [warm], "main": mains, "game": [game] if game else [], "cooldown": [cool] if cool else []}
    return out


def _tiebreak(seed: str, cid: str) -> str:
    return hashlib.md5(f"{seed}:{cid}".encode()).hexdigest()


def plan_by_rules(session: dict, candidates: list[dict], recent: set[str] | None = None) -> dict:
    """session: duration_min, goal, focus; candidates: [{id, category, duration_min, ...}]."""
    recent = recent or set()
    total = int(session["duration_min"])
    goal = session.get("goal", "")
    cats = main_categories(goal, session.get("focus"))
    durations = split_durations(total)
    used: set[str] = set()

    def pick(allowed: list[str]) -> dict | None:
        pool = [c for c in candidates if c["category"] in allowed and c["id"] not in used]
        if not pool:
            return None
        pool.sort(key=lambda c: (
            c["id"] in recent,  # не повторять недавние
            allowed.index(c["category"]),
            _tiebreak(goal, c["id"]),
        ))
        used.add(pool[0]["id"])
        return pool[0]

    blocks = []
    phase_cats = {"warmup": ["warmup"], "main": cats, "game": ["game", "possession"], "cooldown": ["cooldown"]}
    for phase in ("warmup", "main", "game", "cooldown"):
        for minutes in durations[phase]:
            c = pick(phase_cats[phase]) or (pick(DEFAULT_MAIN) if phase == "main" else None)
            if c is None:
                continue
            blocks.append({"phase": phase, "duration_min": minutes, "drill_id": c["id"], "adaptation": ""})

    # Если какой-то фазы не нашлось — отдаём её минуты основной части.
    diff = total - sum(b["duration_min"] for b in blocks)
    if blocks and diff:
        target = next((b for b in blocks if b["phase"] == "main"), blocks[-1])
        target["duration_min"] += diff

    return {
        "title": (goal[:1].upper() + goal[1:])[:80] if goal else "Тренировка",
        "assumptions": ["План собран по правилам из библиотеки, без AI."],
        "clarifying_question": None,
        "blocks": blocks,
    }


def mock_answer_from_prompt(user_prompt: str) -> dict:
    """Mock-провайдер: достаёт данные из промпта и отвечает планом по правилам."""
    payload = json.loads(user_prompt.split("ДАННЫЕ:", 1)[1])
    plan = plan_by_rules(payload["session"], payload["candidates"])
    plan["assumptions"] = ["Тестовый ответ (mock-провайдер)."]
    return plan


def mock_report_from_prompt(user_prompt: str) -> dict:
    """Mock-провайдер для отчёта: раскладывает ответы тренера по разделам."""
    fields = {}
    for line in user_prompt.splitlines():
        for key, prefix in (("went_well", "Что получилось (тренер): "), ("to_improve", "Что улучшить (тренер): "),
                            ("observations", "Наблюдения (тренер): "), ("raw", "Свободная заметка тренера: ")):
            if line.startswith(prefix):
                value = line[len(prefix):]
                fields[key] = "" if value == "—" else value
    notes = [ln[2:] for ln in user_prompt.split("Заметки во время занятия:", 1)[1].split("Оценка", 1)[0].splitlines()
             if ln.startswith("- ") and ln != "- нет"]
    observations = "\n".join(f"• {x}" for x in [fields.get("observations"), fields.get("raw"), *notes] if x)
    return {
        "went_well": f"• {fields['went_well']}" if fields.get("went_well") else "",
        "to_improve": f"• {fields['to_improve']}" if fields.get("to_improve") else "",
        "observations": observations,
        "suggestions": ["Стоит повторить ключевое упражнение с усложнением в следующем занятии."],
    }


def mock_drills_from_prompt(user_prompt: str) -> dict:
    """Mock-провайдер для импорта: абзац — упражнение, первая строка — название, остальное — шаги."""
    text = user_prompt.split("УПРАЖНЕНИЯ:", 1)[1].strip()
    drills = []
    for block in [b.strip() for b in text.split("\n\n") if b.strip()]:
        lines = [ln.strip(" -•\t") for ln in block.splitlines() if ln.strip()]
        drills.append({"title": lines[0][:150], "category": "technique", "steps": lines[1:] or [lines[0]]})
    return {"drills": drills}
