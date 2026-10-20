import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../data/models.dart';

/// Движение одного объекта в пределах шага — по ломаной.
class SchemeMove {
  SchemeMove(this.key, this.path) : assert(path.length >= 2);

  /// Индекс элемента схемы; отрицательный — мяч, которого не было на схеме (старые схемы без мяча).
  final int key;
  final List<Offset> path;

  Offset get from => path.first;
  Offset get to => path.last;

  /// Точка на пути: [f] от 0 до 1 по длине пути.
  Offset at(double f) {
    if (f <= 0) return path.first;
    if (f >= 1) return path.last;
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += (path[i] - path[i - 1]).distance;
    }
    if (total == 0) return path.last;
    var left = total * f;
    for (var i = 1; i < path.length; i++) {
      final seg = (path[i] - path[i - 1]).distance;
      if (left <= seg) return Offset.lerp(path[i - 1], path[i], seg == 0 ? 1 : left / seg)!;
      left -= seg;
    }
    return path.last;
  }
}

/// Где мяч у ног игрока.
const ballOffset = Offset(0.025, 0.025);

/// Анимация схемы по шагам.
///
/// Стрелки одного шага проигрываются одновременно, шаги — по очереди.
///
/// Новые схемы: у движения указан игрок (`actor`), путь — точки, которые тренер поставил на поле.
/// Мяч закреплён за игроком (`holder`): ведение двигает игрока с мячом, бег — игрока без мяча,
/// пас отправляет мяч партнёру (`target`) и мяч переходит к нему. Мяч никогда не раздваивается.
///
/// Старые схемы (без `actor`): двигается ближайший к началу стрелки объект; если на схеме вообще
/// нет мяча, при пасе он появляется сам.
class SchemeAnimation {
  SchemeAnimation(this.scheme) {
    _build();
  }

  final Scheme scheme;

  /// Номера шагов по порядку.
  late final List<int> steps;
  final _starts = <Map<int, Offset>>[];
  final _moves = <List<SchemeMove>>[];

  /// Как рисовать стрелку (индекс элемента → точки): путь игрока начинается там, где он стоит к этому шагу.
  final resolvedPaths = <int, List<Offset>>{};

  /// Владелец каждого мяча после всех шагов (индекс мяча → индекс игрока).
  final finalHolders = <int, int>{};
  final _holdersAt = <Map<int, int>>[];

  /// Позиции к началу шага [step] (номер шага); для нового шага — после всех.
  Map<int, Offset> positionsBeforeStep(int step) {
    final j = steps.indexOf(step);
    return j < 0 ? finalPositions : _starts[j];
  }

  /// У кого мячи к началу шага [step] (мяч → игрок); для нового шага — после всех.
  Map<int, int> holdersBeforeStep(int step) {
    final j = steps.indexOf(step);
    return j < 0 ? finalHolders : _holdersAt[j];
  }

  static const _grab = 0.1;

  int get stepCount => steps.length;
  bool get hasMotion => _moves.any((m) => m.isNotEmpty);

  /// Позиции после всех шагов.
  Map<int, Offset> get finalPositions => _starts.isEmpty ? const {} : _starts.last;

  /// Ключи мячей, которых не было на схеме (появляются при пасе в старых схемах).
  Iterable<int> get virtualKeys => _starts.isEmpty ? const [] : _starts.last.keys.where((k) => k < 0);

  void _build() {
    steps = scheme.steps;
    final items = scheme.items;
    final byId = <String, int>{
      for (var i = 0; i < items.length; i++)
        if (items[i].id != null) items[i].id!: i,
    };
    var pos = <int, Offset>{
      for (var i = 0; i < items.length; i++)
        if (items[i].isPlayer || items[i].type == 'ball') i: Offset(items[i].x, items[i].y),
    };
    // Мяч → игрок и смещение мяча относительно ног.
    final holder = <int, int>{};
    final offsets = <int, Offset>{};
    for (var i = 0; i < items.length; i++) {
      final h = items[i].type == 'ball' ? byId[items[i].holder] : null;
      if (h != null && items[h].isPlayer) {
        holder[i] = h;
        offsets[i] = pos[i]! - pos[h]!;
      }
    }
    final hasBalls = items.any((e) => e.type == 'ball');
    var virtual = 0;
    bool isBall(int k) => k < 0 || items[k].type == 'ball';
    bool isPlayer(int k) => k >= 0 && items[k].isPlayer;
    int? ballOf(int player) => holder.entries.where((e) => e.value == player).firstOrNull?.key;

    for (final step in steps) {
      _starts.add(Map.of(pos));
      _holdersAt.add(Map.of(holder));
      final moves = <SchemeMove>[];
      final busy = <int>{};
      final end = Map.of(pos);
      final arrows = [
        for (var i = 0; i < items.length; i++)
          if (items[i].isMovement && items[i].stepOrFirst == step) i,
      ];

      List<Offset> shifted(SchemeItem a, Offset start) {
        final p = a.path;
        final d = start - Offset(p.first.x, p.first.y);
        return [for (final q in p) Offset(q.x, q.y) + d];
      }

      // 1. Явные бег и ведение: игроки двигаются по своим путям.
      for (final ai in arrows) {
        final a = items[ai];
        final actor = byId[a.actor];
        if (actor == null || a.type == 'arrow_pass' || busy.contains(actor) || pos[actor] == null) continue;
        final path = shifted(a, pos[actor]!);
        resolvedPaths[ai] = path;
        busy.add(actor);
        moves.add(SchemeMove(actor, path));
        end[actor] = path.last;
        final ball = ballOf(actor);
        if (ball == null) continue;
        if (a.type == 'arrow_dribble') {
          final off = offsets[ball] ?? ballOffset;
          busy.add(ball);
          moves.add(SchemeMove(ball, [for (final q in path) q + off]));
          end[ball] = path.last + off;
        } else {
          // Бег без мяча: мяч остаётся на месте.
          holder.remove(ball);
        }
      }

      // 2. Явные пасы: мяч у пасующего летит к партнёру (туда, где партнёр будет в конце шага).
      for (final ai in arrows) {
        final a = items[ai];
        final actor = byId[a.actor];
        if (actor == null || a.type != 'arrow_pass' || pos[actor] == null) continue;
        final receiver = byId[a.target];
        var path = shifted(a, pos[actor]!);
        if (receiver != null && end[receiver] != null) path = [...path.sublist(0, path.length - 1), end[receiver]!];
        resolvedPaths[ai] = path;
        final ball = ballOf(actor);
        if (ball == null || busy.contains(ball)) continue;
        busy.add(ball);
        final target = receiver == null ? path.last : end[receiver]! + ballOffset;
        moves.add(SchemeMove(ball, [pos[ball]!, ...path.sublist(1, path.length - 1), target]));
        end[ball] = target;
        holder.remove(ball);
        if (receiver != null) {
          holder[ball] = receiver;
          offsets[ball] = ballOffset;
        }
      }

      // 3. Старые стрелки: двигается ближайший объект.
      for (final ai in arrows) {
        final a = items[ai];
        if (byId[a.actor] != null) continue;
        final path = [for (final q in a.path) Offset(q.x, q.y)];
        resolvedPaths[ai] = path;
        final from = path.first;
        int? nearest(bool Function(int key) accept, {double radius = _grab}) {
          int? best;
          var bestD = radius;
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

        void move(int key, {Offset offset = Offset.zero}) {
          busy.add(key);
          final p = [pos[key]!, ...path.sublist(1).map((q) => q + offset)];
          moves.add(SchemeMove(key, p));
          end[key] = p.last;
        }

        switch (a.type) {
          case 'arrow_pass':
            // Мяч на схеме есть — берём ближайший, второй мяч не появляется.
            final ball = nearest(isBall, radius: hasBalls ? 2 : _grab);
            if (ball != null) {
              move(ball);
            } else if (!hasBalls) {
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
            final ball = nearest(isBall, radius: hasBalls ? 0.15 : _grab);
            if (p != null) move(p);
            if (ball != null) {
              // мяч остаётся чуть впереди игрока
              move(ball, offset: pos[ball]! - from);
            } else if (p != null && !hasBalls) {
              final k = -(++virtual);
              pos[k] = from + const Offset(0.02, 0.02);
              _starts.last[k] = pos[k]!;
              move(k, offset: const Offset(0.02, 0.02));
            }
        }
      }
      _moves.add(moves);
      pos = end;
      // Мяч у игрока, которого никто не двигал в этом шаге, остаётся у его ног.
      for (final e in holder.entries) {
        if (!busy.contains(e.key) && pos[e.value] != null && pos[e.key] != null) {
          pos[e.key] = pos[e.value]! + (offsets[e.key] ?? ballOffset);
        }
      }
    }
    _starts.add(pos); // итоговые позиции после последнего шага
    finalHolders.addAll(holder);
  }

  /// Индекс шага, который идёт в момент [t] (t от 0 до stepCount).
  int stepIndexAt(double t) => t <= 0 ? 0 : (t >= stepCount ? stepCount - 1 : t.floor());

  /// Позиции подвижных объектов в момент [t].
  Map<int, Offset> positionsAt(double t) {
    if (stepCount == 0) return const {};
    if (t >= stepCount) return _starts.last;
    final j = stepIndexAt(t);
    final frac = Curves.easeInOut.transform(math.min(1.0, math.max(0.0, t - j)));
    final out = Map.of(_starts[j]);
    for (final m in _moves[j]) {
      out[m.key] = m.at(frac);
    }
    return out;
  }
}
