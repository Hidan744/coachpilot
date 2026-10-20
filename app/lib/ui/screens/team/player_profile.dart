import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_screen.dart';
import '../sessions/sessions_screens.dart';
import 'performance_providers.dart';
import 'player_development.dart';
import 'team_dashboard.dart';
import 'team_screens.dart';

/// Сводка по игроку из всех данных; пересчитывается при любом изменении.
final playerSnapshotProvider = Provider.family<PlayerSnapshot?, String>((ref, playerId) {
  final player = ref.watch(playerProvider(playerId)).value;
  if (player == null) return null;
  final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
  return PlayerSnapshot(
    player: player,
    assessments: ref.watch(allAssessmentsProvider).value ?? const [],
    tests: ref.watch(physicalTestsProvider).value ?? const [],
    attendance: ref.watch(allAttendanceProvider).value ?? const [],
    sessions: {for (final s in sessions) s.id: s},
    stats: ref.watch(matchStatsProvider).value ?? const [],
  );
});

String _initials(Player p) =>
    p.number?.toString() ?? '${p.firstName.characters.first}${p.lastName.isEmpty ? '' : p.lastName.characters.first}'.toUpperCase();

/// Карточка игрока: обзор, ОФП, развитие, статистика, родителям.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.playerId, this.initialTab = 0});

  final String playerId;

  /// Открыть сразу вкладку: 0 обзор, 1 ОФП, 2 развитие, 3 статистика, 4 родителям.
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider(playerId));
    return AsyncView(player, builder: (p) {
      if (p == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, title: 'Игрок удалён'));
      final snap = ref.watch(playerSnapshotProvider(p.id));
      return DefaultTabController(
        length: 5,
        initialIndex: initialTab.clamp(0, 4),
        child: Scaffold(
          appBar: AppBar(
            title: Text(p.fullName),
            actions: [
              IconButton(
                icon: const Icon(Icons.insert_chart_outlined),
                tooltip: 'Отчёт о прогрессе',
                onPressed: () => context.push('/team/player/${p.id}/report'),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Изменить',
                onPressed: () => showPlayerForm(context, ref, teamId: p.teamId, player: p),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить',
                onPressed: () async {
                  if (await confirm(context, 'Удалить игрока ${p.fullName}?')) {
                    await ref.read(repoProvider).remove(Entities.players, p.id);
                    if (context.mounted) context.pop();
                  }
                },
              ),
            ],
          ),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(child: _Header(player: p, snap: snap)),
              const SliverToBoxAdapter(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [Tab(text: 'Обзор'), Tab(text: 'ОФП'), Tab(text: 'Развитие'), Tab(text: 'Статистика'), Tab(text: 'Родителям')],
                ),
              ),
            ],
            body: snap == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _OverviewTab(snap),
                    PhysicalTab(snap),
                    ListView(padding: const EdgeInsets.only(bottom: 40), children: [DevelopmentSection(p)]),
                    PlayerStatsTab(snap),
                    ListView(
                      padding: const EdgeInsets.only(bottom: 40),
                      children: [ParentSection(p, present: snap.present, total: snap.total)],
                    ),
                  ]),
          ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.player, required this.snap});

  final Player player;
  final PlayerSnapshot? snap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = snap;
    final height = s?.lastTest?.results['height'], weight = s?.lastTest?.results['weight'];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.redDeep, AppColors.surfaceHigh], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.red,
                child: Text(_initials(player),
                    style: const TextStyle(fontFamily: AppTheme.display, fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(player.fullName,
                      style: t.textTheme.titleLarge?.copyWith(fontFamily: AppTheme.display, fontWeight: FontWeight.w700)),
                  Text(
                    [
                      if (player.position != null) Positions.all[player.position] ?? player.position!,
                      if (player.birthYear != null) '${playerAge(player)} лет',
                    ].join(' · '),
                    style: t.textTheme.bodySmall,
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 6, children: [
              _Fact('Посещаемость', s?.attendancePct == null ? '—' : '${s!.attendancePct}%'),
              if (height != null) _Fact('Рост', '${height.round()} см'),
              if (weight != null) _Fact('Вес', '${weight.round()} кг'),
              if ((s?.season.games ?? 0) > 0) _Fact('Матчи', '${s!.season.games}'),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        ProgressRing(
          value: (s?.overallNow ?? 0) / 100,
          center: s?.overallNow?.toString() ?? '—',
          caption: s?.overallDelta == null || s!.overallDelta == 0 ? 'общий балл' : '${signed(s.overallDelta!)} за 3 мес',
          size: 104,
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]);
}

// ---------------------------------------------------------------- обзор

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab(this.s);

  final PlayerSnapshot s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = s.player;
    final assessments = ref.watch(assessmentsProvider(p.id)).value ?? const <PlayerAssessment>[];
    final (strong, weak) = strengthsAndGaps(s.skillsNow);
    final months = [for (var i = 5; i >= 0; i--) DateTime(DateTime.now().year, DateTime.now().month - i + 1, 0)];
    final trend = [
      for (final m in months)
        () {
          final sk = skillsAt(assessments, m);
          return sk.isEmpty ? null : overallScore(categoryScores(sk), null)?.toDouble();
        }(),
    ];
    final testTrend = [
      for (final m in months)
        () {
          final t = s.tests.where((x) => !x.testedOn.isAfter(m)).lastOrNull;
          return t == null ? null : physicalOverall(t, s.age)?.toDouble();
        }(),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      // Демо: у игрока своей команды ещё нет истории — предложить заполнить примером.
      if (s.season.games == 0 && s.tests.isEmpty && s.weeks.every((w) => w.$2 == null))
        if ((ref.watch(teamsProvider).value ?? const <Team>[]).where((t) => t.id == p.teamId).firstOrNull case final team?)
          DemoFillCard(team: team),
      // Плитки фиксированной высоты: на планшете — 4 в ряд.
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 560 ? 4 : 2,
          mainAxisExtent: 112,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        children: [
          for (final e in s.categoriesNow.entries)
            KpiTile(
              label: e.key == 'Физика' && s.physicalNow != null ? 'Физподготовка' : e.key,
              value: e.value?.toString() ?? '—',
              delta: e.value != null && s.categoriesBefore[e.key] != null && e.value != s.categoriesBefore[e.key]
                  ? signed(e.value! - s.categoriesBefore[e.key]!)
                  : null,
              progress: (e.value ?? 0) / 100,
            ),
        ],
      ),
      const SizedBox(height: 12),
      DashCard(
        title: 'Ключевые навыки',
        trailing: TextButton.icon(
          onPressed: () => addAssessment(context, ref, p),
          icon: const Icon(Icons.star_outline, size: 18),
          label: const Text('Оценить'),
        ),
        child: s.skillsNow.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Оцените навыки по шкале 1–5 — появится радар и динамика.',
                    style: TextStyle(color: AppColors.textMuted)),
              )
            : Column(children: [
                RadarChart(
                  labels: [for (final k in Skills.all.keys) Skills.all[k]!],
                  values: [for (final k in Skills.all.keys) s.skillsNow[k] == null ? null : s.skillsNow[k]! * 20],
                  compare: s.skillsBefore.isEmpty || s.skillsBefore == s.skillsNow
                      ? null
                      : [for (final k in Skills.all.keys) s.skillsBefore[k] == null ? null : s.skillsBefore[k]! * 20],
                  size: 260,
                ),
                if (s.skillsBefore.isNotEmpty && s.skillsBefore != s.skillsNow)
                  const Text('Серым — 3 месяца назад', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
      ),
      if (strong.isNotEmpty || weak.isNotEmpty) ...[
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _ListCard(title: 'Сильные стороны', icon: Icons.trending_up, color: AppColors.good, items: [for (final k in strong) Skills.all[k] ?? k])),
          const SizedBox(width: 10),
          Expanded(child: _ListCard(title: 'Зоны роста', icon: Icons.flag_outlined, color: AppColors.warn, items: [for (final k in weak) Skills.all[k] ?? k])),
        ]),
      ],
      if (trend.any((v) => v != null) || testTrend.any((v) => v != null)) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Динамика развития',
          child: LineChart(
            xLabels: [for (final m in months) DateFormat('LLL', 'ru').format(m)],
            series: [
              if (trend.any((v) => v != null)) LineSeries('Оценки тренера', AppColors.red, trend),
              if (testTrend.any((v) => v != null)) LineSeries('ОФП', Colors.white, testTrend),
            ],
            minY: 0,
            maxY: 100,
          ),
        ),
      ],
      const SizedBox(height: 12),
      DashCard(
        title: 'Посещаемость по неделям',
        trailing: Text(s.total == 0 ? 'нет отметок' : '${s.present} из ${s.total}', style: const TextStyle(color: AppColors.textMuted)),
        child: BarChart(
          groups: [for (final (w, v) in s.weeks) BarGroup(DateFormat('d.MM').format(w), [v])],
          colors: const [AppColors.red],
          maxY: 1,
          percent: true,
          valueLabels: false,
          height: 120,
        ),
      ),
      const SizedBox(height: 12),
      _AssessmentsCard(player: p, assessments: assessments),
      const SizedBox(height: 12),
      DashCard(
        title: 'Заметки тренера',
        trailing: IconButton(
          tooltip: 'Изменить заметки',
          icon: const Icon(Icons.edit_note),
          onPressed: () => editPlayerNotes(context, ref, p),
        ),
        child: Text(p.notes.isEmpty ? 'Нет заметок' : p.notes, style: const TextStyle(color: AppColors.textMuted)),
      ),
    ]);
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.icon, required this.color, required this.items});

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(title.toUpperCase(), style: TextStyle(color: color, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('—', style: TextStyle(color: AppColors.textMuted)),
          for (final i in items)
            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $i')),
        ]),
      );
}

class _AssessmentsCard extends StatelessWidget {
  const _AssessmentsCard({required this.player, required this.assessments});

  final Player player;
  final List<PlayerAssessment> assessments;

  @override
  Widget build(BuildContext context) {
    final bySkill = <String, List<PlayerAssessment>>{};
    for (final a in assessments) {
      bySkill.putIfAbsent(a.skill, () => []).add(a);
    }
    for (final l in bySkill.values) {
      l.sort((a, b) => b.assessedAt.compareTo(a.assessedAt));
    }
    return DashCard(
      title: 'Оценки навыков',
      child: bySkill.isEmpty
          ? const Text('Оценок пока нет. Шкала 1–5, с датой и комментарием.', style: TextStyle(color: AppColors.textMuted))
          : Column(children: [
              for (final e in bySkill.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(Skills.all[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            DateFormat('d MMM yyyy', 'ru').format(e.value.first.assessedAt),
                            if (e.value.first.comment.isNotEmpty) e.value.first.comment,
                            if (e.value.length > 1) 'история: ${e.value.reversed.map((a) => a.score).join(', ')}',
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ]),
                    ),
                    if (e.value.length > 1) _Trend(e.value.first.score - e.value[1].score),
                    Text('${e.value.first.score}/5', style: Theme.of(context).textTheme.titleLarge),
                  ]),
                ),
            ]),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend(this.delta);

  final int delta;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Icon(
          delta > 0 ? Icons.trending_up : (delta < 0 ? Icons.trending_down : Icons.trending_flat),
          color: delta > 0 ? AppColors.good : (delta < 0 ? AppColors.warn : null),
        ),
      );
}

Future<void> editPlayerNotes(BuildContext context, WidgetRef ref, Player p) async {
  final c = TextEditingController(text: p.notes);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Заметки'),
      content: TextField(controller: c, maxLines: 6, minLines: 3, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
      ],
    ),
  );
  if (ok == true) {
    final json = p.toJson()..['notes'] = c.text.trim();
    await ref.read(repoProvider).putJson(Entities.players, p.id, json);
  }
}

Future<void> addAssessment(BuildContext context, WidgetRef ref, Player p) async {
  var skill = Skills.all.keys.first;
  var score = 3;
  final comment = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: const Text('Оценка навыка'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: skill,
            items: [for (final e in Skills.all.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => skill = v!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [for (var i = 1; i <= 5; i++) ButtonSegment(value: i, label: Text('$i'))],
            selected: {score},
            onSelectionChanged: (s) => set(() => score = s.first),
          ),
          const SizedBox(height: 16),
          TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий (наблюдение)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
        ],
      ),
    ),
  );
  if (ok == true) {
    await ref.read(repoProvider).put(
          Entities.assessments,
          PlayerAssessment(
            id: newId(),
            playerId: p.id,
            skill: skill,
            score: score,
            comment: comment.text.trim(),
            assessedAt: DateTime.now(),
          ),
        );
  }
}

// ---------------------------------------------------------------- ОФП

class PhysicalTab extends ConsumerWidget {
  const PhysicalTab(this.s, {super.key});

  final PlayerSnapshot s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = s.lastTest, prev = s.prevTest;
    final add = FilledButton.icon(
      onPressed: () => context.push('/team/player/${s.player.id}/test/new'),
      icon: const Icon(Icons.add),
      label: const Text('Новое тестирование'),
    );
    if (last == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const EmptyState(
          icon: Icons.speed,
          title: 'Тестов ОФП пока нет',
          text: 'Бег 10 и 30 м, челночный бег, прыжок в длину, Yo-Yo тест и гибкость. '
              'Результаты переводятся в баллы по возрасту и рисуют физический профиль.',
        ),
        add,
      ]);
    }
    final scores = physicalScores(last, s.age);
    final prevScores = prev == null ? null : physicalScores(prev, s.age);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      DashCard(
        title: 'Физический профиль',
        trailing: Text(DateFormat('d MMM yyyy', 'ru').format(last.testedOn), style: const TextStyle(color: AppColors.textMuted)),
        child: Column(children: [
          Row(children: [
            ProgressRing(value: (s.physicalNow ?? 0) / 100, center: '${s.physicalNow ?? '—'}', caption: 'общий балл', size: 96),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                prev == null
                    ? 'Первое тестирование. Повторите через 4–6 недель, чтобы увидеть динамику.'
                    : 'Сравнение с тестом ${DateFormat('d MMM', 'ru').format(prev.testedOn)}: '
                        '${signed((physicalOverall(last, s.age) ?? 0) - (physicalOverall(prev, s.age) ?? 0))} балла',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ]),
          RadarChart(
            labels: [for (final m in physicalMetrics) m.axis],
            values: [for (final m in physicalMetrics) scores[m.key]],
            compare: prevScores == null ? null : [for (final m in physicalMetrics) prevScores[m.key]],
            size: 250,
          ),
        ]),
      ),
      const SizedBox(height: 12),
      DashCard(
        title: 'Результаты тестов',
        child: Column(children: [
          for (final m in physicalMetrics)
            if (last.results[m.key] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${_num(last.results[m.key]!)} ${m.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (prev?.results[m.key] != null) ...[
                      const SizedBox(width: 8),
                      _ChangeChip(m.change(prev!.results[m.key]!, last.results[m.key]!)),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  TargetBar(progress: (scores[m.key] ?? 0) / 100, height: 7),
                ]),
              ),
        ]),
      ),
      if (s.tests.length > 1) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Динамика ОФП',
          child: LineChart(
            xLabels: [for (final t in s.tests) DateFormat('d.MM').format(t.testedOn)],
            series: [LineSeries('Общий балл', AppColors.red, [for (final t in s.tests) physicalOverall(t, s.age)?.toDouble()])],
            minY: 0,
            maxY: 100,
          ),
        ),
      ],
      const SizedBox(height: 12),
      add,
      const SizedBox(height: 12),
      for (final t in s.tests.reversed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_note_outlined),
          title: Text(DateFormat('d MMMM yyyy', 'ru').format(t.testedOn)),
          subtitle: Text('Балл ${physicalOverall(t, s.age) ?? '—'} · тестов: ${t.results.length}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/team/player/${s.player.id}/test/${t.id}'),
        ),
      const Text(
        'Баллы — по ориентировочным возрастным нормам: 100 — отличный результат для возраста, 0 — слабый.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    ]);
  }
}

String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

class _ChangeChip extends StatelessWidget {
  const _ChangeChip(this.pct);

  final double pct;

  @override
  Widget build(BuildContext context) {
    final good = pct >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (good ? AppColors.good : AppColors.warn).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${good ? '+' : '−'}${pct.abs().toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 12, color: good ? AppColors.good : AppColors.warn, fontWeight: FontWeight.w600)),
    );
  }
}

/// Тестирование ОФП: ввод результатов.
class PhysicalTestScreen extends ConsumerStatefulWidget {
  const PhysicalTestScreen({super.key, required this.playerId, this.testId});

  final String playerId;
  final String? testId;

  @override
  ConsumerState<PhysicalTestScreen> createState() => _PhysicalTestScreenState();
}

class _PhysicalTestScreenState extends ConsumerState<PhysicalTestScreen> {
  final _c = {
    for (final m in physicalMetrics) m.key: TextEditingController(),
    for (final k in anthropometry.keys) k: TextEditingController(),
  };
  final _notes = TextEditingController();
  DateTime _date = DateTime.now();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.testId == null) {
      _loaded = true;
    } else {
      ref.read(repoProvider).get(Entities.physicalTests, widget.testId!, PhysicalTest.fromJson).then((t) {
        if (t == null || !mounted) return;
        setState(() {
          for (final e in t.results.entries) {
            _c[e.key]?.text = _num(e.value);
          }
          _notes.text = t.notes;
          _date = t.testedOn;
          _loaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final results = <String, double>{
      for (final e in _c.entries)
        if (double.tryParse(e.value.text.replaceAll(',', '.').trim()) != null) e.key: double.parse(e.value.text.replaceAll(',', '.').trim()),
    };
    if (results.isEmpty) return showInfo(context, 'Введите хотя бы один результат');
    await ref.read(repoProvider).put(
          Entities.physicalTests,
          PhysicalTest(
            id: widget.testId ?? newId(),
            playerId: widget.playerId,
            testedOn: _date,
            results: results,
            notes: _notes.text.trim(),
          ),
        );
    if (mounted) popOr(context, '/team/player/${widget.playerId}');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.testId == null ? 'Тестирование ОФП' : 'Тестирование'),
        actions: [
          if (widget.testId != null)
            IconButton(
              tooltip: 'Удалить тестирование',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Удалить тестирование?')) {
                  await ref.read(repoProvider).remove(Entities.physicalTests, widget.testId!);
                  if (context.mounted) popOr(context, '/team/player/${widget.playerId}');
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text('Дата: ${DateFormat('d MMMM yyyy', 'ru').format(_date)}'),
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2018),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              locale: const Locale('ru'),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 8),
        const Text('Заполните только то, что тестировали.', style: TextStyle(color: AppColors.textMuted)),
        for (final m in physicalMetrics)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _c[m.key],
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(
                labelText: '${m.label}, ${m.unit}',
                helperText: [m.axis, if (m.hint.isNotEmpty) m.hint, if (m.lowerBetter) 'меньше — лучше'].join(' · '),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(children: [
          for (final e in anthropometry.entries) ...[
            Expanded(
              child: TextField(
                controller: _c[e.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${e.value.$1}, ${e.value.$2}'),
              ),
            ),
            if (e.key != anthropometry.keys.last) const SizedBox(width: 12),
          ],
        ]),
        const SizedBox(height: 12),
        TextField(controller: _notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Заметки (самочувствие, условия)')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Сохранить результаты')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- статистика

class PlayerStatsTab extends ConsumerWidget {
  const PlayerStatsTab(this.s, {super.key});

  final PlayerSnapshot s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = s.season;
    final rows = (ref.watch(matchStatsProvider).value ?? const <MatchStat>[]).where((r) => r.playerId == s.player.id && r.minutes > 0);
    final matches = {for (final m in ref.watch(matchesProvider).value ?? const <Match>[]) m.id: m};
    final list = rows.toList()..sort((a, b) => (matches[b.matchId]?.startsAt ?? DateTime(2000)).compareTo(matches[a.matchId]?.startsAt ?? DateTime(2000)));
    final keeper = s.player.position == 'GK';
    if (st.games == 0) {
      final team = (ref.watch(teamsProvider).value ?? const <Team>[]).where((t) => t.id == s.player.teamId).firstOrNull;
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (team != null) DemoFillCard(team: team),
        const EmptyState(
          icon: Icons.query_stats,
          title: 'Статистики пока нет',
          text: 'Откройте матч в календаре → «Статистика матча»: минуты, голы, передачи, отборы, карточки и оценка. '
              'Здесь соберутся итоги сезона.',
        ),
      ]);
    }
    String f1(double? v) => v == null ? '—' : v.toStringAsFixed(1);

    // Команда для сравнения: все игроки команды этого игрока.
    final teamIds = {for (final p in ref.watch(playersProvider(s.player.teamId)).value ?? const <Player>[]) p.id};
    final allRows = (ref.watch(matchStatsProvider).value ?? const <MatchStat>[]).where((r) => teamIds.contains(r.playerId)).toList();
    final team = seasonStats(allRows);
    final outfield = {for (final p in ref.watch(playersProvider(s.player.teamId)).value ?? const <Player>[]) if (p.position != 'GK') p.id};
    final profile = keeper ? null : gameProfile(st, [for (final e in team.entries) if (outfield.contains(e.key)) e.value]);
    final sw = profile == null ? null : strengthsAndWeaknesses(profile);

    // Форма: оценка по матчам и средняя оценка команды в тех же матчах.
    final chrono = list.reversed.toList();
    double? teamAvg(String matchId) {
      final r = [for (final x in allRows) if (x.matchId == matchId && x.rating != null && x.minutes > 0) x.rating!];
      return r.isEmpty ? null : r.reduce((a, b) => a + b) / r.length;
    }

    final tiles = <(String, String)>[
      ('Матчи', '${st.games}'),
      ('В старте', '${st.starts}'),
      ('Минуты', '${st.minutes}'),
      if (keeper) ...[('Сейвы', '${st['saves'].round()}'), ('Пропущено', '${st['conceded'].round()}'), ('Сухие матчи', '${st.cleanSheets}')]
      else ...[('Голы', '${st['goals'].round()}'), ('Голевые', '${st['assists'].round()}'), ('Гол+пас', '${st.goalContributions}')],
      ('Ср. оценка', f1(st.avgRating)),
      ('Точность передач', st.passAccuracy == null ? '—' : '${st.passAccuracy!.round()}%'),
      ('Удары в створ', st.shotAccuracy == null ? '—' : '${st.shotAccuracy!.round()}%'),
      if (st.duelRate != null) ('Единоборства', '${st.duelRate!.round()}%'),
      if (st['distance'] > 0) ('Км за 90 мин', st.per90('distance').toStringAsFixed(1)),
      if (st['sprints'] > 0) ('Спринты за 90', st.per90('sprints').toStringAsFixed(1)),
      if (st['top_speed'] > 0) ('Макс. скорость', '${st['top_speed'].toStringAsFixed(1)} км/ч'),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: MediaQuery.sizeOf(context).width >= 560 ? 6 : 3,
          mainAxisExtent: 92,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        children: [
          for (final (label, value) in tiles)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(child: Text(value, style: const TextStyle(fontFamily: AppTheme.display, fontSize: 24, fontWeight: FontWeight.w700))),
                Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
        ],
      ),
      if (chrono.any((r) => r.rating != null)) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Форма по матчам',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Оценка за матч и средняя по команде. Нажмите на точку.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            LineChart(
              xLabels: [
                for (final r in chrono)
                  matches[r.matchId] == null ? '—' : DateFormat('d.MM').format(matches[r.matchId]!.startsAt),
              ],
              series: [
                LineSeries(s.player.firstName, AppColors.red, [for (final r in chrono) r.rating]),
                LineSeries('Команда', chartGrey, [for (final r in chrono) teamAvg(r.matchId)]),
              ],
              minY: 4,
              maxY: 10,
            ),
          ]),
        ),
      ],
      if (profile != null && profile.values.whereType<int>().length >= 3) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Игровой профиль',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Место среди полевых игроков команды: 100 — лучший, 50 — середина.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            RadarChart(
              labels: [for (final a in gameAxes) if (profile[a.label] != null) a.label],
              values: [for (final a in gameAxes) if (profile[a.label] != null) profile[a.label]],
              compare: [for (final a in gameAxes) if (profile[a.label] != null) 50],
              size: 260,
            ),
            const Text('Серым — средний уровень команды', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      ],
      if (sw != null && (sw.strong.isNotEmpty || sw.weak.isNotEmpty)) ...[
        const SizedBox(height: 12),
        DashCard(
          title: 'Вывод тренера',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (sw.strong.isNotEmpty) ...[
              const Text('Сильные стороны', style: TextStyle(color: AppColors.good, fontWeight: FontWeight.w700)),
              for (final (label, text) in sw.strong) _Insight(icon: Icons.trending_up, color: AppColors.good, title: label, text: text),
              const SizedBox(height: 8),
            ],
            if (sw.weak.isNotEmpty) ...[
              const Text('Над чем работать', style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w700)),
              for (final (label, text) in sw.weak) _Insight(icon: Icons.build_circle_outlined, color: AppColors.warn, title: label, text: text),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 12),
      DashCard(
        title: 'Сезон: всего и за 90 минут',
        child: Table(
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
          children: [
            const TableRow(children: [
              SizedBox(),
              Text('Всего', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text('за 90', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
            for (final k in statKeys)
              if (st[k.key] > 0 || (!k.keeper || keeper) && k.basic)
                TableRow(children: [
                  Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(k.label)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(k.format(st[k.key]), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(k.max ? '—' : st.per90(k.key).toStringAsFixed(2),
                        textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textMuted)),
                  ),
                ]),
          ],
        ),
      ),
      const SizedBox(height: 12),
      DashCard(
        title: 'По матчам',
        child: Column(children: [
          for (final r in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(matches[r.matchId]?.opponent ?? 'Матч'),
              subtitle: Text([
                if (matches[r.matchId] != null) DateFormat('d MMM', 'ru').format(matches[r.matchId]!.startsAt),
                '${r.minutes} мин',
                if (r['goals'] > 0) 'голы: ${r['goals'].round()}',
                if (r['assists'] > 0) 'голевые: ${r['assists'].round()}',
                if (r['yellow'] > 0) 'ЖК',
                if (r['red'] > 0) 'КК',
              ].join(' · ')),
              trailing: r.rating == null ? null : Text(r.rating!.toStringAsFixed(1), style: Theme.of(context).textTheme.titleLarge),
              onTap: () => context.push('/calendar/match/${r.matchId}/stats'),
            ),
        ]),
      ),
    ]);
  }
}

/// Строка вывода: направление игры и пояснение.
class _Insight extends StatelessWidget {
  const _Insight({required this.icon, required this.color, required this.title, required this.text});

  final IconData icon;
  final Color color;
  final String title, text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$title. ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: text),
            ])),
          ),
        ]),
      );
}
