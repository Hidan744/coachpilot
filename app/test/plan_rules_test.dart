import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/plan_rules.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List)
      .cast<Json>()
      .map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json))
      .toList();

  test('каталог встроен в приложение', () {
    expect(library.length, greaterThanOrEqualTo(80));
    expect(bundle['version'], isA<String>());
  });

  test('цель → категории основной части', () {
    expect(mainCategories('Удары по воротам'), ['finishing']);
    expect(mainCategories('Передачи и владение').take(2), ['passing', 'possession']);
    expect(mainCategories('что-то общее'), contains('passing'));
    expect(mainCategories('', ['physical']), ['physical']);
  });

  for (final age in ['U8', 'U11', 'U14', 'adult']) {
    for (final players in [6, 12, 20]) {
      for (final duration in [45, 60, 90]) {
        test('офлайн-план $age, $players игроков, $duration мин', () {
          final team = Team(
            id: 't',
            name: 'T',
            ageGroup: age,
            level: 'amateur',
            defaultPlayers: players,
            equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals'],
          );
          final blocks = planByRules(
            library: library,
            team: team,
            players: players,
            durationMin: duration,
            goal: 'Передачи и удары',
          );
          expect(blocks, isNotEmpty);
          expect(blocks.fold<int>(0, (a, b) => a + b.durationMin), duration);
          expect(blocks.first.phase, 'warmup');
          final a = AgeGroups.age(age);
          for (final b in blocks) {
            final d = b.drillSnapshot!;
            expect(a >= d.ageMin && a <= d.ageMax, isTrue, reason: '${d.title} возраст');
            expect(d.playersMin <= players, isTrue, reason: '${d.title} состав');
          }
          expect(blocks.map((b) => b.drillId).toSet().length, blocks.length, reason: 'без повторов');
        });
      }
    }
  }
}
