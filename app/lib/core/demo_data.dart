// Пример данных для демо-режима: команда с игроками, тренировками, матчами, статистикой и тестами ОФП.
// Нужен, чтобы сразу увидеть дашборды, профиль игрока и отчёт о прогрессе.

import 'dart:math' as math;

import '../data/models.dart';
import '../data/repo.dart';

const _squad = [
  ('Артём', 'Ковалёв', 'GK', 1),
  ('Даниил', 'Смирнов', 'GK', 12),
  ('Максим', 'Орлов', 'DF', 2),
  ('Илья', 'Петров', 'DF', 3),
  ('Кирилл', 'Волков', 'DF', 4),
  ('Егор', 'Зайцев', 'DF', 5),
  ('Тимур', 'Соколов', 'DF', 13),
  ('Иван', 'Морозов', 'MF', 6),
  ('Матвей', 'Новиков', 'MF', 8),
  ('Александр', 'Фёдоров', 'MF', 10),
  ('Михаил', 'Кузнецов', 'MF', 14),
  ('Роман', 'Попов', 'MF', 16),
  ('Глеб', 'Васильев', 'MF', 17),
  ('Дмитрий', 'Козлов', 'FW', 7),
  ('Лев', 'Степанов', 'FW', 9),
  ('Марк', 'Белов', 'FW', 11),
];

const _opponents = ['Зенит U16', 'Урал U16', 'Крылья Советов U16', 'Рубин U16', 'Спартак U16', 'Чертаново U16', 'Локомотив U16'];

/// Заполнить пример. Возвращает id созданной команды.
Future<String> seedDemoData(Repo repo, {DateTime? now}) async {
  final rnd = math.Random(16);
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  double r(double a, double b) => a + rnd.nextDouble() * (b - a);
  double round2(double v) => (v * 100).round() / 100;

  final team = Team(
    id: newId(),
    name: 'Амкар U16',
    ageGroup: 'U16',
    level: 'advanced',
    defaultPlayers: 18,
    fieldType: 'full',
    equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals', 'poles', 'ladder'],
  );
  await repo.put(Entities.teams, team);

  final players = <Player>[];
  for (final (first, last, pos, n) in _squad) {
    final p = Player(id: newId(), teamId: team.id, firstName: first, lastName: last, position: pos, number: n, birthYear: today.year - 16);
    players.add(p);
    await repo.put(Entities.players, p);
  }

  // Расписание: пн, ср, пт 16:00–18:00 весь сезон.
  await repo.put(
    Entities.slots,
    ScheduleSlot(id: newId(), teamId: team.id, title: 'Тренировка Амкар U16', weekdays: const [1, 3, 5], startTime: '16:00', durationMin: 120, location: 'Стадион «Звезда»'),
  );

  // Проведённые тренировки за 10 недель (пн и ср) с посещаемостью и нагрузкой.
  const blocksTemplate = [
    ('warmup', 'Разминка с мячом', 15, 'warmup'),
    ('main', 'Рондо 5×2', 20, 'possession'),
    ('main', 'Завершение атаки 2×1', 25, 'finishing'),
    ('game', 'Игра 8×8 на 4 ворот', 25, 'game'),
    ('main', 'Скоростно-силовая работа', 15, 'physical'),
    ('cooldown', 'Заминка и растяжка', 10, 'cooldown'),
  ];
  var monday = day.subtract(Duration(days: day.weekday - 1 + 7 * 10));
  var k = 0;
  while (monday.isBefore(day)) {
    for (final offset in [0, 2]) {
      final at = monday.add(Duration(days: offset, hours: 16));
      if (!at.isBefore(day)) continue;
      k++;
      final s = TrainingSession(
        id: newId(),
        teamId: team.id,
        title: k.isEven ? 'Владение и завершение' : 'Переходы и прессинг',
        goal: k.isEven ? 'Удержание мяча и удары' : 'Быстрый переход в атаку',
        durationMin: 110,
        playersExpected: 16,
        status: 'done',
        scheduledAt: at,
        startedAt: at,
        finishedAt: at.add(const Duration(minutes: 110)),
        blocks: [
          for (final (phase, title, min, cat) in blocksTemplate)
            TrainingBlock(id: newId(), phase: phase, title: title, durationMin: min, drill: {'category': cat, 'title': title}),
        ],
      );
      await repo.put(Entities.sessions, s);
      for (final p in players) {
        final roll = rnd.nextDouble();
        final status = roll < 0.84 ? 'present' : (roll < 0.9 ? 'late' : (roll < 0.95 ? 'excused' : 'absent'));
        await repo.put(Entities.attendance, Attendance(id: attendanceId(s.id, p.id), sessionId: s.id, playerId: p.id, status: status));
      }
      await repo.put(
        Entities.reports,
        SessionReport(
          id: newId(),
          sessionId: s.id,
          rating: 3 + rnd.nextInt(3),
          rpe: 5 + rnd.nextInt(4),
          wentWell: 'Быстро переходили в атаку после отбора',
          toImprove: 'Первое касание под давлением',
          coachConfirmed: true,
          confirmedAt: at.add(const Duration(hours: 3)),
        ),
      );
    }
    monday = monday.add(const Duration(days: 7));
  }

  // Матчи: 5 сыграно, 2 впереди. Статистика по игрокам.
  for (var i = 0; i < _opponents.length; i++) {
    final played = i < 5;
    final at = played ? day.subtract(Duration(days: 7 * (5 - i) - 6, hours: -12)) : day.add(Duration(days: 7 * (i - 4) - 1, hours: 12));
    final m = Match(
      id: newId(),
      teamId: team.id,
      opponent: _opponents[i],
      startsAt: at,
      durationMin: 80,
      home: i.isEven,
      venue: i.isEven ? 'Стадион «Звезда»' : '',
      competition: 'Первенство России U16',
      status: played ? 'played' : 'scheduled',
    );
    if (!played) {
      await repo.put(Entities.matches, m);
      continue;
    }
    var goalsFor = 0, goalsAgainst = rnd.nextInt(3);
    // Схема 4-4-2: вратарь, 4 защитника, 4 полузащитника, 2 нападающих; остальные — замены.
    List<Player> pos(String p, int n) => players.where((x) => x.position == p).take(n).toList();
    final lineup = [...pos('GK', 1), ...pos('DF', 4), ...pos('MF', 4), ...pos('FW', 2)];
    final bench = players.where((p) => p.position != 'GK' && !lineup.contains(p)).take(3).toList();
    for (final p in [...lineup, ...bench]) {
      final starter = lineup.contains(p);
      final fw = p.position == 'FW', mf = p.position == 'MF', gk = p.position == 'GK';
      final goals = gk ? 0 : (rnd.nextDouble() < (fw ? 0.45 : (mf ? 0.18 : 0.05)) ? 1 : 0);
      goalsFor += goals;
      final passes = (gk ? r(15, 25) : r(18, 45)).round().toDouble();
      final stats = {
        'goals': goals.toDouble(),
        'assists': !gk && rnd.nextDouble() < (mf ? 0.3 : 0.15) ? 1.0 : 0.0,
        'shots': gk ? 0.0 : (fw ? r(1, 5) : r(0, 2)).roundToDouble(),
        'passes': passes,
        'passes_ok': (passes * r(0.7, 0.9)).roundToDouble(),
        'tackles': gk ? 0.0 : (p.position == 'DF' ? r(2, 6) : r(0, 3)).roundToDouble(),
        'interceptions': gk ? 0.0 : r(0, 4).roundToDouble(),
        'yellow': rnd.nextDouble() < 0.08 ? 1.0 : 0.0,
        if (gk) 'saves': r(2, 7).roundToDouble(),
        if (gk) 'conceded': goalsAgainst.toDouble(),
      };
      stats['shots_on'] = math.min(stats['shots']!, (stats['shots']! * r(0.3, 0.7)).roundToDouble() + stats['goals']!);
      await repo.put(
        Entities.matchStats,
        MatchStat(
          id: matchStatId(m.id, p.id),
          matchId: m.id,
          playerId: p.id,
          started: starter,
          minutes: starter ? 80 : (15 + rnd.nextInt(20)),
          rating: round2(r(6.0, 8.2) + goals * 0.6),
          stats: stats,
        ),
      );
    }
    await repo.put(Entities.matches, Match.fromJson(m.id, m.toJson()..['score_for'] = goalsFor..['score_against'] = goalsAgainst));
  }

  // Тесты ОФП: три тестирования с ростом результатов.
  for (final p in players) {
    final talent = r(-0.08, 0.08);
    for (final (weeksAgo, gain) in [(12, 0.0), (6, 0.025), (0, 0.05)]) {
      final f = 1 + gain + r(-0.01, 0.01);
      await repo.put(
        Entities.physicalTests,
        PhysicalTest(
          id: newId(),
          playerId: p.id,
          testedOn: day.subtract(Duration(days: 7 * weeksAgo + 1)),
          results: {
            'sprint_10m': round2(1.92 * (1 + talent) / f),
            'sprint_30m': round2(4.75 * (1 + talent) / f),
            'shuttle_3x10': round2(7.95 * (1 + talent) / f),
            'long_jump': (215 * (1 - talent) * f).roundToDouble(),
            'yoyo': ((1500 * (1 - talent * 2) * (1 + gain * 2.5)) / 40).round() * 40.0,
            'flexibility': (6 + talent * -40 + gain * 40).roundToDouble(),
            'height': (172 + r(-6, 10)).roundToDouble(),
            'weight': (61 + r(-5, 8)).roundToDouble(),
          },
        ),
      );
    }
  }

  // Оценки тренера: 3 месяца назад и сейчас.
  for (final p in players) {
    for (final skill in Skills.all.keys) {
      final base = 2 + rnd.nextInt(3);
      await repo.put(
        Entities.assessments,
        PlayerAssessment(id: newId(), playerId: p.id, skill: skill, score: base, assessedAt: day.subtract(const Duration(days: 95))),
      );
      await repo.put(
        Entities.assessments,
        PlayerAssessment(
          id: newId(),
          playerId: p.id,
          skill: skill,
          score: math.min(5, base + (rnd.nextDouble() < 0.55 ? 1 : 0)),
          assessedAt: day.subtract(const Duration(days: 3)),
        ),
      );
    }
  }

  // Программа развития и сообщение родителям для нападающего.
  final fw = players.firstWhere((p) => p.lastName == 'Степанов');
  await repo.put(
    Entities.devPlans,
    DevelopmentPlan(
      id: newId(),
      playerId: fw.id,
      period: 'cycle6',
      title: 'Скорость и завершение',
      startsOn: day.subtract(Duration(days: day.weekday - 1 + 14)),
      endsOn: day.subtract(Duration(days: day.weekday - 1 + 14)).add(const Duration(days: 41)),
      keyGoal: 'Быстрее открываться за спину защитникам и чаще бить в створ',
      focus: const ['finishing', 'physical'],
      targets: const [
        PlanTarget(name: 'Бег 10 м', current: 1.86, target: 1.78, unit: 'с', measure: 'С места, лучшая из 2 попыток', priority: 'high'),
        PlanTarget(name: 'Удары в створ', current: 48, target: 60, unit: '%', measure: 'Статистика матчей за цикл', priority: 'high'),
        PlanTarget(name: 'Прыжок в длину с места', current: 218, target: 228, unit: 'см', priority: 'medium'),
      ],
      items: const [
        PlanItem(text: 'Завершение после рывка — 3 раза в неделю', kind: 'task', done: true),
        PlanItem(text: '100 ударов слабой ногой в неделю', kind: 'task'),
        PlanItem(text: 'Стартовая скорость: 6×10 м после тренировки', kind: 'task', done: true),
        PlanItem(text: 'Уверенный удар левой с ходу', kind: 'goal'),
      ],
      comment: 'Хорошо читает момент для открывания — добавляем скорость и точность удара.',
    ),
  );
  await repo.put(
    Entities.parentNotes,
    ParentNote(
      id: newId(),
      playerId: fw.id,
      category: 'nutrition',
      text: 'Перед игрой — завтрак за 2–3 часа, больше воды в день матча. Сон не меньше 9 часов.',
      writtenAt: day.subtract(const Duration(days: 2)),
    ),
  );

  await repo.put(Entities.staff, StaffMember(id: newId(), name: 'Сергей Ильин', role: 'assistant', teamIds: [team.id]));
  await repo.put(Entities.staff, StaffMember(id: newId(), name: 'Олег Ткачёв', role: 'fitness', teamIds: [team.id]));
  await repo.put(Entities.staff, StaffMember(id: newId(), name: 'Виктор Лапин', role: 'goalkeeper', teamIds: [team.id]));
  return team.id;
}
