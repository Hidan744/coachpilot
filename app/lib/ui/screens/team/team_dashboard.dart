import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/demo_data.dart';
import '../../../core/export/excel_report.dart';
import '../../../core/export/save_file.dart';
import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
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

/// Демо: заполнить свою команду примером истории — тренировки, посещаемость, матчи со статистикой,
/// тесты ОФП, оценки, программы развития. Чтобы сразу увидеть аналитику на своих игроках.
Future<void> fillTeamWithDemo(BuildContext context, WidgetRef ref, Team team) async {
  final repo = ref.read(repoProvider);
  final players = (await repo.list(Entities.players, Player.fromJson, parentId: team.id)).where((p) => p.active).toList();
  if (players.isEmpty) {
    if (context.mounted) showInfo(context, 'Сначала добавьте игроков в состав');
    return;
  }
  await ref.read(dbProvider).transaction(() => seedTeamHistory(repo, team, players, seed: team.id.hashCode));
  if (context.mounted) showInfo(context, 'Готово: история сезона для ${players.length} игроков');
}

/// Плашка демо: своя команда без истории — предложить заполнить примером.
class DemoFillCard extends ConsumerWidget {
  const DemoFillCard({super.key, required this.team});

  final Team team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(authProvider).demo) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(accent: true),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Демо: покажем аналитику на ваших игроках',
            style: TextStyle(fontFamily: AppTheme.display, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Заполним команду примером сезона: тренировки и посещаемость, матчи со статистикой как в профи '
          '(удары, передачи, единоборства, дистанция, спринты), тесты ОФП, оценки и планы развития.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => fillTeamWithDemo(context, ref, team),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Заполнить демо-данными'),
        ),
      ]),
    );
  }
}

/// Дашборд команды: посещаемость, нагрузка, ОФП, результаты, лидеры.
class TeamDashboard extends ConsumerWidget {
  const TeamDashboard({super.key, required this.team, this.embedded = false});

  final Team team;

  /// Внутри другого списка (главный экран): без собственной прокрутки.
  final bool embedded;

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

    final kpis = [
      KpiTile(
        icon: Icons.groups_outlined,
        label: 'Посещаемость',
        value: attNow == null ? '—' : '${(attNow * 100).round()}%',
        delta: attNow != null && attPrev != null ? '${signed(((attNow - attPrev) * 100).round())}%' : null,
        caption: 'за 4 недели',
        progress: attNow,
        onTap: () => _attendanceDetails(context, players, attendance, byId, now),
      ),
      KpiTile(
        icon: Icons.fitness_center,
        label: 'Средняя нагрузка',
        value: loads.isEmpty ? '—' : '${mean(loads).round()}',
        caption: loads.isEmpty ? 'укажите RPE в отчёте занятия' : 'усл. ед. / тренировка',
        onTap: () => _loadDetails(context, recent.toList(), reports),
      ),
      KpiTile(
        icon: Icons.speed,
        label: 'ОФП команды',
        value: physNow == null ? '—' : '${physNow.round()}',
        delta: physNow != null && physFirst != null && physNow != physFirst ? signed((physNow - physFirst).round()) : null,
        caption: 'средний балл',
        progress: (physNow ?? 0) / 100,
        onTap: () => _physicalDetails(context, players, tests, age),
      ),
      KpiTile(
        icon: Icons.emoji_events_outlined,
        label: 'Матчи',
        value: played.isEmpty ? '—' : '$w-$d-$l',
        caption: played.isEmpty
            ? 'результатов пока нет'
            : 'победы-ничьи-поражения · ${played.fold<int>(0, (a, m) => a + m.scoreFor!)}:${played.fold<int>(0, (a, m) => a + m.scoreAgainst!)}',
        onTap: () => _matchDetails(context, played),
      ),
    ];

    final cards = <Widget>[
      _AttendanceCard(attendance: attendance, sessions: byId, now: now),
      if (physTrend.any((v) => v != null))
        DashCard(
          title: 'Динамика ОФП',
          child: LineChart(
            xLabels: [for (final m in months) DateFormat('LLL', 'ru').format(m)],
            series: [LineSeries('Средний балл ОФП', AppColors.red, physTrend)],
            minY: 0,
            maxY: 100,
          ),
        ),
      if (metricChange.isNotEmpty)
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
      if (structure.values.any((v) => v > 0)) DashCard(title: 'Структура нагрузки (8 недель)', child: DonutChart(parts: structure)),
      if (season.isNotEmpty)
        DashCard(
          title: 'Лидеры сезона',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (title, list, fmt) in [
              ('Бомбардиры', top((s) => s['goals']), (double v) => v.round().toString()),
              ('Ассистенты', top((s) => s['assists']), (double v) => v.round().toString()),
              ('Средняя оценка', top((s) => s.games >= 2 ? (s.avgRating ?? 0) : 0), (double v) => v.toStringAsFixed(1)),
            ])
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    // Игрок — кнопка: открывает его статистику.
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in list)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${e.key.fullName}  ${fmt(e.value)}'),
                          onPressed: () => context.push('/team/player/${e.key.id}?tab=3'),
                        ),
                    ]),
                  ]),
                ),
          ]),
        ),
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
    ];

    // Карточки появляются по очереди — дашборд «собирается» сверху вниз.
    // На планшете показатели — в один ряд, карточки — парами.
    final content = LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      var i = 0;
      Widget a(Widget w) => Appear(index: i++, child: w);
      final rows = <Widget>[
        if (played.isEmpty) DemoFillCard(team: team),
        a(GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 4 : 2,
            mainAxisExtent: 128,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          children: kpis,
        )),
      ];
      for (var k = 0; k < cards.length; k += wide ? 2 : 1) {
        rows.add(const SizedBox(height: 12));
        if (wide && k + 1 < cards.length) {
          // Без IntrinsicHeight: графики строятся через LayoutBuilder.
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: a(cards[k])),
            const SizedBox(width: 12),
            Expanded(child: a(cards[k + 1])),
          ]));
        } else {
          rows.add(a(cards[k]));
        }
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
    if (embedded) return content;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 120), children: [content]);
  }

  // ---------------------------------------------------------------- подробности показателей

  void _details(BuildContext context, String title, String hint, List<Widget> rows) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text(title, style: const TextStyle(fontFamily: AppTheme.display, fontSize: 22, fontWeight: FontWeight.w700)),
            Text(hint, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Пока нет данных.')),
            ...rows,
          ]),
        ),
      );

  void _attendanceDetails(BuildContext context, List<Player> players, List<Attendance> marks, Map<String, TrainingSession> sessions, DateTime now) {
    final from = now.subtract(const Duration(days: 28));
    final rows = <(Player, int, int)>[];
    for (final p in players) {
      var present = 0, total = 0;
      for (final a in marks.where((a) => a.playerId == p.id)) {
        final s = sessions[a.sessionId];
        final at = s?.startedAt ?? s?.scheduledAt;
        if (at == null || at.isBefore(from)) continue;
        total++;
        if (a.status == 'present' || a.status == 'late') present++;
      }
      if (total > 0) rows.add((p, present, total));
    }
    rows.sort((a, b) => (a.$2 / a.$3).compareTo(b.$2 / b.$3));
    _details(context, 'Посещаемость', 'За 4 недели, сначала — кто пропускает чаще. Нажмите на игрока.', [
      for (final (p, present, total) in rows)
        _DetailRow(
          title: p.fullName,
          subtitle: 'был на $present из $total',
          value: '${(present * 100 / total).round()}%',
          progress: present / total,
          warn: present / total < 0.75,
          onTap: () => context.push('/team/player/${p.id}'),
        ),
    ]);
  }

  void _loadDetails(BuildContext context, List<TrainingSession> recent, Map<String, SessionReport> reports) {
    recent.sort((a, b) => (b.startedAt ?? b.scheduledAt ?? DateTime(2000)).compareTo(a.startedAt ?? a.scheduledAt ?? DateTime(2000)));
    final loads = [for (final s in recent) sessionLoad(s, reports[s.id])];
    final maxLoad = loads.whereType<int>().fold<int>(1, (a, b) => b > a ? b : a);
    _details(context, 'Нагрузка', 'Занятия за 4 недели: RPE × минуты. Нажмите, чтобы открыть итоги занятия.', [
      for (var i = 0; i < recent.length; i++)
        _DetailRow(
          title: recent[i].title,
          subtitle: '${formatWhen(recent[i].startedAt ?? recent[i].scheduledAt)}'
              '${reports[recent[i].id]?.rpe == null ? ' · RPE не указан' : ' · RPE ${reports[recent[i].id]!.rpe}'}',
          value: loads[i]?.toString() ?? '—',
          progress: (loads[i] ?? 0) / maxLoad,
          onTap: () => context.push('/sessions/${recent[i].id}/summary'),
        ),
    ]);
  }

  void _physicalDetails(BuildContext context, List<Player> players, List<PhysicalTest> tests, Map<String, int> age) {
    final rows = <(Player, int, int?)>[];
    for (final p in players) {
      final pt = tests.where((t) => t.playerId == p.id).toList()..sort((a, b) => a.testedOn.compareTo(b.testedOn));
      if (pt.isEmpty) continue;
      final last = physicalOverall(pt.last, age[p.id]!);
      if (last == null) continue;
      final first = pt.length > 1 ? physicalOverall(pt.first, age[p.id]!) : null;
      rows.add((p, last, first == null ? null : last - first));
    }
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    _details(context, 'ОФП команды', 'Балл 0–100 по нормам возраста и рост с первого тестирования. Нажмите на игрока.', [
      for (final (p, score, delta) in rows)
        _DetailRow(
          title: p.fullName,
          subtitle: delta == null ? 'одно тестирование' : 'с первого теста: ${signed(delta)}',
          value: '$score',
          progress: score / 100,
          warn: score < 50,
          onTap: () => context.push('/team/player/${p.id}?tab=1'),
        ),
    ]);
  }

  void _matchDetails(BuildContext context, List<Match> played) {
    final list = [...played]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    _details(context, 'Матчи', 'Сыгранные матчи. Нажмите, чтобы открыть статистику игроков.', [
      for (final m in list)
        _DetailRow(
          title: '${m.home ? '' : '@ '}${m.opponent}',
          subtitle: '${DateFormat('d MMMM', 'ru').format(m.startsAt)}${m.competition.isEmpty ? '' : ' · ${m.competition}'}',
          value: '${m.scoreFor}:${m.scoreAgainst}',
          warn: m.scoreFor! < m.scoreAgainst!,
          good: m.scoreFor! > m.scoreAgainst!,
          onTap: () => context.push('/calendar/match/${m.id}/stats'),
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

/// Строка подробностей: название, подпись, значение и полоса.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.title,
    required this.subtitle,
    required this.value,
    this.progress,
    this.warn = false,
    this.good = false,
    required this.onTap,
  });

  final String title, subtitle, value;
  final double? progress;
  final bool warn, good;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                if (progress != null) ...[const SizedBox(height: 6), TargetBar(progress: progress!, height: 6)],
              ]),
            ),
            const SizedBox(width: 12),
            Text(value,
                style: TextStyle(
                  fontFamily: AppTheme.display,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: warn ? AppColors.warn : (good ? AppColors.good : AppColors.text),
                )),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ]),
        ),
      );
}

/// Посещаемость по неделям с выбором периода.
class _AttendanceCard extends StatefulWidget {
  const _AttendanceCard({required this.attendance, required this.sessions, required this.now});

  final List<Attendance> attendance;
  final Map<String, TrainingSession> sessions;
  final DateTime now;

  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard> {
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final weeks = attendanceByWeek(widget.attendance, widget.sessions, weeks: _weeks, now: widget.now);
    // Сколько отметок в каждой неделе — для подсказки «был N из M».
    final counts = List.filled(_weeks, 0);
    final start = weeks.first.$1;
    for (final a in widget.attendance) {
      final s = widget.sessions[a.sessionId];
      final at = s?.startedAt ?? s?.scheduledAt;
      if (at == null) continue;
      final i = weekStart(at).difference(start).inDays ~/ 7;
      if (i >= 0 && i < _weeks) counts[i]++;
    }
    return DashCard(
      title: 'Посещаемость по неделям',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            segments: const [
              ButtonSegment(value: 4, label: Text('4 недели')),
              ButtonSegment(value: 12, label: Text('12 недель')),
              ButtonSegment(value: 26, label: Text('Полгода')),
            ],
            selected: {_weeks},
            onSelectionChanged: (v) => setState(() => _weeks = v.first),
          ),
        ),
        const SizedBox(height: 4),
        const Text('Нажмите на столбец, чтобы увидеть неделю', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 6),
        BarChart(
        key: ValueKey(_weeks),
        groups: [for (final (wk, v) in weeks) BarGroup(DateFormat('d.MM').format(wk), [v])],
        colors: const [AppColors.red],
        maxY: 1,
        percent: true,
        valueLabels: _weeks <= 4,
        height: 140,
        describe: (i) => [
          'неделя с ${DateFormat('d MMMM', 'ru').format(weeks[i].$1)}',
          weeks[i].$2 == null ? 'занятий не было' : '${(weeks[i].$2! * 100).round()}% · отметок: ${counts[i]}',
        ],
      ),
      ]),
    );
  }
}

/// Статистика сезона по команде: таблица по игрокам.
class TeamStatsTable extends ConsumerStatefulWidget {
  const TeamStatsTable({super.key, required this.team});

  final Team team;

  @override
  ConsumerState<TeamStatsTable> createState() => _TeamStatsTableState();
}

class _TeamStatsTableState extends ConsumerState<TeamStatsTable> {
  String _group = 'main';
  String _sort = 'goals';

  static String _int(double v) => v.round().toString();
  static String _f1(double v) => v.toStringAsFixed(1);
  static String _pct(double v) => v < 0 ? '—' : '${v.round()}';

  /// Колонка: ключ сортировки, заголовок, значение и вид.
  static final _groups = <String, (String, List<(String, String, double Function(SeasonStats), String Function(double))>)>{
    'main': ('Основное', [
      ('games', 'И', (s) => s.games.toDouble(), _int),
      ('minutes', 'Мин', (s) => s.minutes.toDouble(), _int),
      ('goals', 'Г', (s) => s['goals'], _int),
      ('assists', 'П', (s) => s['assists'], _int),
      ('ga', 'Г+П', (s) => s.goalContributions.toDouble(), _int),
      ('pass', 'Пер%', (s) => s.passAccuracy ?? -1, _pct),
      ('yellow', 'ЖК', (s) => s['yellow'], _int),
      ('rating', 'Оц', (s) => s.avgRating ?? -1, (v) => v < 0 ? '—' : _f1(v)),
    ]),
    'attack': ('Атака', [
      ('goals', 'Г', (s) => s['goals'], _int),
      ('shots', 'Уд', (s) => s['shots'], _int),
      ('shots_on', 'УдС', (s) => s['shots_on'], _int),
      ('shot_acc', 'Створ%', (s) => s.shotAccuracy ?? -1, _pct),
      ('goals90', 'Г/90', (s) => s.per90('goals'), (v) => v.toStringAsFixed(2)),
      ('dribbles', 'Обв', (s) => s['dribbles'], _int),
    ]),
    'passing': ('Передачи', [
      ('passes', 'Пер', (s) => s['passes'], _int),
      ('pass', 'Точн%', (s) => s.passAccuracy ?? -1, _pct),
      ('key_passes', 'КП', (s) => s['key_passes'], _int),
      ('assists', 'ГП', (s) => s['assists'], _int),
      ('crosses', 'Нав', (s) => s['crosses'], _int),
    ]),
    'defence': ('Оборона', [
      ('tackles', 'Отб', (s) => s['tackles'], _int),
      ('interceptions', 'Пхв', (s) => s['interceptions'], _int),
      ('recoveries', 'Под', (s) => s['recoveries'], _int),
      ('duel', 'Ед%', (s) => s.duelRate ?? -1, _pct),
      ('losses', 'Пот', (s) => s['losses'], _int),
      ('fouls', 'Ф', (s) => s['fouls'], _int),
    ]),
    'physical': ('Физика', [
      ('distance', 'Км', (s) => s['distance'], _f1),
      ('distance90', 'Км/90', (s) => s.per90('distance'), _f1),
      ('sprints', 'Спр', (s) => s['sprints'], _int),
      ('sprints90', 'Спр/90', (s) => s.per90('sprints'), _f1),
      ('top_speed', 'Скор', (s) => s['top_speed'], _f1),
    ]),
  };

  static const _legend = {
    'main': 'И — игры, Г — голы, П — голевые передачи, Пер% — точность передач, Оц — средняя оценка.',
    'attack': 'Уд — удары, УдС — в створ, Створ% — доля ударов в створ, Г/90 — голы за 90 минут, Обв — удачные обводки.',
    'passing': 'Пер — передачи, Точн% — точность, КП — ключевые (после них удар), ГП — голевые, Нав — навесы.',
    'defence': 'Отб — отборы, Пхв — перехваты, Под — подборы, Ед% — выигранные единоборства, Пот — потери, Ф — фолы.',
    'physical': 'Км — дистанция за сезон, Км/90 — за полный матч, Спр — спринты, Скор — максимальная скорость, км/ч.',
  };

  @override
  Widget build(BuildContext context) {
    final players = ref.watch(playersProvider(widget.team.id)).value ?? const <Player>[];
    final matches = (ref.watch(matchesProvider).value ?? const <Match>[]).where((m) => m.teamId == widget.team.id).toList();
    final matchIds = {for (final m in matches) m.id};
    final season = seasonStats((ref.watch(matchStatsProvider).value ?? const <MatchStat>[]).where((s) => matchIds.contains(s.matchId)));
    final cols = _groups[_group]!.$2;
    if (!cols.any((c) => c.$1 == _sort)) _sort = cols.first.$1;
    final sortBy = cols.firstWhere((c) => c.$1 == _sort).$3;
    final rows = [for (final p in players) if (season[p.id] != null && season[p.id]!.games > 0) (p, season[p.id]!)]
      ..sort((a, b) => sortBy(b.$2).compareTo(sortBy(a.$2)));
    if (rows.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        DemoFillCard(team: widget.team),
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
      // Группы показателей — как вкладки в профессиональной аналитике.
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          for (final e in _groups.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value.$1),
                selected: _group == e.key,
                onSelected: (_) => setState(() => _group = e.key),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
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
            for (final (k, label, _, _) in cols)
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
                  for (final (_, _, value, fmt) in cols) DataCell(Text(fmt(value(s)))),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(_legend[_group]!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
    ]);
  }
}
