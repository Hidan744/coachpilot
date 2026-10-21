import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/demo_data.dart';
import 'package:coachpilot/core/dev_weeks.dart';
import 'package:coachpilot/core/performance.dart';
import 'package:coachpilot/core/recommendations.dart';
import 'package:coachpilot/core/session_summary.dart';
import 'package:coachpilot/data/db.dart';
import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/data/repo.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List).cast<Json>().map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json)).toList();

  group('понедельная программа', () {
    for (final weeks in [4, 8, 12]) {
      test('$weeks недель: этапы по порядку, упражнения из каталога, есть критерии', () {
        final plan = buildPlanWeeks(weeks: weeks, focus: ['passing', 'finishing'], library: library, age: 12, minutes: 25);
        expect(plan.length, weeks);
        expect(plan.map((w) => w.n), List.generate(weeks, (i) => i + 1));
        expect(plan.first.load, contains('25 мин'));
        final names = {for (final d in library) d.title};
        for (final w in plan) {
          expect(w.drills, isNotEmpty);
          expect(names, containsAll(w.drills));
          expect(w.criteria, isNotEmpty);
          expect(w.expected, startsWith('Ориентир'));
        }
        // Навыки чередуются по неделям.
        expect(plan[0].priority, isNot(plan[1].priority));
      });
    }

    test('упражнения подходят возрасту и индивидуальной работе', () {
      final byTitle = {for (final d in library) d.title: d};
      for (final w in buildPlanWeeks(weeks: 6, focus: ['dribbling'], library: library, age: 9)) {
        for (final t in w.drills) {
          final d = byTitle[t]!;
          expect(d.playersMin, lessThanOrEqualTo(4));
          expect(9, inInclusiveRange(d.ageMin, d.ageMax));
        }
      }
    });

    test('недели и отметки сохраняются в плане', () {
      final weeks = buildPlanWeeks(weeks: 4, focus: ['technique'], library: library, age: 14);
      final plan = DevelopmentPlan(
        id: 'p',
        playerId: 'pl',
        period: 'cycle8',
        title: 'План',
        weeks: [weeks.first.copyWith(done: true, comment: 'Хорошо'), ...weeks.skip(1)],
      );
      final back = DevelopmentPlan.fromJson('p', jsonDecode(jsonEncode(plan.toJson())) as Json);
      expect(back.weeks.length, 4);
      expect(back.weeks.first.done, isTrue);
      expect(back.weeks.first.comment, 'Хорошо');
      expect(back.weeks.last.drills, weeks.last.drills);
      expect(PlanPeriods.weeks('cycle12'), 12);
    });
  });

  group('сводка занятия', () {
    final s = TrainingSession(
      id: 's',
      title: 'Передачи',
      goal: 'передачи',
      durationMin: 60,
      status: 'done',
      blocks: [
        TrainingBlock(id: 'a', phase: 'warmup', title: 'Разминка', durationMin: 15),
        TrainingBlock(id: 'b', phase: 'main', title: 'Квадрат 4×2', durationMin: 30),
        TrainingBlock(id: 'c', phase: 'cooldown', title: 'Заминка', durationMin: 15),
      ],
      actual: const {
        'blocks': {'a': 900, 'b': 2400},
        'skipped': ['c'],
      },
    );
    Attendance at(String p, String st) => Attendance(id: p, sessionId: 's', playerId: p, status: st);

    test('без данных — ничего не выдумывает, а говорит, чего не хватает', () {
      final empty = summarizeSession(TrainingSession(id: 'x', title: 'X', durationMin: 60), null, const []);
      expect(empty.achieved, isEmpty);
      expect(empty.problems, isEmpty);
      expect(empty.next, isEmpty);
      expect(empty.missingData.length, 3);
    });

    test('факт, посещаемость и отчёт тренера — с основанием у каждого пункта', () {
      final r = SessionReport(
        id: 'r',
        sessionId: 's',
        rating: 2,
        rpe: 9,
        wentWell: 'Темп передач',
        toImprove: 'Открывания',
        nextTime: 'Добавить игру 3×3',
        playerNotes: const {'p1': 'Лучший на занятии'},
      );
      final sum = summarizeSession(s, r, [at('p1', 'present'), at('p2', 'absent'), at('p3', 'absent'), at('p4', 'injured')]);
      expect(sum.achieved.first.text, 'Проведено блоков: 2 из 3, 55 из 60 мин');
      expect(sum.notDone.single.text, contains('Заминка'));
      expect(sum.problems.map((i) => i.text), containsAll(['Низкая посещаемость: 25%', 'Травмы: 1', 'Открывания']));
      expect(sum.problems.any((i) => i.text.contains('Квадрат') && i.text.contains('дольше')), isTrue);
      expect(sum.next.map((i) => i.text).join(), allOf(contains('RPE 9'), contains('Добавить игру 3×3'), contains('Перенести')));
      for (final i in [...sum.achieved, ...sum.notDone, ...sum.problems, ...sum.next]) {
        expect(i.basis, isNotEmpty);
      }
      final text = reportAsText(s, r, sum, {'p1': 'Иванов Пётр'});
      expect(text, contains('Иванов Пётр: Лучший на занятии'));
      expect(text, contains('[отчёт тренера]'));
      expect(text, isNot(contains('Не хватает данных')));
    });

    test('заметки по игрокам и «что изменить» сохраняются', () {
      final r = SessionReport(id: 'r', sessionId: 's', playerNotes: const {'p1': 'Молодец'}, nextTime: 'Меньше зона');
      final back = SessionReport.fromJson('r', jsonDecode(jsonEncode(r.toJson())) as Json);
      expect(back.playerNotes, {'p1': 'Молодец'});
      expect(back.nextTime, 'Меньше зона');
    });
  });

  group('рекомендации тренеру', () {
    test('пустая команда — нет выводов, только список недостающих данных', () {
      final rec = coachRecommendations(
        team: Team(id: 't', name: 'T', ageGroup: 'U12', level: 'amateur', defaultPlayers: 14),
        players: const [],
        sessions: const [],
        reports: const {},
        attendance: const [],
        matches: const [],
        plans: const [],
        library: library,
        season: const {},
        now: DateTime(2026, 10, 20),
      );
      // Только общая возрастная памятка — без выводов о команде, которых не из чего сделать.
      expect(rec.team.map((a) => a.kind), everyElement('info'));
      expect(rec.nextSession, isEmpty);
      expect(rec.players, isEmpty);
      expect(rec.week, isEmpty);
      expect(rec.missing, isNotEmpty);
    });

    test('на примере данных: у каждого совета есть основание и следующий шаг', () async {
      final db = AppDb(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = Repo(db);
      final now = DateTime(2026, 10, 20);
      final teamId = await db.transaction(() => seedDemoData(repo, now: now));
      final team = (await repo.list(Entities.teams, Team.fromJson)).firstWhere((t) => t.id == teamId);
      final players = await repo.list(Entities.players, Player.fromJson, parentId: teamId);
      final sessions = await repo.list(Entities.sessions, TrainingSession.fromJson);
      final attendance = await repo.list(Entities.attendance, Attendance.fromJson);
      final stats = await repo.list(Entities.matchStats, MatchStat.fromJson);
      final rec = coachRecommendations(
        team: team,
        players: [
          for (final p in players)
            PlayerSnapshot(
              player: p,
              now: now,
              assessments: await repo.list(Entities.assessments, PlayerAssessment.fromJson),
              tests: await repo.list(Entities.physicalTests, PhysicalTest.fromJson),
              attendance: attendance,
              sessions: {for (final s in sessions) s.id: s},
              stats: stats,
            ),
        ],
        sessions: sessions,
        reports: {for (final r in await repo.list(Entities.reports, SessionReport.fromJson)) r.sessionId: r},
        attendance: attendance,
        matches: await repo.list(Entities.matches, Match.fromJson),
        plans: await repo.list(Entities.devPlans, DevelopmentPlan.fromJson),
        library: library,
        season: seasonStats(stats),
        now: now,
      );
      expect(rec.isEmpty, isFalse);
      for (final a in [...rec.team, ...rec.nextSession, ...rec.players, ...rec.week]) {
        expect(a.basis, isNotEmpty, reason: a.title);
        expect(a.next, isNotEmpty, reason: a.title);
      }
    });
  });

  test('резервная копия: сохранить и восстановить в чистую базу', () async {
    final src = AppDb(NativeDatabase.memory()), dst = AppDb(NativeDatabase.memory());
    addTearDown(src.close);
    addTearDown(dst.close);
    final a = Repo(src), b = Repo(dst);
    await src.transaction(() => seedDemoData(a, now: DateTime(2026, 10, 20)));
    final backup = jsonDecode(jsonEncode(await a.backup())) as Json;
    final n = await b.restore(backup);
    expect(n, (backup['data'] as Map).values.fold<int>(0, (s, l) => s + (l as List).length));
    final before = await a.list(Entities.players, Player.fromJson), after = await b.list(Entities.players, Player.fromJson);
    expect(after.map((p) => p.id).toSet(), before.map((p) => p.id).toSet());
    expect(after.first.toJson(), before.firstWhere((p) => p.id == after.first.id).toJson());
    expect(() => b.restore({'app': 'Other'}), throwsFormatException);
  });
}
