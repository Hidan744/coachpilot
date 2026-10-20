import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/export/excel_report.dart';
import '../../../core/export/save_file.dart';
import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_screen.dart';
import '../sessions/sessions_screens.dart';
import 'performance_providers.dart';
import 'team_screens.dart';

/// Выгрузка всей отчётности команды в Excel.
Future<void> exportTeamExcel(BuildContext context, WidgetRef ref, Team team) async {
  final repo = ref.read(repoProvider);
  try {
    final bytes = buildExcelReport(ExcelReportData(
      team: team,
      players: await repo.list(Entities.players, Player.fromJson, parentId: team.id),
      sessions: await repo.list(Entities.sessions, TrainingSession.fromJson),
      attendance: await repo.list(Entities.attendance, Attendance.fromJson),
      reports: await repo.list(Entities.reports, SessionReport.fromJson),
      matches: await repo.list(Entities.matches, Match.fromJson),
      stats: await repo.list(Entities.matchStats, MatchStat.fromJson),
      tests: await repo.list(Entities.physicalTests, PhysicalTest.fromJson),
      assessments: await repo.list(Entities.assessments, PlayerAssessment.fromJson),
      staff: await repo.list(Entities.staff, StaffMember.fromJson),
    ));
    await saveFile(bytes, 'Отчёт ${team.name} ${DateFormat('dd.MM.yyyy').format(DateTime.now())}.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    ref.read(analyticsProvider).track('excel_exported');
  } catch (_) {
    if (context.mounted) showInfo(context, 'Не удалось сформировать отчёт');
  }
}

/// Дашборд команды: посещаемость, нагрузка, ОФП, результаты, лидеры.
class TeamDashboard extends ConsumerWidget {
  const TeamDashboard({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = (ref.watch(playersProvider(team.id)).value ?? const <Player>[]).where((p) => p.active).toList();
    final ids = {for (final p in players) p.id};
    final sessions = (ref.watch(sessionsProvider).value ?? const <TrainingSession>[]).where((s) => s.teamId == team.id).toList();
    final byId = {for (final s in sessions) s.id: s};
    final attendance = (ref.watch(allAttendanceProvider).value ?? const <Attendance>[]).where((a) => ids.contains(a.playerId)).toList();
    final reports = {for (final r in ref.watch(allReportsProvider).value ?? const <SessionReport>[]) r.sessionId: r};
    final tests = (ref.watch(physicalTestsProvider).value ?? const <PhysicalTest>[]).where((t) => ids.contains(t.playerId)).toList();
    final matches = (ref.watch(matchesProvider).value ?? const <Match>[]).where((m) => m.teamId == team.id).toList();
    final matchIds = {for (final m in matches) m.id};
    final season = seasonStats((ref.watch(matchStatsProvider).value ?? const <MatchStat>[]).where((s) => matchIds.contains(s.matchId)));
    final now = DateTime.now();

    // Посещаемость: последние 4 недели против предыдущих 4.
    final weeks = attendanceByWeek(attendance, byId, weeks: 12, now: now);
    double? avgOf(Iterable<double?> v) {
      final x = v.whereType<double>();
      return x.isEmpty ? null : mean(x);
    }

    final attNow = avgOf(weeks.skip(8).map((w) => w.$2)), attPrev = avgOf(weeks.skip(4).take(4).map((w) => w.$2));

    // Нагрузка (sRPE) за 4 недели.
    final recent = sessions.where((s) => s.status == 'done' && (s.startedAt ?? s.scheduledAt ?? DateTime(2000)).isAfter(now.subtract(const Duration(days: 28))));
    final loads = [for (final s in recent) ?sessionLoad(s, reports[s.id])];
    final structure = loadStructure(sessions.where((s) => s.status == 'done' && (s.startedAt ?? DateTime(2000)).isAfter(now.subtract(const Duration(days: 56)))));

    // ОФП: средний балл команды по месяцам (последний тест игрока на конец месяца).
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i + 1, 0)];
    final age = {for (final p in players) p.id: playerAge(p, now)};
    double? teamPhysical(DateTime at) {
      final v = <int>[];
      for (final p in players) {
        final t = (tests.where((t) => t.playerId == p.id && !t.testedOn.isAfter(at)).toList()..sort((a, b) => a.testedOn.compareTo(b.testedOn))).lastOrNull;
        final s = t == null ? null : physicalOverall(t, age[p.id]!);
        if (s != null) v.add(s);
      }
      return v.isEmpty ? null : mean(v);
    }

    final physTrend = [for (final m in months) teamPhysical(m)];
    final physNow = teamPhysical(now);
    final physFirst = physTrend.whereType<double>().firstOrNull;

    // Изменение по каждому тесту: среднее по игрокам «первый → последний».
    final metricChange = <PhysicalMetric, double>{};
    for (final m in physicalMetrics) {
      final ch = <double>[];
      for (final p in players) {
        final pt = tests.where((t) => t.playerId == p.id && t.results[m.key] != null).toList()..sort((a, b) => a.testedOn.compareTo(b.testedOn));
        if (pt.length >= 2) ch.add(m.change(pt.first.results[m.key]!, pt.last.results[m.key]!));
      }
      if (ch.isNotEmpty) metricChange[m] = mean(ch);
    }

    final played = matches.where((m) => m.status == 'played' && m.hasScore).toList();
    final w = played.where((m) => m.scoreFor! > m.scoreAgainst!).length;
    final d = played.where((m) => m.scoreFor! == m.scoreAgainst!).length;
    final l = played.length - w - d;

    List<MapEntry<Player, double>> top(double Function(SeasonStats s) f) => ([
          for (final p in players)
            if (season[p.id] != null && f(season[p.id]!) > 0) MapEntry(p, f(season[p.id]!)),
        ]..sort((a, b) => b.value.compareTo(a.value)))
            .take(3)
            .toList();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
        children: [
          KpiTile(
            icon: Icons.groups_outlined,
            label: 'Посещаемость',
            value: attNow == null ? '—' : '${(attNow * 100).round()}%',
            delta: attNow != null && attPrev != null ? '${signed(((attNow - attPrev) * 100).round())}%' : null,
            caption: 'за 4 недели',
            progress: attNow,
          ),
          KpiTile(
            icon: Icons.fitness_center,
            label: 'Средняя нагрузка',
            value: loads.isEmpty ? '—' : '${mean(loads).round()}',
            caption: loads.isEmpty ? 'укажите RPE в отчёте занятия' : 'усл. ед. / тренировка',
          ),
          KpiTile(
            icon: Icons.speed,
            label: 'ОФП команды',
            value: physNow == null ? '—' : '${physNow.round()}',
            delta: physNow != null && physFirst != null && physNow != physFirst ? signed((physNow - physFirst).round()) : null,
            caption: 'средний балл',
            progress: (physNow ?? 0) / 100,
          ),
          KpiTile(
            icon: Icons.emoji_events_outlined,
            label: 'Матчи',
            value: played.isEmpty ? '—' : '$w-$d-$l',
            caption: played.isEmpty
                ? 'результатов пока нет'
                : 'победы-ничьи-поражения · ${played.fold<int>(0, (a, m) => a + m.scoreFor!)}:${played.fold<int>(0, (a, m) => a + m.scoreAgainst!)}',
          ),
        ],
      ),
      const SizedBox(height: 12),
      DashCard(
        title: 'Посещаемость по неделям',
        child: BarChart(
          groups: [for (final (wk, v) in weeks) BarGroup(DateFormat('d.MM').format(wk), [v])],
          colors: const [AppColors.red],
          maxY: 1,
          percent: true,
          valueLabels: false,
          height: 130,
        ),
      ),
      if (physTrend.any((v) => v != null)) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Динамика ОФП',
          child: LineChart(
            xLabels: [for (final m in months) DateFormat('LLL', 'ru').format(m)],
            series: [LineSeries('Средний балл ОФП', AppColors.red, physTrend)],
            minY: 0,
            maxY: 100,
          ),
        ),
      ],
      if (metricChange.isNotEmpty) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Результаты тестов',
          child: Column(children: [
            for (final e in metricChange.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 130, child: Text(e.key.label, style: const TextStyle(fontSize: 13))),
                  Expanded(child: TargetBar(progress: (e.value.abs() / 20).clamp(0.05, 1.0), height: 8)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text('${e.value >= 0 ? '+' : '−'}${e.value.abs().toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: e.value >= 0 ? AppColors.good : AppColors.warn)),
                  ),
                ]),
              ),
            const Text('Средний прирост от первого тестирования к последнему', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      ],
      if (structure.values.any((v) => v > 0)) ...[
        const SizedBox(height: 12),
        DashCard(title: 'Структура нагрузки (8 недель)', child: DonutChart(parts: structure)),
      ],
      if (season.isNotEmpty) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Лидеры сезона',
          child: Column(children: [
            for (final (title, list, fmt) in [
              ('Бомбардиры', top((s) => s['goals']), (double v) => v.round().toString()),
              ('Ассистенты', top((s) => s['assists']), (double v) => v.round().toString()),
              ('Средняя оценка', top((s) => s.games >= 2 ? (s.avgRating ?? 0) : 0), (double v) => v.toStringAsFixed(1)),
            ])
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: Text(title, style: const TextStyle(color: AppColors.textMuted))),
                    Expanded(child: Text([for (final e in list) '${e.key.fullName} ${fmt(e.value)}'].join(' · '))),
                  ]),
                ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      DashCard(
        title: 'Отчёты',
        child: Column(children: [
          _ReportTile(
            icon: Icons.table_chart_outlined,
            title: 'Для штаба: Excel',
            subtitle: 'Игроки, посещаемость, тренировки, статистика, ОФП',
            onTap: () => exportTeamExcel(context, ref, team),
          ),
          _ReportTile(
            icon: Icons.person_outline,
            title: 'Для игрока и родителей',
            subtitle: 'Визуальный отчёт о прогрессе: PDF или картинка',
            onTap: () => _pickPlayer(context, players),
          ),
        ]),
      ),
    ]);
  }

  void _pickPlayer(BuildContext context, List<Player> players) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (c, scroll) => ListView(controller: scroll, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Отчёт игрока', style: TextStyle(fontSize: 18))),
            for (final p in players)
              ListTile(
                title: Text(p.fullName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(c);
                  context.push('/team/player/${p.id}/report');
                },
              ),
          ]),
        ),
      );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.red),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

/// Статистика сезона по команде: таблица по игрокам.
class TeamStatsTable extends ConsumerStatefulWidget {
  const TeamStatsTable({super.key, required this.team});

  final Team team;

  @override
  ConsumerState<TeamStatsTable> createState() => _TeamStatsTableState();
}

class _TeamStatsTableState extends ConsumerState<TeamStatsTable> {
  String _sort = 'goals';

  static const _cols = [
    ('games', 'И'),
    ('minutes', 'Мин'),
    ('goals', 'Г'),
    ('assists', 'П'),
    ('ga', 'Г+П'),
    ('shots', 'Уд'),
    ('pass', 'Пер%'),
    ('tackles', 'Отб'),
    ('yellow', 'ЖК'),
    ('red', 'КК'),
    ('rating', 'Оц'),
  ];

  double _value(SeasonStats s, String k) => switch (k) {
        'games' => s.games.toDouble(),
        'minutes' => s.minutes.toDouble(),
        'ga' => s.goalContributions.toDouble(),
        'pass' => s.passAccuracy ?? -1,
        'rating' => s.avgRating ?? -1,
        _ => s[k],
      };

  String _fmt(SeasonStats s, String k) => switch (k) {
        'pass' => s.passAccuracy == null ? '—' : '${s.passAccuracy!.round()}',
        'rating' => s.avgRating == null ? '—' : s.avgRating!.toStringAsFixed(1),
        _ => _value(s, k).round().toString(),
      };

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider(widget.team.id)).value ?? const <Player>[];
    final matches = (ref.watch(matchesProvider).value ?? const <Match>[]).where((m) => m.teamId == widget.team.id).toList();
    final matchIds = {for (final m in matches) m.id};
    final season = seasonStats((ref.watch(matchStatsProvider).value ?? const <MatchStat>[]).where((s) => matchIds.contains(s.matchId)));
    final rows = [for (final p in players) if (season[p.id] != null && season[p.id]!.games > 0) (p, season[p.id]!)]
      ..sort((a, b) => _value(b.$2, _sort).compareTo(_value(a.$2, _sort)));
    if (rows.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const EmptyState(
          icon: Icons.query_stats,
          title: 'Статистики пока нет',
          text: 'Откройте матч в календаре и нажмите «Статистика матча»: кто играл, минуты, голы, передачи, отборы, '
              'карточки, оценка. Можно загрузить таблицу из Excel.',
        ),
        FilledButton.icon(
          onPressed: () => context.go('/calendar'),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('Открыть календарь'),
        ),
      ]);
    }
    final t = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(8, 12, 8, 120), children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('Сезон: матчей сыграно ${matches.where((m) => m.status == 'played').length}. Нажмите на столбец, чтобы отсортировать.',
            style: const TextStyle(color: AppColors.textMuted)),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          showCheckboxColumn: false,
          horizontalMargin: 8,
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 44,
          columns: [
            const DataColumn(label: Text('Игрок')),
            for (final (k, label) in _cols)
              DataColumn(
                numeric: true,
                label: Text(label, style: TextStyle(color: _sort == k ? AppColors.red : null, fontWeight: FontWeight.w700)),
                onSort: (_, _) => setState(() => _sort = k),
              ),
          ],
          rows: [
            for (final (p, s) in rows)
              DataRow(
                onSelectChanged: (_) => context.push('/team/player/${p.id}'),
                cells: [
                  DataCell(Text(p.lastName.isEmpty ? p.firstName : '${p.lastName} ${p.firstName.characters.first}.',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  for (final (k, _) in _cols) DataCell(Text(_fmt(s, k))),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('И — игры, Г — голы, П — голевые передачи, Уд — удары, Пер% — точность передач, Отб — отборы, Оц — средняя оценка.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
    ]);
  }
}
