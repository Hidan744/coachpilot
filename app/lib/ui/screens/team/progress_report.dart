import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/export/save_file.dart';
import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../sessions/sessions_screens.dart';
import 'performance_providers.dart';
import 'player_development.dart';
import 'team_screens.dart';

const _periods = {30: 'Месяц', 90: '3 месяца', 270: 'Сезон'};

/// Визуальный отчёт о прогрессе игрока: «было → стало → следующий шаг».
/// Отправляется игроку, родителям или штабу как PDF или картинка.
class ProgressReportScreen extends ConsumerStatefulWidget {
  const ProgressReportScreen({super.key, required this.playerId});

  final String playerId;

  @override
  ConsumerState<ProgressReportScreen> createState() => _ProgressReportScreenState();
}

class _ProgressReportScreenState extends ConsumerState<ProgressReportScreen> {
  final _boundary = GlobalKey();
  final _summary = TextEditingController();
  int _days = 90;
  bool _busy = false;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Future<Uint8List?> _png() async {
    final b = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return null;
    final image = await b.toImage(pixelRatio: 2.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  String _fileBase(Player p) => 'Отчёт ${p.fullName} ${DateFormat('dd.MM.yyyy').format(DateTime.now())}';

  Future<void> _export(Player p, {required bool pdf}) async {
    setState(() => _busy = true);
    try {
      final png = await _png();
      if (png == null) return;
      if (!pdf) {
        await saveFile(png, '${_fileBase(p)}.png', 'image/png');
      } else {
        final img = await decodeImageFromList(png);
        final doc = pw.Document(title: 'Отчёт о прогрессе: ${p.fullName}', author: AppBrand.clubName);
        const width = 595.0;
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(width, width * img.height / img.width),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
        ));
        await saveFile(await doc.save(), '${_fileBase(p)}.pdf', 'application/pdf');
      }
      ref.read(analyticsProvider).track('progress_report_exported', {'format': pdf ? 'pdf' : 'png'});
    } catch (_) {
      if (mounted) showInfo(context, 'Не удалось сохранить отчёт. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider(widget.playerId)).value;
    if (player == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
    final snap = PlayerSnapshot(
      player: player,
      assessments: ref.watch(allAssessmentsProvider).value ?? const [],
      tests: ref.watch(physicalTestsProvider).value ?? const [],
      attendance: ref.watch(allAttendanceProvider).value ?? const [],
      sessions: {for (final s in sessions) s.id: s},
      stats: ref.watch(matchStatsProvider).value ?? const [],
      periodDays: _days,
    );
    final plans = ref.watch(devPlansProvider(player.id)).value ?? const <DevelopmentPlan>[];
    final team = (ref.watch(teamsProvider).value ?? const <Team>[]).where((t) => t.id == player.teamId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Отчёт о прогрессе')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _export(player, pdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Скачать PDF'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _export(player, pdf: false),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Картинка'),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        SegmentedButton<int>(
          segments: [for (final e in _periods.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_days},
          onSelectionChanged: (s) => setState(() => _days = s.first),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _summary,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Вывод тренера (попадёт в отчёт)'),
        ),
        const SizedBox(height: 12),
        RepaintBoundary(
          key: _boundary,
          child: ProgressReportView(snap: snap, team: team, plans: plans, summary: _summary.text.trim(), periodLabel: _periods[_days]!),
        ),
      ]),
    );
  }
}

/// Сам отчёт — отдельный виджет, чтобы его можно было снять в картинку целиком.
class ProgressReportView extends StatelessWidget {
  const ProgressReportView({
    super.key,
    required this.snap,
    required this.team,
    required this.plans,
    required this.summary,
    required this.periodLabel,
  });

  final PlayerSnapshot snap;
  final Team? team;
  final List<DevelopmentPlan> plans;
  final String summary, periodLabel;

  @override
  Widget build(BuildContext context) {
    final s = snap;
    final p = s.player;
    final (strong, weak) = strengthsAndGaps(s.skillsNow);
    final active = ([...plans]..sort((a, b) => (b.startsOn ?? DateTime(2000)).compareTo(a.startsOn ?? DateTime(2000)))).firstOrNull;
    final nextSteps = [
      for (final t in active?.targets ?? const <PlanTarget>[])
        '${t.name}: ${t.current == null ? '' : '${_n(t.current!)} → '}${t.target == null ? '' : _n(t.target!)} ${t.unit}'.trim(),
      for (final i in active?.items ?? const <PlanItem>[]) if (!i.done) i.text,
    ].take(5).toList();
    final cats = s.categoriesNow.keys.where((k) => s.categoriesNow[k] != null || s.categoriesBefore[k] != null).toList();
    return Container(
      color: AppColors.black,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Шапка.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.red, Color(0xFF7A0009)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${AppBrand.clubName.toUpperCase()} · ОТЧЁТ О ПРОГРЕССЕ',
                    style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: Colors.white70)),
                const SizedBox(height: 6),
                Text(p.fullName.toUpperCase(),
                    style: const TextStyle(fontFamily: AppTheme.display, fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(
                  [
                    if (p.number != null) '№${p.number}',
                    if (p.position != null) Positions.all[p.position] ?? p.position!,
                    if (p.birthYear != null) '${s.age} лет',
                    if (team != null) team!.name,
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text('Период: $periodLabel · ${DateFormat('d MMMM yyyy', 'ru').format(DateTime.now())}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
            ProgressRing(
              value: (s.overallNow ?? 0) / 100,
              center: s.overallDelta == null ? '${s.overallNow ?? '—'}' : signed(s.overallDelta!),
              caption: s.overallDelta == null ? 'общий балл' : 'общий прогресс',
              size: 96,
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: KpiTile(label: 'Общий балл', value: '${s.overallNow ?? '—'}', caption: s.overallBefore == null ? null : 'было ${s.overallBefore}')),
          const SizedBox(width: 8),
          Expanded(
            child: KpiTile(
              label: 'Посещаемость',
              value: s.attendancePct == null ? '—' : '${s.attendancePct}%',
              caption: s.total == 0 ? null : '${s.present} из ${s.total}',
              progress: (s.attendancePct ?? 0) / 100,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: KpiTile(
              label: 'ОФП',
              value: '${s.physicalNow ?? '—'}',
              delta: s.physicalNow != null && s.physicalBefore != null ? signed(s.physicalNow! - s.physicalBefore!) : null,
            ),
          ),
        ]),
        if (cats.isNotEmpty) ...[
          const SizedBox(height: 10),
          DashCard(
            title: 'Было → стало',
            child: BarChart(
              groups: [
                for (final k in cats)
                  BarGroup(
                    k,
                    [s.categoriesBefore[k]?.toDouble(), s.categoriesNow[k]?.toDouble()],
                    caption: s.categoriesNow[k] != null && s.categoriesBefore[k] != null
                        ? signed(s.categoriesNow[k]! - s.categoriesBefore[k]!)
                        : null,
                  ),
              ],
              legend: const ['Было', 'Стало'],
              maxY: 100,
              height: 170,
            ),
          ),
        ],
        if (s.lastTest != null) ...[
          const SizedBox(height: 10),
          DashCard(
            title: 'Физический профиль',
            child: Column(children: [
              RadarChart(
                labels: [for (final m in physicalMetrics) m.axis],
                values: [for (final m in physicalMetrics) physicalScores(s.lastTest!, s.age)[m.key]],
                compare: s.baseTest == null || identical(s.baseTest, s.lastTest)
                    ? null
                    : [for (final m in physicalMetrics) physicalScores(s.baseTest!, s.age)[m.key]],
                size: 230,
              ),
              if (s.baseTest != null && !identical(s.baseTest, s.lastTest))
                for (final m in physicalMetrics)
                  if (s.lastTest!.results[m.key] != null && s.baseTest!.results[m.key] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(child: Text(m.label)),
                        Text('${_n(s.baseTest!.results[m.key]!)} → ${_n(s.lastTest!.results[m.key]!)} ${m.unit}  ',
                            style: const TextStyle(color: AppColors.textMuted)),
                        Text(
                          '${m.change(s.baseTest!.results[m.key]!, s.lastTest!.results[m.key]!) >= 0 ? '+' : '−'}'
                          '${m.change(s.baseTest!.results[m.key]!, s.lastTest!.results[m.key]!).abs().toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: m.change(s.baseTest!.results[m.key]!, s.lastTest!.results[m.key]!) >= 0 ? AppColors.good : AppColors.warn,
                          ),
                        ),
                      ]),
                    ),
            ]),
          ),
        ],
        if (s.season.games > 0) ...[
          const SizedBox(height: 10),
          DashCard(
            title: 'Игровая статистика',
            child: Wrap(spacing: 18, runSpacing: 8, children: [
              _Num('Матчи', '${s.season.games}'),
              _Num('Минуты', '${s.season.minutes}'),
              if (p.position == 'GK') ...[
                _Num('Сейвы', '${s.season['saves'].round()}'),
                _Num('Сухие', '${s.season.cleanSheets}'),
              ] else ...[
                _Num('Голы', '${s.season['goals'].round()}'),
                _Num('Голевые', '${s.season['assists'].round()}'),
              ],
              if (s.season.avgRating != null) _Num('Ср. оценка', s.season.avgRating!.toStringAsFixed(1)),
              if (s.season.passAccuracy != null) _Num('Точность передач', '${s.season.passAccuracy!.round()}%'),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        DashCard(
          title: 'Выводы и рекомендации',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (summary.isNotEmpty) ...[
              Text(summary, style: const TextStyle(height: 1.35)),
              const SizedBox(height: 10),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _Column('Сильные стороны', Icons.trending_up, AppColors.good, [for (final k in strong) Skills.all[k] ?? k])),
              const SizedBox(width: 8),
              Expanded(child: _Column('Зоны роста', Icons.flag_outlined, AppColors.warn, [for (final k in weak) Skills.all[k] ?? k])),
              const SizedBox(width: 8),
              Expanded(child: _Column('Следующий шаг', Icons.my_location, AppColors.red, nextSteps)),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          'CoachPilot · ${AppBrand.clubName}${team == null ? '' : ' · ${team!.name}'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ]),
    );
  }
}

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');

class _Num extends StatelessWidget {
  const _Num(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontFamily: AppTheme.display, fontSize: 22, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]);
}

class _Column extends StatelessWidget {
  const _Column(this.title, this.icon, this.color, this.items);

  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(title.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 1, color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (items.isEmpty) const Text('—', style: TextStyle(color: AppColors.textMuted)),
        for (final i in items) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $i', style: const TextStyle(fontSize: 12.5))),
      ]);
}
