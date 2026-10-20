// Пример данных для демо-режима: команда с игроками, тренировками, матчами, статистикой и тестами ОФП.
// Нужен, чтобы сразу увидеть дашборды, профиль игрока и отчёт о прогрессе.

import 'dart:math' as math;

import '../data/models.dart';
import '../data/repo.dart';
import 'tactics.dart';

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

/// Основной состав: взрослые игроки, профессиональный уровень.
const _proSquad = [
  ('Антон', 'Широков', 'GK', 1, 29),
  ('Илья', 'Лантратов', 'GK', 35, 24),
  ('Сергей', 'Багров', 'DF', 2, 27),
  ('Павел', 'Ивашин', 'DF', 4, 30),
  ('Никита', 'Чернов', 'DF', 5, 26),
  ('Даниил', 'Круглов', 'DF', 3, 23),
  ('Артур', 'Гараев', 'DF', 15, 25),
  ('Алексей', 'Миронов', 'MF', 6, 28),
  ('Владислав', 'Сафонов', 'MF', 8, 24),
  ('Константин', 'Рябов', 'MF', 10, 27),
  ('Егор', 'Тарасов', 'MF', 14, 22),
  ('Максим', 'Глушков', 'MF', 17, 25),
  ('Тимофей', 'Орехов', 'MF', 18, 21),
  ('Андрей', 'Комаров', 'FW', 7, 26),
  ('Денис', 'Шустов', 'FW', 9, 28),
  ('Роман', 'Еремеев', 'FW', 11, 23),
];

const _opponents = [
  'Зенит',
  'Урал',
  'Крылья Советов',
  'Рубин',
  'Спартак',
  'Чертаново',
  'Локомотив',
  'Динамо',
  'ЦСКА',
  'Краснодар',
];
const _played = 8;

/// Заполнить пример: основной состав (взрослые, профессиональный уровень) и академия U16.
/// Возвращает id основного состава.
Future<String> seedDemoData(Repo repo, {DateTime? now}) async {
  final today = now ?? DateTime.now();

  final main = Team(
    id: newId(),
    name: 'Основной состав',
    ageGroup: 'adult',
    level: 'pro',
    defaultPlayers: 22,
    fieldType: 'full',
    equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals', 'poles', 'ladder'],
  );
  await repo.put(Entities.teams, main);
  final pros = <Player>[];
  for (final (first, last, pos, n, age) in _proSquad) {
    final p = Player(
      id: newId(),
      teamId: main.id,
      firstName: first,
      lastName: last,
      position: pos,
      number: n,
      birthYear: today.year - age,
    );
    pros.add(p);
    await repo.put(Entities.players, p);
  }
  // Основа тренируется с 16:00, академия — с 10:00.
  await seedTeamHistory(repo, main, pros, now: now, seed: 7, startHour: 16);

  final team = Team(
    id: newId(),
    name: 'Академия U16',
    ageGroup: 'U16',
    level: 'advanced',
    defaultPlayers: 18,
    fieldType: 'full',
    equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals', 'poles', 'ladder'],
  );
  await repo.put(Entities.teams, team);

  final players = <Player>[];
  for (final (first, last, pos, n) in _squad) {
    final p = Player(
      id: newId(),
      teamId: team.id,
      firstName: first,
      lastName: last,
      position: pos,
      number: n,
      birthYear: today.year - 16,
    );
    players.add(p);
    await repo.put(Entities.players, p);
  }

  await seedTeamHistory(repo, team, players, now: now, startHour: 10);
  await repo.put(Entities.staff, StaffMember(id: newId(), name: 'Михаил Громов', role: 'head', teamIds: [main.id]));
  await repo.put(
    Entities.staff,
    StaffMember(id: newId(), name: 'Сергей Ильин', role: 'assistant', teamIds: [main.id, team.id]),
  );
  await repo.put(
    Entities.staff,
    StaffMember(id: newId(), name: 'Олег Ткачёв', role: 'fitness', teamIds: [main.id, team.id]),
  );
  await repo.put(
    Entities.staff,
    StaffMember(id: newId(), name: 'Виктор Лапин', role: 'goalkeeper', teamIds: [main.id, team.id]),
  );
  await repo.put(Entities.staff, StaffMember(id: newId(), name: 'Анна Белова', role: 'analyst', teamIds: [main.id]));
  return main.id;
}

/// Демо-история для команды и её игроков: расписание, тренировки с посещаемостью и нагрузкой,
/// матчи со статистикой, тесты ОФП, оценки навыков, программы развития и сообщения родителям.
/// Работает и для своей команды в демо — чтобы сразу увидеть всю аналитику на своих игроках.
Future<void> seedTeamHistory(
  Repo repo,
  Team team,
  List<Player> players, {
  DateTime? now,
  int seed = 16,
  int startHour = 16,
}) async {
  if (players.isEmpty) return;
  final rnd = math.Random(seed);
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  double r(double a, double b) => a + rnd.nextDouble() * (b - a);
  double round2(double v) => (v * 100).round() / 100;
  final adult = team.ageGroup == 'adult';
  final hh = startHour.toString().padLeft(2, '0');
  // Расписание: пн, ср, пт по 2 часа весь сезон.
  await repo.put(
    Entities.slots,
    ScheduleSlot(
      id: newId(),
      teamId: team.id,
      title: 'Тренировка ${team.name}',
      weekdays: const [1, 3, 5],
      startTime: '$hh:00',
      durationMin: 120,
      location: 'Стадион «Звезда»',
    ),
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
      final at = monday.add(Duration(days: offset, hours: startHour));
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
            TrainingBlock(
              id: newId(),
              phase: phase,
              title: title,
              durationMin: min,
              drill: {'category': cat, 'title': title},
            ),
        ],
      );
      await repo.put(Entities.sessions, s);
      for (final p in players) {
        final roll = rnd.nextDouble();
        final status = roll < 0.84 ? 'present' : (roll < 0.9 ? 'late' : (roll < 0.95 ? 'excused' : 'absent'));
        await repo.put(
          Entities.attendance,
          Attendance(id: attendanceId(s.id, p.id), sessionId: s.id, playerId: p.id, status: status),
        );
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

  // Игровой стиль каждого игрока — чтобы профили отличались: кто-то дриблёр, кто-то диспетчер или «мотор».
  final style = {
    for (final p in players)
      p.id: (dribble: r(0.5, 1.6), pass: r(0.85, 1.1), defend: r(0.6, 1.5), run: r(0.85, 1.15), finish: r(0.6, 1.5)),
  };

  // Матчи: 8 сыграно, 2 впереди. Статистика по игрокам — как в профессиональной аналитике.
  for (var i = 0; i < _opponents.length; i++) {
    final played = i < _played;
    final at = played
        ? day.subtract(Duration(days: 7 * (_played - i) - 6, hours: -12))
        : day.add(Duration(days: 7 * (i - _played + 1) - 1, hours: 12));
    final m = Match(
      id: newId(),
      teamId: team.id,
      opponent: adult ? _opponents[i] : '${_opponents[i]} ${team.ageGroup}',
      startsAt: at,
      durationMin: 80,
      home: i.isEven,
      venue: i.isEven ? 'Стадион «Звезда»' : '',
      competition: adult ? 'Первая лига' : 'Первенство России ${team.ageGroup}',
      status: played ? 'played' : 'scheduled',
    );
    if (!played) {
      await repo.put(Entities.matches, m);
      // Тактика на ближайший матч: наш состав 4-4-2 против 4-3-3 соперника.
      if (i == _played) {
        await repo.put(
          Entities.boards,
          TacticBoard(
            id: newId(),
            teamId: team.id,
            matchId: m.id,
            title: 'Матч: ${m.opponent}',
            formation: '4-4-2',
            scheme: Scheme(
              field: 'full_v',
              items: [
                ...formationItems('4-4-2', lineup: assignLineup('4-4-2', players)),
                ...formationItems('4-3-3', opponent: true),
              ],
            ),
            notes: 'Высокий прессинг первые 15 минут, атаки через фланги.',
          ),
        );
      }
      continue;
    }
    var goalsFor = 0, goalsAgainst = rnd.nextInt(3);
    // Схема 4-4-2: вратарь, 4 защитника, 4 полузащитника, 2 нападающих; остальные — замены.
    // У своей команды позиции могут быть не указаны — тогда добираем состав любыми игроками.
    List<Player> pos(String p, int n) => players.where((x) => x.position == p).take(n).toList();
    final lineup = [...pos('GK', 1), ...pos('DF', 4), ...pos('MF', 4), ...pos('FW', 2)];
    for (final p in players) {
      if (lineup.length >= 11) break;
      if (!lineup.contains(p) && !(p.position == 'GK' && lineup.any((x) => x.position == 'GK'))) lineup.add(p);
    }
    // На скамейке ротация: разные игроки выходят на замену.
    final rest = players.where((p) => p.position != 'GK' && !lineup.contains(p)).toList()..shuffle(rnd);
    final bench = rest.take(4).toList();
    for (final p in [...lineup, ...bench]) {
      final starter = lineup.contains(p);
      final gk = p.position == 'GK';
      final fw = p.position == 'FW',
          mf = p.position == 'MF' || !['GK', 'DF', 'FW'].contains(p.position),
          df = p.position == 'DF';
      final st = style[p.id]!;
      final minutes = starter ? (rnd.nextDouble() < 0.2 ? 60 + rnd.nextInt(15) : 80) : (15 + rnd.nextInt(20));
      final f = minutes / 80;
      int n(double a, double b) => (r(a, b) * f).round();
      final goals = gk ? 0 : (rnd.nextDouble() < (fw ? 0.45 : (mf ? 0.18 : 0.05)) * st.finish * f ? 1 : 0);
      goalsFor += goals;
      final passes = (gk ? r(15, 25) : r(18, 45) * f).round().toDouble();
      final duels = gk ? 0 : n(df ? 8 : 5, df ? 15 : 12);
      final stats = <String, double>{
        'goals': goals.toDouble(),
        'assists': !gk && rnd.nextDouble() < (mf ? 0.3 : 0.15) * st.pass * f ? 1.0 : 0.0,
        'shots': gk ? 0.0 : ((fw ? r(1, 5) : r(0, 2)) * st.finish * f).roundToDouble(),
        'passes': passes,
        'passes_ok': (passes * (r(0.68, 0.86) * st.pass).clamp(0.5, 0.95)).roundToDouble(),
        'key_passes': gk ? 0.0 : ((mf ? r(0, 3) : r(0, 1.5)) * st.pass * f).roundToDouble(),
        'crosses': gk || !(df || mf) ? 0.0 : n(0, 3).toDouble(),
        'dribbles': gk ? 0.0 : ((fw || mf ? r(0, 4) : r(0, 1.5)) * st.dribble * f).roundToDouble(),
        'tackles': gk ? 0.0 : ((df ? r(2, 6) : r(0, 3)) * st.defend * f).roundToDouble(),
        'interceptions': gk ? 0.0 : ((df ? r(1, 4) : r(0, 2.5)) * st.defend * f).roundToDouble(),
        'recoveries': gk ? r(1, 4).roundToDouble() : ((df || mf ? r(3, 8) : r(1, 4)) * st.defend * f).roundToDouble(),
        'duels': duels.toDouble(),
        'duels_won': (duels * (r(0.38, 0.62) * (0.7 + st.defend * 0.25)).clamp(0.2, 0.85)).roundToDouble(),
        'losses': gk
            ? r(0, 2).roundToDouble()
            : ((fw ? r(6, 13) : (mf ? r(4, 10) : r(2, 7))) * f / st.pass).roundToDouble(),
        'fouls': gk ? 0.0 : n(0, 2.5).toDouble(),
        'distance': round2((gk ? r(4.2, 5.2) : (mf ? r(8.4, 10.6) : r(7.6, 9.6))) * st.run * f),
        'sprints': gk ? 0.0 : ((fw ? r(14, 26) : r(8, 20)) * st.run * f).roundToDouble(),
        'top_speed': double.parse(((gk ? r(21, 25) : r(25.5, 31)) * (0.95 + st.run * 0.05)).toStringAsFixed(1)),
        'yellow': rnd.nextDouble() < 0.08 ? 1.0 : 0.0,
        if (gk) 'saves': r(2, 7).roundToDouble(),
        if (gk) 'conceded': goalsAgainst.toDouble(),
      };
      stats['shots_on'] = math.min(stats['shots']!, (stats['shots']! * r(0.3, 0.7)).roundToDouble() + stats['goals']!);
      if (stats['shots']! < stats['shots_on']!) stats['shots'] = stats['shots_on']!;
      await repo.put(
        Entities.matchStats,
        MatchStat(
          id: matchStatId(m.id, p.id),
          matchId: m.id,
          playerId: p.id,
          started: starter,
          minutes: minutes,
          // Оценка следует из действий: голы, голевые, созидание, борьба, потери.
          rating: round2(
            (r(5.6, 6.6) +
                    goals * 0.9 +
                    stats['assists']! * 0.6 +
                    stats['key_passes']! * 0.15 +
                    stats['duels_won']! * 0.06 +
                    stats['dribbles']! * 0.08 +
                    (stats['saves'] ?? 0) * 0.12 -
                    stats['losses']! * 0.03)
                .clamp(4.5, 9.6),
          ),
          stats: stats,
        ),
      );
    }
    await repo.put(
      Entities.matches,
      Match.fromJson(
        m.id,
        m.toJson()
          ..['score_for'] = goalsFor
          ..['score_against'] = goalsAgainst,
      ),
    );
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
        PlayerAssessment(
          id: newId(),
          playerId: p.id,
          skill: skill,
          score: base,
          assessedAt: day.subtract(const Duration(days: 95)),
        ),
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
  final fw = players.firstWhere(
    (p) => p.lastName == 'Степанов',
    orElse: () => players.firstWhere((p) => p.position == 'FW', orElse: () => players.first),
  );
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
        PlanTarget(
          name: 'Бег 10 м',
          current: 1.86,
          target: 1.78,
          unit: 'с',
          measure: 'С места, лучшая из 2 попыток',
          priority: 'high',
        ),
        PlanTarget(
          name: 'Удары в створ',
          current: 48,
          target: 60,
          unit: '%',
          measure: 'Статистика матчей за цикл',
          priority: 'high',
        ),
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
  if (!adult) {
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
  }

  // Программа развития и сообщения родителям для остальных игроков — по позиции,
  // чтобы в демо у каждого профиля были заполнены все вкладки.
  final cycleStart = day.subtract(Duration(days: day.weekday - 1 + 7));
  const templates = {
    'GK': (
      'Игра на выходах и первый пас',
      'Увереннее играть на выходах и начинать атаку точным пасом',
      ['goalkeeping', 'passing'],
      [('Точность передач', 68.0, 78.0, '%'), ('Реакция: сейвы за матч', 3.0, 4.0, '')],
      [
        'Выходы на навесы — 2 раза в неделю',
        'Пас в одно касание после приёма — 50 повторений',
        'Командовать обороной голосом',
      ],
      'Надёжен на линии — добавляем игру ногами и выходы.',
    ),
    'DF': (
      'Отбор и выход из обороны',
      'Чаще выигрывать единоборства и не терять мяч при выходе из обороны',
      ['defending', 'passing'],
      [('Отборы за матч', 3.0, 4.0, ''), ('Точность передач', 74.0, 82.0, '%')],
      [
        'Игра 1×1 в обороне — 3 раза в неделю',
        'Длинная передача на фланг — 30 повторений',
        'Разбор своих единоборств по видео',
      ],
      'Хорошо читает игру — работаем над первым пасом после отбора.',
    ),
    'MF': (
      'Видение поля и передачи вперёд',
      'Чаще отдавать обостряющие передачи и успевать в оборону',
      ['passing', 'tactics', 'physical'],
      [('Точность передач', 78.0, 85.0, '%'), ('Челночный бег 3×10 м', 7.9, 7.6, 'с')],
      [
        'Осмотр перед приёмом мяча — каждое упражнение',
        'Передачи между линиями — 40 повторений',
        'Интервальный бег 6×200 м',
      ],
      'Связывает линии — добавляем остроту передач и выносливость.',
    ),
    'FW': (
      'Завершение и игра спиной',
      'Забивать больше из штрафной и держать мяч спиной к воротам',
      ['finishing', 'physical'],
      [('Удары в створ', 50.0, 60.0, '%'), ('Бег 10 м', 1.9, 1.82, 'с')],
      ['Удары после рывка — 3 раза в неделю', 'Игра спиной к воротам с защитником', 'Стартовая скорость: 6×10 м'],
      'Активен в штрафной — работаем над точностью и стартом.',
    ),
  };
  const parentNotes = [
    ('psychology', 'После неудачного эпизода быстро возвращается в игру — хвалите за это дома. Уверенность растёт.'),
    ('extra_training', 'Дома 2–3 раза в неделю: 15 минут жонглирования и работа слабой ногой о стенку.'),
    ('nutrition', 'В день тренировки — полноценный обед за 2–3 часа, бутылка воды с собой.'),
    ('general', 'Стал внимательнее на теоретических разборах, задаёт хорошие вопросы. Так держать!'),
  ];
  var pi = 0;
  for (final p in players) {
    if (p.id == fw.id) continue;
    final t = templates[p.position] ?? templates['MF']!;
    final shift = (pi % 3) * 0.04;
    await repo.put(
      Entities.devPlans,
      DevelopmentPlan(
        id: newId(),
        playerId: p.id,
        period: pi.isEven ? 'cycle4' : 'cycle6',
        title: t.$1,
        startsOn: cycleStart,
        endsOn: cycleStart.add(Duration(days: pi.isEven ? 27 : 41)),
        keyGoal: t.$2,
        focus: t.$3,
        targets: [
          for (final (i, (name, cur, target, unit)) in t.$4.indexed)
            PlanTarget(
              name: name,
              // Небольшой разброс, чтобы у игроков были разные текущие значения.
              current: round2(cur + (target - cur) * shift),
              target: target,
              unit: unit,
              priority: i == 0 ? 'high' : 'medium',
            ),
        ],
        items: [for (final (i, text) in t.$5.indexed) PlanItem(text: text, kind: 'task', done: i < 1 + pi % 2)],
        comment: t.$6,
      ),
    );
    // Сообщения родителям — только для юношеской команды.
    for (var n = 0; n < (adult ? 0 : 2); n++) {
      final (cat, text) = parentNotes[(pi + n) % parentNotes.length];
      await repo.put(
        Entities.parentNotes,
        ParentNote(
          id: newId(),
          playerId: p.id,
          category: cat,
          text: text,
          writtenAt: day.subtract(Duration(days: 3 + n * 9 + pi % 4)),
        ),
      );
    }
    pi++;
  }
}
