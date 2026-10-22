import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/plan_context.dart';
import 'package:coachpilot/core/plan_rules.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List).cast<Json>().map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json)).toList();
  final team = Team(
    id: 't',
    name: 'T',
    ageGroup: 'U14',
    level: 'amateur',
    defaultPlayers: 16,
    equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals'],
  );
  int sum(List<TrainingBlock> b) => b.fold(0, (a, x) => a + x.durationMin);

  group('площадка', () {
    test('размер упражнения по описанию площадки', () {
      Drill d(String size) => Drill(id: 'x', source: 'system', title: 'x', category: 'passing', fieldSize: size);
      expect(areaNeed(d('Половина поля')), 2);
      expect(areaNeed(d('Штрафная')), 1);
      expect(areaNeed(d('20×20 м')), 0);
      expect(areaNeed(d('30×20 м')), 0);
      expect(areaNeed(d('35×25 м')), 1);
      expect(areaNeed(d('40×30 м')), 1);
      expect(areaNeed(d('50×40 м')), 2);
      expect(areaNeed(d('Коридор 15 м')), 0);
      expect(areaNeed(d('')), 0);
    });

    test('на мини-площадке план собирается только из упражнений, которым хватает места', () {
      final blocks = planByRules(library: library, team: team, players: 14, durationMin: 60, goal: 'передачи', field: 'box');
      expect(blocks, isNotEmpty);
      expect(sum(blocks), 60);
      for (final b in blocks) {
        expect(areaNeed(b.drillSnapshot!), 0, reason: '${b.title}: ${b.drillSnapshot!.fieldSize}');
      }
    });
  });

  group('конструктор: разные составы и инвентарь', () {
    for (final players in [6, 10, 18]) {
      for (final eq in [const ['balls', 'cones'], const ['balls', 'cones', 'bibs', 'goals']]) {
        test('$players игроков, инвентарь $eq — сумма = 75 мин, все упражнения выполнимы', () {
          final blocks = planByRules(library: library, team: team, players: players, durationMin: 75, goal: 'владение мячом', equipment: eq);
          expect(sum(blocks), 75);
          for (final b in blocks) {
            final d = b.drillSnapshot!;
            expect(d.playersMin, lessThanOrEqualTo(players), reason: b.title);
            for (final e in d.equipment) {
              expect(e == 'balls' || e == 'cones' || eq.contains(e), isTrue, reason: '${b.title}: $e');
            }
          }
        });
      }
    }
  });

  group('история команды', () {
    final players = [
      for (var i = 0; i < 4; i++) Player(id: 'p$i', teamId: 't', firstName: 'И', lastName: 'Игрок$i', active: true),
    ];
    final now = DateTime(2026, 10, 20, 12);
    TrainingSession done(String id, int daysAgo, String drillId) => TrainingSession(
          id: id,
          teamId: 't',
          title: 'Занятие $id',
          durationMin: 60,
          status: 'done',
          finishedAt: now.subtract(Duration(days: daysAgo)),
          blocks: [TrainingBlock(id: 'b', phase: 'main', title: 'Б', durationMin: 60, drillId: drillId)],
        );
    final sessions = [done('s1', 1, 'd1'), done('s2', 3, 'd2'), done('s3', 20, 'd3')];

    test('без истории — пустая подсказка, ничего не выдумывается', () {
      final h = teamHistory(team: team, sessions: const [], reports: const {}, attendance: const [], players: players, now: now);
      expect(h.isEmpty, isTrue);
      expect(h.suggestedIntensity, isNull);
      expect(h.recentDrillIds, isEmpty);
    });

    test('тяжёлые занятия → низкая интенсивность; недавние упражнения и приоритеты из отчёта', () {
      final h = teamHistory(
        team: team,
        sessions: sessions,
        reports: {
          's1': SessionReport(id: 'r1', sessionId: 's1', rpe: 9, nextTime: 'Больше игр 3×3', toImprove: 'Открывания'),
          's2': SessionReport(id: 'r2', sessionId: 's2', rpe: 8),
        },
        attendance: [
          for (final s in ['s1', 's2']) Attendance(id: '$s-p0', sessionId: s, playerId: 'p0', status: 'absent'),
          Attendance(id: 's1-p1', sessionId: 's1', playerId: 'p1', status: 'injured'),
        ],
        players: players,
        now: now,
      );
      expect(h.suggestedIntensity, 'low');
      expect(h.intensityReason, contains('RPE 9 и 8'));
      expect(h.recentDrillIds, {'d1', 'd2'});
      expect(h.priorities.map((p) => p.text), containsAll(['Больше игр 3×3', 'Открывания']));
      expect(h.absentLately.map((p) => p.id), ['p0']);
      expect(h.injured, {'p1'});
      for (final n in h.notes) {
        expect(n.basis, isNotEmpty);
      }
    });

    test('матч завтра → подводка с низкой интенсивностью', () {
      final h = teamHistory(
        team: team,
        sessions: sessions,
        reports: const {},
        attendance: const [],
        players: players,
        matches: [Match(id: 'm', teamId: 't', opponent: 'Динамо', startsAt: now.add(const Duration(hours: 26)))],
        now: now,
      );
      expect(h.suggestedIntensity, 'low');
      expect(h.intensityReason, contains('Динамо'));
    });

    test('конструктор не повторяет упражнения последних занятий, если есть замена', () {
      final first = planByRules(library: library, team: team, players: 14, durationMin: 75, goal: 'передачи');
      final recent = {for (final b in first) b.drillId!};
      final second = planByRules(library: library, team: team, players: 14, durationMin: 75, goal: 'передачи', recentDrillIds: recent);
      final repeated = second.where((b) => recent.contains(b.drillId)).length;
      expect(repeated, lessThan(first.length));
    });
  });

  group('план к проведению', () {
    final blocks = planByRules(library: library, team: team, players: 16, durationMin: 90, goal: 'удары по воротам');

    test('переход называет следующее упражнение и что подготовить', () {
      final note = transitionNote(blocks[0], blocks[1]);
      expect(note, contains(blocks[1].title));
    });

    test('у каждого блока есть подсказка на случай нехватки игроков', () {
      for (final b in blocks) {
        expect(fewerPlayersNote(b, library, team), isNotEmpty, reason: b.title);
      }
    });

    test('план Б: без больших ворот и на мини-площадке', () {
      final alt = planB(blocks, library, team, 16);
      expect(alt, isNotEmpty);
      for (final d in alt.values) {
        expect(areaNeed(d), 0);
        expect(d.equipment, isNot(contains('goals')));
      }
    });
  });

  group('пересборка только затронутых блоков', () {
    final blocks = planByRules(library: library, team: team, players: 16, durationMin: 90, goal: 'удары по воротам');

    test('те же условия — ничего не меняется', () {
      final r = adaptPlan(
        blocks: blocks,
        library: library,
        team: team,
        conditions: PlanConditions(players: 16, durationMin: 90, equipment: team.equipment),
        oldDurationMin: 90,
      );
      expect(r.changes, isEmpty);
      expect(r.blocks.map((b) => b.drillId), blocks.map((b) => b.drillId));
    });

    test('нет ворот и мини-площадка — меняются только неподходящие блоки, правки остальных сохраняются', () {
      final edited = [blocks.first.copyWith(notes: 'Моя заметка'), ...blocks.skip(1)];
      final r = adaptPlan(
        blocks: edited,
        library: library,
        team: team,
        conditions: const PlanConditions(players: 16, durationMin: 90, equipment: ['bibs'], field: 'box'),
        oldDurationMin: 90,
      );
      expect(sum(r.blocks), 90);
      for (var i = 0; i < edited.length; i++) {
        final d = edited[i].drillSnapshot!;
        final ok = areaNeed(d) == 0 && !d.equipment.any((e) => e == 'goals' || e == 'mini_goals');
        if (ok) expect(r.blocks[i].drillId, edited[i].drillId);
      }
      expect(r.blocks.first.notes, 'Моя заметка');
      expect(r.changes, isNotEmpty);
    });

    test('новая длительность — сумма блоков ровно равна ей', () {
      for (final total in [45, 60, 120]) {
        final r = adaptPlan(
          blocks: blocks,
          library: library,
          team: team,
          conditions: PlanConditions(players: 16, durationMin: total, equipment: team.equipment),
          oldDurationMin: 90,
          dosage: dosageFor,
        );
        expect(sum(r.blocks), total);
      }
    });

    test('rescale сохраняет сумму и минимум 3 мин', () {
      final out = rescale([15, 30, 30, 10, 5], 47);
      expect(out.fold<int>(0, (a, b) => a + b), 47);
      expect(out.every((m) => m >= 3), isTrue);
    });
  });
}
