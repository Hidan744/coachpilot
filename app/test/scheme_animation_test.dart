import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/scheme_animation.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool near(Offset a, Offset b) => (a - b).distance < 1e-6;

  test('пас двигает мяч, бег — игрока; шаги по очереди', () {
    const s = Scheme(items: [
      SchemeItem(type: 'player_a', x: 0.2, y: 0.5), // 0 пасующий
      SchemeItem(type: 'ball', x: 0.22, y: 0.52), // 1
      SchemeItem(type: 'player_a', x: 0.8, y: 0.5), // 2 принимающий
      SchemeItem(type: 'arrow_pass', x: 0.2, y: 0.5, x2: 0.8, y2: 0.5, step: 1),
      SchemeItem(type: 'arrow_run', x: 0.2, y: 0.5, x2: 0.5, y2: 0.2, step: 2),
    ]);
    final a = SchemeAnimation(s);
    expect(a.stepCount, 2);
    expect(a.hasMotion, isTrue);

    // начало: всё на местах
    expect(near(a.positionsAt(0)[1]!, const Offset(0.22, 0.52)), isTrue);
    // середина шага 1: мяч в пути, пасующий стоит
    final mid = a.positionsAt(0.5);
    expect(mid[1]!.dx, greaterThan(0.3));
    expect(near(mid[0]!, const Offset(0.2, 0.5)), isTrue);
    expect(a.stepIndexAt(0.5), 0);
    // после шага 1 мяч у принимающего, шаг 2 — пасующий убегает
    expect(near(a.positionsAt(1)[1]!, const Offset(0.8, 0.5)), isTrue);
    expect(a.stepIndexAt(1.5), 1);
    final end = a.positionsAt(2);
    expect(near(end[0]!, const Offset(0.5, 0.2)), isTrue);
    expect(near(end[2]!, const Offset(0.8, 0.5)), isTrue);
  });

  test('ведение: игрок двигается вместе с мячом', () {
    const s = Scheme(items: [
      SchemeItem(type: 'player_b', x: 0.1, y: 0.9),
      SchemeItem(type: 'ball', x: 0.12, y: 0.88),
      SchemeItem(type: 'arrow_dribble', x: 0.1, y: 0.9, x2: 0.6, y2: 0.4),
    ]);
    final end = SchemeAnimation(s).positionsAt(1);
    expect(near(end[0]!, const Offset(0.6, 0.4)), isTrue);
    expect(near(end[1]!, const Offset(0.62, 0.38)), isTrue);
  });

  test('пас без нарисованного мяча — мяч появляется сам', () {
    const s = Scheme(items: [
      SchemeItem(type: 'player_a', x: 0.2, y: 0.2),
      SchemeItem(type: 'arrow_pass', x: 0.2, y: 0.2, x2: 0.7, y2: 0.7),
    ]);
    final a = SchemeAnimation(s);
    expect(a.positionsAt(0).keys.where((k) => k < 0), hasLength(1));
    expect(near(a.positionsAt(1)[-1]!, const Offset(0.7, 0.7)), isTrue);
  });

  test('стрелки одного шага двигаются одновременно; без стрелок анимации нет', () {
    const s = Scheme(items: [
      SchemeItem(type: 'player_a', x: 0.1, y: 0.1),
      SchemeItem(type: 'player_a', x: 0.9, y: 0.1),
      SchemeItem(type: 'arrow_run', x: 0.1, y: 0.1, x2: 0.1, y2: 0.9),
      SchemeItem(type: 'arrow_run', x: 0.9, y: 0.1, x2: 0.9, y2: 0.9),
    ]);
    final a = SchemeAnimation(s);
    expect(a.stepCount, 1);
    final mid = a.positionsAt(0.5);
    expect(mid[0]!.dy, closeTo(mid[1]!.dy, 1e-9));
    expect(SchemeAnimation(const Scheme(items: [SchemeItem(type: 'cone', x: 0.5, y: 0.5)])).hasMotion, isFalse);
  });

  test('шаг сохраняется в JSON', () {
    const it = SchemeItem(type: 'arrow_run', x: 0, y: 0, x2: 1, y2: 1, step: 3);
    expect(SchemeItem.fromJson(it.toJson()).step, 3);
    expect(it.moved(0.1, 0).step, 3);
  });

  test('в каталоге каждая анимированная схема двигает объекты на каждом шаге', () {
    final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
    var animated = 0;
    for (final r in (bundle['drills'] as List).cast<Json>()) {
      final d = Drill.fromJson(r['id'] as String, r['data'] as Json);
      final scheme = d.scheme;
      if (scheme == null || scheme.steps.isEmpty) continue;
      final a = SchemeAnimation(scheme);
      animated++;
      for (var j = 0; j < a.stepCount; j++) {
        final before = a.positionsAt(j.toDouble()), after = a.positionsAt(j + 0.999);
        final moved = after.keys.any((k) => before[k] == null || (after[k]! - before[k]!).distance > 0.01);
        expect(moved, isTrue, reason: '${d.title}: шаг ${j + 1} ничего не двигает');
      }
    }
    expect(animated, greaterThan(60));
  });

  group('схемы с привязкой к игроку', () {
    // Нападающий A с мячом, защитник D без мяча, партнёр B.
    const a = SchemeItem(type: 'player_a', x: 0.2, y: 0.8, id: 'A');
    const ball = SchemeItem(type: 'ball', x: 0.225, y: 0.825, id: 'M', holder: 'A');
    const d = SchemeItem(type: 'player_b', x: 0.4, y: 0.5, id: 'D');
    const b = SchemeItem(type: 'player_a', x: 0.8, y: 0.6, id: 'B');

    test('ведение по точкам: игрок проходит весь путь до последней точки, мяч у ног', () {
      const s = Scheme(items: [
        a, ball, d, b,
        SchemeItem(type: 'arrow_dribble', x: 0.2, y: 0.8, actor: 'A', step: 1, points: [
          Offset2(0.2, 0.8), Offset2(0.3, 0.6), Offset2(0.5, 0.4),
        ]),
      ]);
      final an = SchemeAnimation(s);
      final endPos = an.positionsAt(1);
      expect(near(endPos[0]!, const Offset(0.5, 0.4)), isTrue);
      expect(near(endPos[1]!, const Offset(0.525, 0.425)), isTrue);
      // защитник без мяча стоит, второго мяча нет
      expect(near(endPos[2]!, const Offset(0.4, 0.5)), isTrue);
      expect(an.virtualKeys, isEmpty);
      // середина пути — на ломаной, а не на прямой от начала к концу
      final mid = an.positionsAt(0.5)[0]!;
      expect(mid.dx, greaterThan(0.25));
    });

    test('пас партнёру: мяч уходит к нему, следующее ведение — уже у партнёра', () {
      const s = Scheme(items: [
        a, ball, d, b,
        SchemeItem(type: 'arrow_pass', x: 0.2, y: 0.8, x2: 0.8, y2: 0.6, actor: 'A', target: 'B', step: 1),
        SchemeItem(type: 'arrow_run', x: 0.4, y: 0.5, x2: 0.7, y2: 0.55, actor: 'D', step: 1),
        SchemeItem(type: 'arrow_dribble', x: 0.8, y: 0.6, x2: 0.8, y2: 0.2, actor: 'B', step: 2),
        // пас без мяча у пасующего ничего не делает
        SchemeItem(type: 'arrow_pass', x: 0.4, y: 0.5, x2: 0.2, y2: 0.8, actor: 'D', target: 'A', step: 2),
      ]);
      final an = SchemeAnimation(s);
      expect(an.stepCount, 2);
      final after1 = an.positionsAt(1);
      expect(near(after1[1]!, const Offset(0.8, 0.6) + ballOffset), isTrue);
      expect(near(after1[2]!, const Offset(0.7, 0.55)), isTrue);
      final after2 = an.positionsAt(2);
      expect(near(after2[3]!, const Offset(0.8, 0.2)), isTrue);
      expect(near(after2[1]!, const Offset(0.8, 0.2) + ballOffset), isTrue);
      expect(an.finalHolders[1], 3);
    });

    test('путь следующего шага начинается там, где игрок оказался', () {
      const s = Scheme(items: [
        a,
        SchemeItem(type: 'arrow_run', x: 0.2, y: 0.8, x2: 0.2, y2: 0.5, actor: 'A', step: 1),
        // нарисован от старого места — проигрывается от нового
        SchemeItem(type: 'arrow_run', x: 0.2, y: 0.8, x2: 0.5, y2: 0.8, actor: 'A', step: 2),
      ]);
      final an = SchemeAnimation(s);
      expect(near(an.resolvedPaths[2]!.first, const Offset(0.2, 0.5)), isTrue);
      expect(near(an.positionsAt(2)[0]!, const Offset(0.5, 0.5)), isTrue);
    });

    test('бег игрока с мячом оставляет мяч на месте', () {
      const s = Scheme(items: [
        a, ball,
        SchemeItem(type: 'arrow_run', x: 0.2, y: 0.8, x2: 0.6, y2: 0.8, actor: 'A', step: 1),
      ]);
      final end = SchemeAnimation(s).positionsAt(1);
      expect(near(end[1]!, const Offset(0.225, 0.825)), isTrue);
    });

    test('старая схема с мячом далеко от начала паса — второй мяч не появляется', () {
      const s = Scheme(items: [
        SchemeItem(type: 'player_a', x: 0.2, y: 0.2),
        SchemeItem(type: 'ball', x: 0.5, y: 0.5),
        SchemeItem(type: 'arrow_pass', x: 0.2, y: 0.2, x2: 0.7, y2: 0.7),
      ]);
      final an = SchemeAnimation(s);
      expect(an.virtualKeys, isEmpty);
      expect(near(an.positionsAt(1)[1]!, const Offset(0.7, 0.7)), isTrue);
    });
  });
}
