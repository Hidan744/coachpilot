import 'dart:typed_data';

import 'package:coachpilot/core/demo_data.dart';
import 'package:coachpilot/core/export/excel_report.dart';
import 'package:coachpilot/core/export/file_name.dart';
import 'package:coachpilot/core/file_import.dart';
import 'package:coachpilot/core/performance.dart';
import 'package:coachpilot/core/recommendations.dart';
import 'package:coachpilot/core/stats_import.dart';
import 'package:coachpilot/data/db.dart';
import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/data/repo.dart';
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

Player pl(String id, String last, {String? pos, int? n, int? year}) =>
    Player(id: id, teamId: 't', firstName: 'И', lastName: last, position: pos, number: n, birthYear: year);

MatchStat st(String m, String p, {int minutes = 90, double? rating, Map<String, double> s = const {}, bool started = true}) =>
    MatchStat(id: '$m$p', matchId: m, playerId: p, minutes: minutes, rating: rating, stats: s, started: started);

void main() {
  group('статистика сезона', () {
    test('итоги, точность, за 90 минут, сухие матчи', () {
      final s = SeasonStats('p', [
        st('m1', 'p', rating: 7, s: {'goals': 2, 'shots': 4, 'shots_on': 3, 'passes': 40, 'passes_ok': 32}),
        st('m2', 'p', minutes: 45, rating: 6, s: {'assists': 1, 'shots': 1}, started: false),
        st('m3', 'p', minutes: 0),
      ]);
      expect(s.games, 2);
      expect(s.starts, 1);
      expect(s.minutes, 135);
      expect(s['goals'], 2);
      expect(s.goalContributions, 3);
      expect(s.avgRating, 6.5);
      expect(s.passAccuracy, 80);
      expect(s.shotAccuracy, 60);
      expect(s.per90('goals'), closeTo(1.333, 0.01));

      final gk = SeasonStats('g', [
        st('m1', 'g', s: {'saves': 4}),
        st('m2', 'g', s: {'saves': 2, 'conceded': 1}),
      ]);
      expect(gk.cleanSheets, 1);
    });
  });

  group('ОФП', () {
    test('баллы по возрастным нормам: для бега меньше — лучше', () {
      final sprint = physicalMetrics.firstWhere((m) => m.key == 'sprint_10m');
      expect(sprint.score(1.70, 16), 100);
      expect(sprint.score(2.00, 16), 0);
      expect(sprint.score(1.85, 16), 50);
      // для 10-летнего тот же результат — выше балл
      expect(sprint.score(2.00, 10), greaterThan(sprint.score(2.00, 16)));
      expect(sprint.change(1.90, 1.80), closeTo(5.26, 0.01));
      final jump = physicalMetrics.firstWhere((m) => m.key == 'long_jump');
      expect(jump.change(200, 210), 5);
      expect(jump.score(300, 16), 100);
    });

    test('общий балл — по сданным тестам', () {
      final t = PhysicalTest(id: 't', playerId: 'p', testedOn: DateTime(2026, 10, 1), results: {'sprint_10m': 1.85, 'long_jump': 250, 'height': 180});
      expect(physicalScores(t, 16).keys, {'sprint_10m', 'long_jump'});
      expect(physicalOverall(t, 16), 75);
    });
  });

  group('оценки и сводка', () {
    test('категории, сильные стороны и зоны роста', () {
      final skills = {'technique': 5, 'passing': 4, 'dribbling': 3, 'finishing': 4, 'positioning': 2, 'decision': 3, 'attitude': 5};
      final c = categoryScores(skills);
      expect(c['Техника'], 80);
      expect(c['Тактика'], 50);
      expect(c['Физика'], isNull);
      expect(c['Ментальная'], 100);
      expect(overallScore(c, null), 77);
      final (strong, weak) = strengthsAndGaps(skills);
      expect(strong, ['technique', 'attitude', 'passing']);
      expect(weak.first, 'positioning');
    });

    test('сводка игрока: было → стало за период', () {
      final now = DateTime(2026, 10, 20);
      final p = pl('p', 'Иванов', pos: 'FW', year: 2010);
      final snap = PlayerSnapshot(
        player: p,
        now: now,
        assessments: [
          PlayerAssessment(id: '1', playerId: 'p', skill: 'technique', score: 3, assessedAt: DateTime(2026, 6, 1)),
          PlayerAssessment(id: '2', playerId: 'p', skill: 'technique', score: 4, assessedAt: DateTime(2026, 10, 10)),
          PlayerAssessment(id: '3', playerId: 'x', skill: 'technique', score: 1, assessedAt: DateTime(2026, 10, 10)),
        ],
        tests: [
          PhysicalTest(id: 'a', playerId: 'p', testedOn: DateTime(2026, 6, 1), results: {'sprint_10m': 1.95}),
          PhysicalTest(id: 'b', playerId: 'p', testedOn: DateTime(2026, 10, 1), results: {'sprint_10m': 1.80}),
        ],
        attendance: [
          Attendance(id: '1', sessionId: 's1', playerId: 'p', status: 'present'),
          Attendance(id: '2', sessionId: 's2', playerId: 'p', status: 'absent'),
          Attendance(id: '3', sessionId: 's3', playerId: 'p', status: 'excused'),
        ],
        sessions: {
          's1': TrainingSession(id: 's1', title: 'a', durationMin: 60, startedAt: DateTime(2026, 10, 13)),
          's2': TrainingSession(id: 's2', title: 'b', durationMin: 60, startedAt: DateTime(2026, 10, 14)),
        },
        stats: [st('m', 'p', s: {'goals': 1})],
      );
      expect(snap.age, 16);
      expect(snap.skillsBefore['technique'], 3);
      expect(snap.skillsNow['technique'], 4);
      expect(snap.categoriesBefore['Техника'], 60);
      expect(snap.categoriesNow['Техника'], 80);
      expect(snap.physicalNow, greaterThan(snap.physicalBefore!));
      expect(snap.overallDelta, greaterThan(0));
      expect(snap.attendancePct, 50);
      expect(snap.weeks[snap.weeks.length - 2].$2, 0.5); // занятия на прошлой неделе
      expect(snap.season['goals'], 1);
    });

    test('нагрузка sRPE и структура по направлениям', () {
      final s = TrainingSession(
        id: 's',
        title: 't',
        durationMin: 90,
        actual: const {'b1': 1800, 'b2': 1800, 'skipped': []},
        blocks: const [
          TrainingBlock(id: 'b1', phase: 'warmup', title: 'Разминка', durationMin: 15),
          TrainingBlock(id: 'b2', phase: 'main', title: 'Рондо', durationMin: 30, drill: {'category': 'possession'}),
          TrainingBlock(id: 'b3', phase: 'main', title: 'Рывки', durationMin: 15, drill: {'category': 'physical'}),
        ],
      );
      expect(sessionLoad(s, SessionReport(id: 'r', sessionId: 's', rpe: 6)), 360);
      expect(sessionLoad(s, SessionReport(id: 'r', sessionId: 's')), isNull);
      final structure = loadStructure([s]);
      expect(structure['Тактика'], 30);
      expect(structure['ОФП'], 15);
      expect(structure['Разминка и восстановление'], 15);
    });
  });

  group('импорт статистики', () {
    final players = [pl('1', 'Иванов', n: 9), pl('2', 'Петров', n: 5), pl('3', 'Сидоров', pos: 'GK', n: 1)];

    test('таблица с заголовком: игроки по фамилии, показатели по названиям колонок', () {
      final rows = [
        ['Матч с Зенитом'],
        ['№', 'Игрок', 'Мин', 'Голы', 'Голевые передачи', 'Удары', 'Удары в створ', 'Точные передачи', 'Передачи', 'ЖК', 'Оценка'],
        ['9', 'Иванов Иван', '90', '2', '0', '5', '3', '20', '25', '1', '7,5'],
        ['5', 'Петров', '', '', '1', '', '', '30', '35', '', ''],
        ['7', 'Неизвестный', '90', '1', '', '', '', '', '', '', ''],
      ];
      final r = parseStatsTable(rows, players);
      expect(r.length, 2);
      final iv = r.firstWhere((x) => x.player.id == '1');
      expect(iv.minutes, 90);
      expect(iv.stats['goals'], 2);
      expect(iv.stats['shots_on'], 3);
      expect(iv.stats['passes_ok'], 20);
      expect(iv.stats['passes'], 25);
      expect(iv.stats['yellow'], 1);
      expect(iv.rating, 7.5);
      final pt = r.firstWhere((x) => x.player.id == '2');
      expect(pt.stats['assists'], 1);
      expect(pt.minutes, 90); // минут нет, но есть показатели — считаем полный матч
    });
  });

  test('пример данных для демо и выгрузка Excel', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = Repo(db);
    final now = DateTime(2026, 10, 20);
    final mainId = await db.transaction(() => seedDemoData(repo, now: now));
    // Две команды: основной состав (взрослые) и академия U16.
    final teams = await repo.list(Entities.teams, Team.fromJson);
    expect(teams.map((t) => t.name), containsAll(['Основной состав', 'Академия U16']));
    expect(teams.firstWhere((t) => t.id == mainId).ageGroup, 'adult');
    final teamId = teams.firstWhere((t) => t.name == 'Академия U16').id;
    final players = await repo.list(Entities.players, Player.fromJson, parentId: teamId);
    expect(players.length, 16);
    expect((await repo.list(Entities.players, Player.fromJson, parentId: mainId)).length, 16);
    final stats = await repo.list(Entities.matchStats, MatchStat.fromJson);
    final tests = await repo.list(Entities.physicalTests, PhysicalTest.fromJson);
    final sessions = await repo.list(Entities.sessions, TrainingSession.fromJson);
    expect(stats, isNotEmpty);
    expect(tests.length, 96);
    expect(sessions.length, greaterThanOrEqualTo(19));

    // Сводка по игроку: есть «было» и «стало», ОФП растёт.
    final fw = players.firstWhere((p) => p.lastName == 'Степанов');
    final snap = PlayerSnapshot(
      player: fw,
      now: now,
      assessments: await repo.list(Entities.assessments, PlayerAssessment.fromJson),
      tests: tests,
      attendance: await repo.list(Entities.attendance, Attendance.fromJson),
      sessions: {for (final s in sessions) s.id: s},
      stats: stats,
    );
    expect(snap.overallNow, isNotNull);
    expect(snap.physicalNow, greaterThanOrEqualTo(snap.physicalBefore!));
    expect(snap.season.games, 8);
    // Профессиональные показатели: дистанция, спринты, скорость (максимум, а не сумма), единоборства.
    expect(snap.season['distance'], greaterThan(30));
    expect(snap.season['top_speed'], inInclusiveRange(24, 33));
    expect(snap.season.duelRate, isNotNull);
    // Игровой профиль относительно команды и выводы.
    final squad = seasonStats(stats);
    final profile = gameProfile(snap.season, squad.values);
    expect(profile['Атака'], inInclusiveRange(0, 100));
    expect(profile.values.whereType<int>().length, gameAxes.length);
    expect(snap.attendancePct, greaterThan(70));

    final team = teams.firstWhere((t) => t.id == teamId);
    final bytes = buildExcelReport(ExcelReportData(
      team: team,
      players: players,
      sessions: sessions,
      attendance: await repo.list(Entities.attendance, Attendance.fromJson),
      reports: await repo.list(Entities.reports, SessionReport.fromJson),
      matches: await repo.list(Entities.matches, Match.fromJson),
      stats: stats,
      tests: tests,
      assessments: await repo.list(Entities.assessments, PlayerAssessment.fromJson),
      staff: await repo.list(Entities.staff, StaffMember.fromJson),
    ));
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Игроки', 'Посещаемость', 'Тренировки', 'Статистика матчей', 'Итоги сезона', 'ОФП', 'Матчи', 'Штаб']));
    expect(book.tables['Игроки']!.maxRows, 17);
    expect(book.tables['ОФП']!.maxRows, 49);
    final header = book.tables['Игроки']!.rows.first.map((c) => c?.value.toString()).toList();
    expect(header, contains('Посещаемость, %'));
  });

  test('имя файла латиницей', () {
    expect(safeFileName('Отчёт Лев Степанов 20.10.2026.pdf'), 'Otchet_Lev_Stepanov_20.10.2026.pdf');
    expect(safeFileName('Отчёт Амкар U16 (сезон).xlsx'), 'Otchet_Amkar_U16_sezon.xlsx');
  });

  test('демо-история для своей команды без позиций', () async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = Repo(db);
    final team = Team(id: newId(), name: 'Моя команда', ageGroup: 'U12', level: 'beginner', defaultPlayers: 12, fieldType: 'half');
    await repo.put(Entities.teams, team);
    final players = [
      for (var i = 0; i < 9; i++) Player(id: newId(), teamId: team.id, firstName: 'Игрок$i', lastName: ''),
    ];
    for (final p in players) {
      await repo.put(Entities.players, p);
    }
    await db.transaction(() => seedTeamHistory(repo, team, players, now: DateTime(2026, 10, 20)));
    final stats = await repo.list(Entities.matchStats, MatchStat.fromJson);
    final matches = await repo.list(Entities.matches, Match.fromJson);
    expect(matches.where((m) => m.status == 'played').length, 8);
    expect(matches.first.opponent, endsWith('U12'));
    // Все 9 игроков сыграли: состав добран без позиций.
    expect(seasonStats(stats).length, 9);
    expect(await repo.list(Entities.devPlans, DevelopmentPlan.fromJson), isNotEmpty);
  });

  test('шаблон статистики: заполнить в Excel и загрузить обратно', () {
    final players = [
      Player(id: 'a', teamId: 't', firstName: 'Иван', lastName: 'Петров', position: 'MF', number: 8),
      Player(id: 'b', teamId: 't', firstName: 'Олег', lastName: 'Сидоров', position: 'DF', number: 4),
    ];
    final book = Excel.decodeBytes(buildStatsTemplate(players));
    final sheet = book.tables.values.first;
    final head = [for (final c in sheet.rows.first) c?.value.toString() ?? ''];
    expect(head, statsTemplateHeader());
    // Заполняем строку Петрова: минуты, единоборства, выигранные, дистанция с запятой, скорость.
    final row = sheet.rows.indexWhere((r) => r.first?.value.toString() == 'Иван Петров');
    void put(String col, String v) =>
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: head.indexOf(col), rowIndex: row), TextCellValue(v));
    put('Минуты', '75');
    put('Единоборства', '12');
    put('Выигранные единоборства', '7');
    put('Дистанция, км', '9,4');
    put('Макс. скорость, км/ч', '29.5');
    put('Подборы', '6');
    final rows = readTable('s.xlsx', Uint8List.fromList(book.encode()!));
    final r = parseStatsTable(rows, players).single;
    expect(r.player.id, 'a');
    expect(r.minutes, 75);
    expect(r.stats['duels'], 12);
    expect(r.stats['duels_won'], 7);
    expect(r.stats['distance'], 9.4);
    expect(r.stats['top_speed'], 29.5);
    expect(r.stats['recoveries'], 6);
  });

  test('рекомендации: интенсивность по нагрузке и подводка к матчу', () {
    final now = DateTime(2026, 10, 21, 12);
    final team = Team(id: 't', name: 'Основа', ageGroup: 'adult', level: 'pro', defaultPlayers: 20);
    TrainingSession s(int daysAgo) => TrainingSession(
          id: 's$daysAgo',
          teamId: 't',
          title: 'x',
          durationMin: 90,
          status: 'done',
          startedAt: now.subtract(Duration(days: daysAgo)),
        );
    // Последняя неделя — 3 занятия с RPE 9, месяц до неё — по 1 занятию в неделю с RPE 5.
    final sessions = [s(1), s(3), s(5), s(9), s(16), s(23), s(30)];
    final reports = {
      for (final x in sessions)
        x.id: SessionReport(id: 'r${x.id}', sessionId: x.id, rpe: int.parse(x.id.substring(1)) < 7 ? 9 : 5),
    };
    final match = Match(id: 'm', teamId: 't', opponent: 'Урал', startsAt: now.add(const Duration(days: 1)));
    final advice = teamAdvice(team: team, sessions: sessions, reports: reports, matches: [match], now: now);
    expect(advice.map((a) => a.title), containsAll(['Снизить интенсивность', 'Игроки устали', 'Подводка к матчу']));
    // Взрослой команде нет детских ограничений.
    expect(advice.where((a) => a.title.startsWith('Возраст')), isEmpty);
  });
}
