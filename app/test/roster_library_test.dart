import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/plan_rules.dart';
import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/ui/screens/library/library_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List).cast<Json>().map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json)).toList();

  test('каталог: все 81 упражнение на месте, у каждого схема и критерии успеха', () {
    expect(library.length, 81);
    expect(library.every((d) => d.scheme != null && d.successCriteria.isNotEmpty && d.steps.isNotEmpty), isTrue);
  });

  test('подробные фильтры каталога', () {
    List<Drill> run(DrillFilter f) => applyFilter(library, f, const {}, null);
    final high = run(const DrillFilter().withExtra(intensities: {'high'}));
    expect(high, isNotEmpty);
    expect(high.every((d) => d.intensity == 'high'), isTrue);
    expect(run(const DrillFilter().withExtra(maxDuration: 10)).every((d) => d.durationMin <= 10), isTrue);
    final for6 = run(const DrillFilter().withExtra(players: 6));
    expect(for6.every((d) => d.playersMin <= 6 && d.playersMax >= 6), isTrue);
    expect(run(const DrillFilter().withExtra(age: 8)).every((d) => d.ageMin <= 8 && d.ageMax >= 8), isTrue);
    final onlyBalls = run(const DrillFilter().withExtra(equipment: {'balls'}));
    expect(onlyBalls, isNotEmpty);
    expect(onlyBalls.every((d) => d.equipment.every((e) => e == 'balls')), isTrue);
    expect(const DrillFilter().withExtra(intensities: {'low'}, age: 10).extraCount, 2);
    // поиск по шагам выполнения, а не только по названию
    final step = library.first.steps.first.split(' ').where((w) => w.length > 6).first.toLowerCase();
    expect(run(DrillFilter(query: step)), contains(library.first));
  });

  test('похожие упражнения — той же категории, без самого упражнения', () {
    final d = library.firstWhere((x) => x.category == 'passing');
    final similar = similarDrills(d, library);
    expect(similar, isNotEmpty);
    expect(similar.map((x) => x.id), isNot(contains(d.id)));
    expect(similar.first.category, 'passing');
  });

  test('блок из упражнения: фаза по категории и дозировка', () {
    final warm = library.firstWhere((x) => x.category == 'warmup');
    final b = blockFromDrill(warm, id: 'x');
    expect(b.phase, 'warmup');
    expect(b.durationMin, warm.durationMin);
    expect(b.dosage, startsWith('Непрерывно'));
    expect(b.why, isNotEmpty);
  });

  test('игрок и команда: новые поля сохраняются', () {
    final p = Player.fromJson('p', Player(
      id: 'p',
      teamId: 't',
      firstName: 'Саша',
      dominantFoot: 'left',
      level: 'advanced',
      strengths: 'Скорость',
      weaknesses: 'Игра головой',
      goals: '10 голов',
    ).toJson());
    expect([p.dominantFoot, p.level, p.strengths, p.weaknesses, p.goals], ['left', 'advanced', 'Скорость', 'Игра головой', '10 голов']);
    final old = Player.fromJson('p', {'team_id': 't', 'first_name': 'Миша'});
    expect([old.dominantFoot, old.strengths], [null, '']);
    final t = Team(id: 't', name: 'T', ageGroup: 'U12', level: 'amateur', defaultPlayers: 12, formation: '2-3-1',
        seasonGoals: const [TeamGoal('Топ-3'), TeamGoal('Кубок', done: true)]);
    final back = Team.fromJson('t', t.toJson());
    expect(back.formation, '2-3-1');
    expect(back.seasonGoals.map((g) => '${g.text}:${g.done}'), ['Топ-3:false', 'Кубок:true']);
    expect(back.copyWith(seasonGoals: const [TeamGoal('Топ-3', done: true)]).seasonGoals.single.done, isTrue);
  });
}
