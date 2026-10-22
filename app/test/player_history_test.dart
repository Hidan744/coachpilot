import 'dart:convert';

import 'package:coachpilot/core/player_timeline.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Json roundtrip(Json j) => jsonDecode(jsonEncode(j)) as Json;

  group('цели игрока', () {
    test('«больше — лучше»: достигнута, когда текущее ≥ цели', () {
      const t = PlanTarget(name: 'Передачи', current: 82, target: 85, unit: '%', kind: 'technical');
      expect(t.lowerBetter, isFalse);
      expect(t.reached, isFalse);
      expect(const PlanTarget(name: 'x', current: 86, target: 85).reached, isTrue);
    });

    test('«меньше — лучше» (бег): направление берётся от первого замера и не теряется после цели', () {
      final t = PlanTarget(
        name: 'Бег 30 м',
        current: 4.9,
        target: 5.0,
        unit: 'с',
        checkpoints: [TargetCheckpoint(DateTime(2026, 9, 1), 5.4), TargetCheckpoint(DateTime(2026, 10, 1), 4.9)],
      );
      expect(t.lowerBetter, isTrue);
      expect(t.reached, isTrue);
      expect(t.progress, 1.0);
    });

    test('срок прошёл — цель просрочена, если не достигнута', () {
      final t = PlanTarget(name: 'x', current: 1, target: 5, due: DateTime(2026, 10, 1));
      expect(t.overdue(DateTime(2026, 10, 20)), isTrue);
      expect(t.overdue(DateTime(2026, 9, 20)), isFalse);
    });

    test('вид, срок и замеры сохраняются', () {
      final t = PlanTarget(
        name: 'Удары в створ',
        current: 6,
        target: 8,
        kind: 'technical',
        due: DateTime(2026, 12, 15),
        checkpoints: [TargetCheckpoint(DateTime(2026, 10, 1), 5, note: 'старт'), TargetCheckpoint(DateTime(2026, 10, 15), 6)],
      );
      final back = PlanTarget.fromJson(roundtrip(t.toJson()));
      expect(back.kind, 'technical');
      expect(back.due, DateTime(2026, 12, 15));
      expect(back.checkpoints.map((c) => c.value), [5, 6]);
      expect(back.checkpoints.first.note, 'старт');
    });
  });

  group('профиль игрока', () {
    final a = Player(id: 'p', teamId: 't', firstName: 'Иван', lastName: 'Петров', position: 'DF', number: 5);

    test('история изменений: что поменялось — словами', () {
      final b = Player(id: 'p', teamId: 't', firstName: 'Иван', lastName: 'Петров', position: 'MF', number: 7, active: false);
      final d = Player.diff(a, b);
      expect(d, contains('Позиция: Защитник → Полузащитник'));
      expect(d, contains('Номер: 5 → 7'));
      expect(d, contains('Выбыл из состава'));
      expect(Player.diff(a, a), isEmpty);
    });

    test('изменения сохраняются в профиле', () {
      final p = Player.fromJson('p', {...a.toJson(), 'changes': [ProfileChange(DateTime(2026, 10, 1), 'Номер: 5 → 7').toJson()]});
      final back = Player.fromJson('p', roundtrip(p.toJson()));
      expect(back.changes.single.text, 'Номер: 5 → 7');
    });
  });

  group('упражнение', () {
    test('ошибки, источник, права и видео сохраняются; у каталога права «Каталог CoachPilot»', () {
      final d = Drill(
        id: 'd',
        title: 'Квадрат',
        category: 'possession',
        mistakes: ['Стоят на месте'],
        sourceRef: 'Своё',
        license: 'own',
        videoUrl: 'https://example.com/v',
        tags: ['рондо'],
      );
      final back = Drill.fromJson('d', roundtrip(d.toJson()));
      expect(back.mistakes, ['Стоят на месте']);
      expect(back.videoUrl, 'https://example.com/v');
      expect(back.tags, ['рондо']);
      expect(Drill.fromJson('s', {'source': 'system', 'title': 'x', 'category': 'passing'}).license, 'catalog');
    });
  });

  test('хронология игрока: всё по датам, у каждого события источник, оценки отдельно от измерений', () {
    final p = Player(
      id: 'p',
      teamId: 't',
      firstName: 'Иван',
      changes: [ProfileChange(DateTime(2026, 10, 18), 'Номер: 5 → 7')],
    );
    final s = TrainingSession(id: 's', teamId: 't', title: 'Передачи', durationMin: 60, status: 'done', finishedAt: DateTime(2026, 10, 10));
    final m = Match(id: 'm', teamId: 't', opponent: 'Динамо', startsAt: DateTime(2026, 10, 12), scoreFor: 2, scoreAgainst: 1);
    final events = playerTimeline(
      player: p,
      sessions: [s],
      attendance: [Attendance(id: 'a', sessionId: 's', playerId: 'p', status: 'present')],
      reports: {'s': SessionReport(id: 'r', sessionId: 's', playerNotes: const {'p': 'Хорошо открывался'})},
      matches: [m],
      stats: [MatchStat(id: 'x', matchId: 'm', playerId: 'p', minutes: 60, stats: const {'goals': 1})],
      tests: [PhysicalTest(id: 'ft', playerId: 'p', testedOn: DateTime(2026, 10, 5), results: const {'sprint_30m': 4.9})],
      assessments: [PlayerAssessment(id: 'as', playerId: 'p', skill: 'passing', score: 4, assessedAt: DateTime(2026, 10, 15))],
      plans: const [],
    );
    expect(events.map((e) => e.kind), ['profile', 'assessment', 'match', 'training', 'test']);
    expect(events.firstWhere((e) => e.kind == 'training').detail, contains('Хорошо открывался'));
    expect(events.firstWhere((e) => e.kind == 'assessment').source, contains('субъективно'));
    expect(events.firstWhere((e) => e.kind == 'test').source, contains('измерение'));
    expect(events.firstWhere((e) => e.kind == 'match').title, contains('2:1'));
    for (final e in events) {
      expect(e.source, isNotEmpty);
    }
  });
}
