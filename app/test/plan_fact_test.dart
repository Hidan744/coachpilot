import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/recommendations.dart';
import 'package:coachpilot/core/session_summary.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List).cast<Json>().map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json)).toList();
  final now = DateTime(2026, 10, 20, 12);
  final team = Team(id: 't', name: 'T', ageGroup: 'U14', level: 'amateur', defaultPlayers: 14);
  final players = [for (var i = 0; i < 3; i++) Player(id: 'p$i', teamId: 't', firstName: 'И', lastName: 'Игрок$i', active: true)];

  TrainingSession done(String id, int daysAgo, {int factMin = 60, List<String> skipped = const []}) => TrainingSession(
        id: id,
        teamId: 't',
        title: 'Занятие $id',
        durationMin: 60,
        status: 'done',
        finishedAt: now.subtract(Duration(days: daysAgo)),
        blocks: [
          TrainingBlock(id: 'a', phase: 'main', title: 'Основная', durationMin: 50),
          TrainingBlock(id: 'c', phase: 'cooldown', title: 'Заминка', durationMin: 10),
        ],
        actual: {
          'blocks': {'a': factMin * 60},
          'skipped': skipped,
        },
      );

  List<Advice> run({
    List<TrainingSession> sessions = const [],
    Map<String, SessionReport> reports = const {},
    List<Attendance> attendance = const [],
    List<DevelopmentPlan> plans = const [],
    Team? t,
  }) =>
      planFactAdvice(
        team: t ?? team,
        sessions: sessions,
        reports: reports,
        attendance: attendance,
        players: players,
        plans: plans,
        library: library,
        now: now,
      );

  void complete(Advice a) {
    expect(a.text, isNotEmpty, reason: a.title);
    expect(a.basis, isNotEmpty, reason: a.title);
    expect(a.next, isNotEmpty, reason: a.title);
    expect(a.expected, isNotEmpty, reason: a.title);
    expect(confidenceLabels.containsKey(a.confidence), isTrue, reason: a.title);
  }

  test('без данных — нет выводов', () {
    expect(run(), isEmpty);
  });

  test('игрок пропустил 2 из 3 — проверить готовность, без медицинских выводов', () {
    final s = [done('s1', 1), done('s2', 3), done('s3', 5)];
    final out = run(sessions: s, attendance: [
      Attendance(id: '1', sessionId: 's1', playerId: 'p0', status: 'absent'),
      Attendance(id: '2', sessionId: 's2', playerId: 'p0', status: 'absent'),
      Attendance(id: '3', sessionId: 's3', playerId: 'p0', status: 'present'),
      Attendance(id: '4', sessionId: 's1', playerId: 'p1', status: 'absent'),
      Attendance(id: '5', sessionId: 's2', playerId: 'p1', status: 'present'),
      Attendance(id: '6', sessionId: 's3', playerId: 'p1', status: 'present'),
    ]);
    final a = out.single;
    expect(a.playerId, 'p0');
    expect(a.title, contains('2 из 3'));
    expect(a.limits, contains('не медицинский'));
    complete(a);
  });

  test('занятия систематически длиннее плана — сократить основную часть', () {
    final out = run(sessions: [done('s1', 1, factMin: 72), done('s2', 3, factMin: 70), done('s3', 5, factMin: 60)]);
    final a = out.singleWhere((x) => x.title.contains('длиннее плана'));
    expect(a.basis, contains('+12'));
    expect(a.confidence, 'medium');
    complete(a);
  });

  test('один выход за время — это не система', () {
    expect(run(sessions: [done('s1', 1, factMin: 75), done('s2', 3, factMin: 50), done('s3', 5, factMin: 50)])
        .where((x) => x.title.contains('длиннее')), isEmpty);
  });

  test('часто пропускаемая часть занятия', () {
    final out = run(sessions: [done('s1', 1, skipped: ['c']), done('s2', 3, skipped: ['c'])]);
    expect(out.any((a) => a.title.contains('заминка')), isTrue);
  });

  test('тема «передачи» 3 раза за 4 недели — новые упражнения и контрольное задание', () {
    final s = [done('s1', 2), done('s2', 9), done('s3', 16), done('s4', 40)];
    final out = run(sessions: s, reports: {
      's1': SessionReport(id: 'r1', sessionId: 's1', toImprove: 'Точность передач'),
      's2': SessionReport(id: 'r2', sessionId: 's2', toImprove: 'Передачи под давлением'),
      's3': SessionReport(id: 'r3', sessionId: 's3', nextTime: 'Больше передач в одно касание'),
      's4': SessionReport(id: 'r4', sessionId: 's4', toImprove: 'Передачи'),
    });
    final a = out.singleWhere((x) => x.kind == 'work');
    expect(a.title, contains('3 раза'));
    expect(a.next, contains('«'));
    expect(a.limits, contains('не измерение'));
    complete(a);
  });

  test('цель сезона выполнена и программа игрока завершена — следующий этап', () {
    final t = Team(id: 't', name: 'T', ageGroup: 'U14', level: 'amateur', defaultPlayers: 14, seasonGoals: const [TeamGoal('Меньше пропущенных', done: true)]);
    final out = run(t: t, plans: [
      DevelopmentPlan(
        id: 'd',
        playerId: 'p2',
        period: 'cycle4',
        title: 'Передачи',
        weeks: [for (var n = 1; n <= 4; n++) PlanWeek(n: n, priority: 'Передачи', done: true)],
      ),
    ]);
    expect(out.map((a) => a.title), containsAll(['Цель «Меньше пропущенных» выполнена', 'И Игрок2: программа «Передачи» выполнена']));
    out.forEach(complete);
  });

  test('ключ рекомендации стабилен в течение недели и не зависит от чисел', () {
    const a = Advice('down', 'Занятия длиннее плана в среднем на 12 мин', 'x');
    const b = Advice('down', 'Занятия длиннее плана в среднем на 9 мин', 'x');
    expect(adviceKey(a, now), adviceKey(b, now.add(const Duration(days: 2))));
    expect(adviceKey(a, now), isNot(adviceKey(a, now.add(const Duration(days: 7)))));
  });

  test('решение тренера сохраняется', () {
    final d = AdviceDecision(id: 'x', teamId: 't', key: 'k', status: 'edited', note: 'Сделаю по-своему', decidedAt: now);
    final back = AdviceDecision.fromJson('x', jsonDecode(jsonEncode(d.toJson())) as Json);
    expect(back.status, 'edited');
    expect(back.note, 'Сделаю по-своему');
  });

  test('сводка после занятия: на чём сосредоточиться', () {
    final s = done('s1', 1, skipped: ['c']);
    expect(summarizeSession(s, null, const []).focus!.text, contains('Заминка'));
    final r = SessionReport(id: 'r', sessionId: 's1', nextTime: 'Игры 3×3');
    expect(summarizeSession(s, r, const []).focus!.text, 'Игры 3×3');
  });
}
