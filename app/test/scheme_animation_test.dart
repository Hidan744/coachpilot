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
}
