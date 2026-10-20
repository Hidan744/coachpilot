// Выгрузка отчётности в Excel: игроки, посещаемость, тренировки, статистика матчей, ОФП.

import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../performance.dart';

class ExcelReportData {
  ExcelReportData({
    required this.team,
    required this.players,
    required this.sessions,
    required this.attendance,
    required this.reports,
    required this.matches,
    required this.stats,
    required this.tests,
    required this.assessments,
    this.staff = const [],
  });

  final Team team;
  final List<Player> players;
  final List<TrainingSession> sessions;
  final List<Attendance> attendance;
  final List<SessionReport> reports;
  final List<Match> matches;
  final List<MatchStat> stats;
  final List<PhysicalTest> tests;
  final List<PlayerAssessment> assessments;
  final List<StaffMember> staff;
}

final _d = DateFormat('dd.MM.yyyy');

Uint8List buildExcelReport(ExcelReportData r) {
  final book = Excel.createExcel();
  final header = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.fromHexString('#E30613'),
    horizontalAlign: HorizontalAlign.Center,
  );
  final teamPlayers = r.players.where((p) => p.teamId == r.team.id).toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  final ids = {for (final p in teamPlayers) p.id};
  final sessions = r.sessions.where((s) => s.teamId == r.team.id).toList()
    ..sort((a, b) => (a.startedAt ?? a.scheduledAt ?? DateTime(2000)).compareTo(b.startedAt ?? b.scheduledAt ?? DateTime(2000)));
  final matches = r.matches.where((m) => m.teamId == r.team.id).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  final matchById = {for (final m in matches) m.id: m};
  final season = seasonStats(r.stats.where((s) => matchById.containsKey(s.matchId)));

  void sheet(String name, List<String> head, List<List<Object?>> rows, {List<double>? widths}) {
    final s = book[name];
    s.appendRow([for (final h in head) TextCellValue(h)]);
    for (var i = 0; i < head.length; i++) {
      s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = header;
      s.setColumnWidth(i, widths != null && i < widths.length ? widths[i] : (i == 0 ? 24 : 14));
    }
    for (final row in rows) {
      s.appendRow([
        for (final v in row)
          switch (v) {
            null => TextCellValue(''),
            int x => IntCellValue(x),
            double x => DoubleCellValue(double.parse(x.toStringAsFixed(2))),
            _ => TextCellValue('$v'),
          },
      ]);
    }
  }

  // Игроки: сводка.
  final latestTest = <String, PhysicalTest>{};
  for (final t in r.tests) {
    if (!ids.contains(t.playerId)) continue;
    final prev = latestTest[t.playerId];
    if (prev == null || t.testedOn.isAfter(prev.testedOn)) latestTest[t.playerId] = t;
  }
  sheet('Игроки', [
    'Игрок', 'Номер', 'Позиция', 'Год рождения', 'Посещаемость, %', 'Занятий отмечено', 'Общий балл', 'Балл ОФП',
    'Матчи', 'Минуты', 'Голы', 'Голевые', 'Ср. оценка',
  ], [
    for (final p in teamPlayers)
      () {
        var present = 0, total = 0;
        for (final a in r.attendance.where((a) => a.playerId == p.id && a.status != 'excused')) {
          total++;
          if (a.status == 'present' || a.status == 'late') present++;
        }
        final age = playerAge(p);
        final phys = latestTest[p.id] == null ? null : physicalOverall(latestTest[p.id]!, age);
        final cats = categoryScores(skillsAt(r.assessments.where((a) => a.playerId == p.id), DateTime.now()));
        if (phys != null) cats['Физика'] = phys;
        final st = season[p.id];
        return <Object?>[
          p.fullName, p.number, Positions.all[p.position] ?? '', p.birthYear,
          total == 0 ? null : (present * 100 / total).round(), total, overallScore(cats, null), phys,
          st?.games ?? 0, st?.minutes ?? 0, st?['goals'].round() ?? 0, st?['assists'].round() ?? 0, st?.avgRating,
        ];
      }(),
  ]);

  // Посещаемость: игрок × занятие.
  final marks = {for (final a in r.attendance) '${a.sessionId}|${a.playerId}': a.status};
  final marked = sessions.where((s) => teamPlayers.any((p) => marks.containsKey('${s.id}|${p.id}'))).toList();
  const short = {'present': 'Был', 'late': 'Опоздал', 'absent': 'Не был', 'injured': 'Травма', 'excused': 'Уваж.'};
  sheet('Посещаемость', ['Игрок', for (final s in marked) _d.format(s.startedAt ?? s.scheduledAt ?? DateTime.now())], [
    for (final p in teamPlayers) [p.fullName, for (final s in marked) short[marks['${s.id}|${p.id}']] ?? ''],
  ]);

  // Тренировки.
  final reportBy = {for (final x in r.reports) x.sessionId: x};
  sheet('Тренировки', ['Дата', 'Тренировка', 'Цель', 'Статус', 'План, мин', 'Блоков', 'Присутствовали', 'RPE', 'Нагрузка, усл. ед.', 'Оценка занятия'], [
    for (final s in sessions)
      [
        (s.startedAt ?? s.scheduledAt) == null ? '' : _d.format((s.startedAt ?? s.scheduledAt)!),
        s.title,
        s.goal,
        SessionStatus.labels[s.status] ?? s.status,
        s.durationMin,
        s.blocks.length,
        r.attendance.where((a) => a.sessionId == s.id && (a.status == 'present' || a.status == 'late')).length,
        reportBy[s.id]?.rpe,
        sessionLoad(s, reportBy[s.id]),
        reportBy[s.id]?.rating,
      ],
  ], widths: [12, 28, 28, 14]);

  // Статистика матчей: строка — игрок в матче.
  final playerById = {for (final p in teamPlayers) p.id: p};
  sheet('Статистика матчей', ['Дата', 'Соперник', 'Игрок', 'Старт', 'Минуты', 'Оценка', for (final k in statKeys) k.label], [
    for (final m in matches)
      for (final s in r.stats.where((s) => s.matchId == m.id && s.minutes > 0 && playerById.containsKey(s.playerId)))
        [
          _d.format(m.startsAt), m.opponent, playerById[s.playerId]!.fullName, s.started ? 'да' : '', s.minutes, s.rating,
          for (final k in statKeys) s[k.key] == 0 ? null : s[k.key].round(),
        ],
  ], widths: [12, 20, 22]);

  // Итоги сезона.
  sheet('Итоги сезона', ['Игрок', 'Матчи', 'В старте', 'Минуты', for (final k in statKeys) k.label, 'Точность передач, %', 'Ср. оценка'], [
    for (final p in teamPlayers)
      if (season[p.id] != null)
        [
          p.fullName, season[p.id]!.games, season[p.id]!.starts, season[p.id]!.minutes,
          for (final k in statKeys) season[p.id]![k.key].round(),
          season[p.id]!.passAccuracy?.round(), season[p.id]!.avgRating,
        ],
  ]);

  // ОФП: все тестирования.
  sheet('ОФП', ['Игрок', 'Дата', for (final m in physicalMetrics) '${m.label}, ${m.unit}', 'Рост, см', 'Вес, кг', 'Балл ОФП'], [
    for (final t in r.tests.where((t) => ids.contains(t.playerId)).toList()..sort((a, b) => a.testedOn.compareTo(b.testedOn)))
      [
        playerById[t.playerId]!.fullName,
        _d.format(t.testedOn),
        for (final m in physicalMetrics) t.results[m.key],
        t.results['height'],
        t.results['weight'],
        physicalOverall(t, playerAge(playerById[t.playerId]!)),
      ],
  ], widths: [24, 12]);

  // Матчи.
  sheet('Матчи', ['Дата', 'Соперник', 'Дома/в гостях', 'Турнир', 'Счёт', 'Статус'], [
    for (final m in matches)
      [_d.format(m.startsAt), m.opponent, m.home ? 'дома' : 'в гостях', m.competition, m.score, MatchStatus.labels[m.status]],
  ], widths: [12, 24, 14, 20]);

  if (r.staff.isNotEmpty) {
    sheet('Штаб', ['Имя', 'Роль', 'Телефон', 'Email'], [
      for (final s in r.staff) [s.name, StaffRoles.all[s.role] ?? s.role, s.phone, s.email],
    ], widths: [24, 22, 16, 24]);
  }

  book.delete('Sheet1');
  book.setDefaultSheet('Игроки');
  return Uint8List.fromList(book.encode()!);
}
