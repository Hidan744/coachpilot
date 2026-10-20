"""Генераторы схем для системной библиотеки.

Координаты нормированы 0..1 (x — слева направо, y — сверху вниз).
У схем "half" ворота соперника сверху (y≈0).
"""

import math


def _p(t, x, y, label=None):
    d = {"type": t, "x": round(x, 3), "y": round(y, 3)}
    if label:
        d["label"] = label
    return d


def _a(t, x, y, x2, y2, step=1):
    """Стрелка движения; step — шаг анимации (стрелки одного шага проигрываются вместе)."""
    return {"type": t, "x": round(x, 3), "y": round(y, 3), "x2": round(x2, 3), "y2": round(y2, 3), "step": step}


def rondo(outside=4, inside=2, field="grid"):
    """Квадрат/круг: атакующие по периметру, обороняющиеся внутри."""
    items = []
    cx, cy, r = 0.5, 0.5, 0.36
    for i in range(4):
        ang = math.pi / 4 + i * math.pi / 2
        items.append(_p("cone", cx + 0.46 * math.cos(ang), cy + 0.46 * math.sin(ang)))
    pts = []
    for i in range(outside):
        ang = -math.pi / 2 + i * 2 * math.pi / outside
        x, y = cx + r * math.cos(ang), cy + r * math.sin(ang)
        pts.append((x, y))
        items.append(_p("player_a", x, y, str(i + 1)))
    for i in range(inside):
        items.append(_p("player_b", cx - 0.08 + 0.16 * i, cy + (0.04 if i % 2 else -0.04)))
    items.append(_p("ball", pts[0][0] + 0.04, pts[0][1] + 0.03))
    items.append(_a("arrow_pass", *pts[0], *pts[1 % outside]))
    if outside > 2:
        items.append(_a("arrow_pass", *pts[1], *pts[outside // 2 + 1 if outside > 3 else 2], step=2))
    return {"field": field, "items": items}


def lines(pairs=2, field="grid", dribble=False):
    """Колонны напротив друг друга: передачи/ведение со сменой мест."""
    items = []
    for i in range(pairs):
        y = (i + 1) / (pairs + 1)
        items += [_p("cone", 0.15, y), _p("cone", 0.85, y)]
        items += [_p("player_a", 0.1, y), _p("player_a", 0.04, y), _p("player_b", 0.9, y), _p("player_b", 0.96, y)]
        items.append(_p("ball", 0.15, y + 0.04))
        items.append(_a("arrow_dribble" if dribble else "arrow_pass", 0.16, y, 0.84, y))
        items.append(_a("arrow_run", 0.1, y, 0.85, y + 0.06, step=2))
    return {"field": field, "items": items}


def gates(n=8, players=6, field="grid"):
    """Ворота из фишек по всей площадке, игроки с мячами."""
    items = []
    spots = [(0.15, 0.2), (0.5, 0.15), (0.85, 0.25), (0.25, 0.55), (0.7, 0.5),
             (0.15, 0.85), (0.5, 0.8), (0.85, 0.8), (0.45, 0.45)]
    for x, y in spots[:n]:
        items += [_p("cone", x - 0.04, y), _p("cone", x + 0.04, y)]
    for i in range(players):
        x, y = 0.1 + (i * 0.27) % 0.8, 0.35 + 0.3 * (i % 2)
        items += [_p("player_a", x, y), _p("ball", x + 0.03, y + 0.03)]
    items.append(_a("arrow_dribble", 0.1, 0.35, 0.21, 0.2))
    return {"field": field, "items": items}


def ssg(a=4, b=4, goals="mini", field="third", jokers=0):
    """Игра в малых составах: команды, ворота на лицевых линиях."""
    items = []
    if goals == "mini":
        items += [_p("mini_goal", 0.5, 0.03), _p("mini_goal", 0.5, 0.97)]
    elif goals == "big":
        items += [_p("goal", 0.5, 0.02), _p("goal", 0.5, 0.98)]
        items += [_p("goalkeeper", 0.5, 0.07), _p("goalkeeper", 0.5, 0.93)]
    elif goals == "gates":
        for x in (0.2, 0.8):
            items += [_p("cone", x - 0.06, 0.03), _p("cone", x + 0.06, 0.03)]
            items += [_p("cone", x - 0.06, 0.97), _p("cone", x + 0.06, 0.97)]
    for i in range(a):
        items.append(_p("player_a", 0.15 + 0.7 * i / max(a - 1, 1), 0.62 + 0.12 * (i % 2)))
    for i in range(b):
        items.append(_p("player_b", 0.15 + 0.7 * i / max(b - 1, 1), 0.3 + 0.12 * (i % 2)))
    for i in range(jokers):
        items.append(_p("neutral", 0.04 if i % 2 == 0 else 0.96, 0.5))
    items.append(_p("ball", 0.5, 0.52))
    return {"field": field, "items": items}


def finishing(shooters=2, server=True, defender=False):
    """Завершение: ворота сверху, удары с линии штрафной."""
    items = [_p("goal", 0.5, 0.02), _p("goalkeeper", 0.5, 0.07)]
    items += [_p("cone", 0.3, 0.45), _p("cone", 0.7, 0.45)]
    for i in range(shooters):
        x = 0.35 + 0.3 * i / max(shooters - 1, 1) if shooters > 1 else 0.5
        items.append(_p("player_a", x, 0.62))
        items.append(_a("arrow_dribble", x, 0.62, x + (0.05 if x < 0.5 else -0.05), 0.4, step=2))
        items.append(_a("arrow_pass", x + (0.05 if x < 0.5 else -0.05), 0.4, 0.5, 0.05, step=3))
    if server:
        items += [_p("neutral", 0.85, 0.4, "П"), _p("ball", 0.88, 0.43)]
        items.append(_a("arrow_pass", 0.84, 0.4, 0.62, 0.4))
    if defender:
        items.append(_p("player_b", 0.5, 0.32))
    return {"field": "half", "items": items}


def one_v_one(goals="mini"):
    items = [_p("player_a", 0.3, 0.92), _p("player_a", 0.24, 0.92), _p("ball", 0.33, 0.88),
             _p("player_b", 0.7, 0.08), _p("player_b", 0.76, 0.08)]
    if goals == "mini":
        items += [_p("mini_goal", 0.5, 0.03), _p("mini_goal", 0.5, 0.97)]
    else:
        items += [_p("goal", 0.5, 0.02), _p("goalkeeper", 0.5, 0.07)]
    items += [_a("arrow_dribble", 0.33, 0.86, 0.5, 0.15), _a("arrow_run", 0.7, 0.1, 0.5, 0.45)]
    return {"field": "box" if goals == "mini" else "half", "items": items}


def circuit():
    """Станции: лестница, барьеры, слалом, рывок."""
    items = []
    for i in range(4):
        items.append(_p("cone", 0.12 + i * 0.07, 0.2))  # лестница
    for i in range(4):
        items.append(_p("pole", 0.15 + i * 0.1, 0.5))  # слалом
    for i in range(3):
        items.append(_p("cone", 0.65 + i * 0.1, 0.2))  # барьеры
    items += [_p("cone", 0.6, 0.8), _p("cone", 0.9, 0.8)]
    items += [_p("player_a", 0.05, 0.2), _p("player_a", 0.05, 0.5), _p("player_a", 0.55, 0.2), _p("player_a", 0.55, 0.8)]
    items += [_a("arrow_run", 0.1, 0.25, 0.4, 0.25), _a("arrow_run", 0.1, 0.55, 0.5, 0.55),
              _a("arrow_run", 0.6, 0.25, 0.9, 0.25), _a("arrow_run", 0.6, 0.85, 0.9, 0.85)]
    items += [{"type": "zone", "x": 0.03, "y": 0.1, "x2": 0.47, "y2": 0.65}]
    return {"field": "grid", "items": items}


def triangle(field="grid"):
    """Треугольник/ромб передач с выходом на свободное место."""
    pts = [(0.5, 0.15), (0.15, 0.8), (0.85, 0.8), (0.5, 0.55)]
    items = [_p("cone", x, y) for x, y in pts[:3]]
    items += [_p("player_a", x, y + 0.04) for x, y in pts[:3]]
    items += [_p("ball", 0.53, 0.2), _a("arrow_pass", 0.5, 0.19, 0.15, 0.84),
              _a("arrow_run", 0.5, 0.19, 0.15, 0.7, step=2), _a("arrow_pass", 0.15, 0.84, 0.85, 0.84, step=2)]
    return {"field": field, "items": items}


def wave_attack(attackers=3, defenders=2):
    """Атака волнами на ворота (численное преимущество)."""
    items = [_p("goal", 0.5, 0.02), _p("goalkeeper", 0.5, 0.07)]
    for i in range(attackers):
        items.append(_p("player_a", 0.2 + 0.6 * i / max(attackers - 1, 1), 0.75))
    for i in range(defenders):
        items.append(_p("player_b", 0.35 + 0.3 * i / max(defenders - 1, 1), 0.38))
    items += [_p("ball", 0.5, 0.7), _a("arrow_pass", 0.5, 0.73, 0.22, 0.6),
              _a("arrow_run", 0.8, 0.75, 0.75, 0.25, step=2), _a("arrow_pass", 0.22, 0.6, 0.72, 0.28, step=2)]
    return {"field": "half", "items": items}


def transition_zones():
    """Игра с переходами: зона потери — быстрая атака в другую сторону."""
    items = [{"type": "zone", "x": 0.0, "y": 0.0, "x2": 1.0, "y2": 0.33},
             {"type": "zone", "x": 0.0, "y": 0.67, "x2": 1.0, "y2": 1.0},
             _p("mini_goal", 0.5, 0.03), _p("mini_goal", 0.5, 0.97)]
    items += [_p("player_a", 0.3, 0.15), _p("player_a", 0.7, 0.2), _p("player_a", 0.5, 0.25),
              _p("player_b", 0.4, 0.2), _p("player_b", 0.6, 0.12)]
    items += [_p("player_b", 0.3, 0.8), _p("player_a", 0.7, 0.85)]
    items += [_p("ball", 0.42, 0.24), _a("arrow_pass", 0.4, 0.22, 0.32, 0.78)]
    return {"field": "third", "items": items}


def defending_shape(defenders=4):
    items = [_p("goal", 0.5, 0.98), _p("goalkeeper", 0.5, 0.93)]
    for i in range(defenders):
        items.append(_p("player_b", 0.15 + 0.7 * i / max(defenders - 1, 1), 0.72))
    for i in range(defenders + 1):
        items.append(_p("player_a", 0.1 + 0.8 * i / defenders, 0.35))
    items += [_p("ball", 0.14, 0.38), _a("arrow_pass", 0.1, 0.35, 0.3, 0.35),
              _a("arrow_run", 0.15, 0.72, 0.3, 0.62, step=2), _a("arrow_run", 0.38, 0.72, 0.42, 0.68, step=2)]
    return {"field": "half", "items": items}


def gk_basic():
    items = [_p("goal", 0.5, 0.02), _p("goalkeeper", 0.5, 0.08), _p("neutral", 0.5, 0.42, "Т"),
             _p("ball", 0.52, 0.38), _p("cone", 0.4, 0.1), _p("cone", 0.6, 0.1),
             _a("arrow_pass", 0.5, 0.4, 0.42, 0.06), _a("arrow_run", 0.5, 0.08, 0.42, 0.08)]
    return {"field": "half", "items": items}


def free_zone(players=10, field="grid"):
    """Свободное перемещение по зоне (разминка/заминка)."""
    items = [_p("cone", 0.05, 0.05), _p("cone", 0.95, 0.05), _p("cone", 0.05, 0.95), _p("cone", 0.95, 0.95)]
    for i in range(players):
        items.append(_p("player_a" if i % 2 == 0 else "player_b", 0.15 + (i * 0.37) % 0.7, 0.15 + (i * 0.23) % 0.7))
    items += [_a("arrow_run", 0.2, 0.3, 0.4, 0.45), _a("arrow_run", 0.7, 0.6, 0.55, 0.35)]
    return {"field": field, "items": items}
