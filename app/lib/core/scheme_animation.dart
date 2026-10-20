import 'package:flutter/animation.dart';

import '../data/models.dart';

/// Движение одного объекта в пределах шага.
class SchemeMove {
  const SchemeMove(this.key, this.from, this.to);

  /// Индекс элемента схемы; отрицательный — мяч, которого не было на схеме (пас без нарисованного мяча).
  final int key;
  final Offset from, to;
}

/// Анимация схемы по шагам.
///
/// Стрелки одного шага проигрываются одновременно, шаги — по очереди. Кто двигается, определяется
/// по началу стрелки: пас — ближайший мяч, бег — ближайший игрок, ведение — игрок вместе с мячом.
/// Если мяча у начала паса нет, он появляется сам.
class SchemeAnimation {
  SchemeAnimation(this.scheme) {
    _build();
  }

  final Scheme scheme;

  /// Номера шагов по порядку.
  late final List<int> steps;
  final _starts = <Map<int, Offset>>[];
  final _moves = <List<SchemeMove>>[];

  static const _grab = 0.1;

  int get stepCount => steps.length;
  bool get hasMotion => _moves.any((m) => m.isNotEmpty);

  /// Ключи мячей, которых не было на схеме (появляются при пасе).
  Iterable<int> get virtualKeys => _starts.isEmpty ? const [] : _starts.last.keys.where((k) => k < 0);

  void _build() {
    steps = scheme.steps;
    var pos = <int, Offset>{
      for (var i = 0; i < scheme.items.length; i++)
        if (scheme.items[i].isPlayer || scheme.items[i].type == 'ball') i: Offset(scheme.items[i].x, scheme.items[i].y),
    };
    var virtual = 0;
    for (final step in steps) {
      _starts.add(Map.of(pos));
      final moves = <SchemeMove>[];
      final busy = <int>{};
      for (final a in scheme.items.where((e) => e.isMovement && e.stepOrFirst == step)) {
        final from = Offset(a.x, a.y), to = Offset(a.x2 ?? a.x, a.y2 ?? a.y);
        int? nearest(bool Function(int key) accept) {
          int? best;
          var bestD = _grab;
          for (final e in pos.entries) {
            if (busy.contains(e.key) || !accept(e.key)) continue;
            final d = (e.value - from).distance;
            if (d < bestD) {
              bestD = d;
              best = e.key;
            }
          }
          return best;
        }

        bool isBall(int k) => k < 0 || scheme.items[k].type == 'ball';
        bool isPlayer(int k) => k >= 0 && scheme.items[k].isPlayer;

        void move(int key, {Offset offset = Offset.zero}) {
          busy.add(key);
          moves.add(SchemeMove(key, pos[key]!, to + offset));
        }

        switch (a.type) {
          case 'arrow_pass':
            final ball = nearest(isBall);
            if (ball != null) {
              move(ball);
            } else {
              final k = -(++virtual);
              pos[k] = from;
              _starts.last[k] = from;
              move(k);
            }
          case 'arrow_run':
            final p = nearest(isPlayer);
            if (p != null) move(p);
          case 'arrow_dribble':
            final p = nearest(isPlayer);
            final ball = nearest(isBall);
            if (p != null) move(p);
            if (ball != null) {
              // мяч остаётся чуть впереди игрока
              move(ball, offset: Offset((pos[ball]! - from).dx, (pos[ball]! - from).dy));
            } else if (p != null) {
              final k = -(++virtual);
              pos[k] = from + const Offset(0.02, 0.02);
              _starts.last[k] = pos[k]!;
              move(k, offset: const Offset(0.02, 0.02));
            }
        }
      }
      _moves.add(moves);
      pos = Map.of(pos);
      for (final m in moves) {
        pos[m.key] = m.to;
      }
    }
    _starts.add(pos); // итоговые позиции после последнего шага
  }

  /// Индекс шага, который идёт в момент [t] (t от 0 до stepCount).
  int stepIndexAt(double t) => t <= 0 ? 0 : (t >= stepCount ? stepCount - 1 : t.floor());

  /// Позиции подвижных объектов в момент [t]. Мячи-«призраки» появляются с шага, где их пасуют.
  Map<int, Offset> positionsAt(double t) {
    if (stepCount == 0) return const {};
    if (t >= stepCount) return _starts.last;
    final j = stepIndexAt(t);
    final frac = Curves.easeInOut.transform((t - j).clamp(0.0, 1.0));
    final out = Map.of(_starts[j]);
    for (final m in _moves[j]) {
      out[m.key] = Offset.lerp(m.from, m.to, frac)!;
    }
    return out;
  }
}
