import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/export/plan_export.dart';
import '../../../core/export/save_file.dart';
import '../../../core/providers.dart';
import '../../../core/run_state.dart';
import '../../../core/session_summary.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../library/library_screens.dart';
import '../team/team_screens.dart';
import 'sessions_screens.dart';

final notesProvider = StreamProvider.family<List<SessionNote>, String>(
  (ref, sessionId) => ref.watch(repoProvider).watchNotes(sessionId).map((l) => l..sort((a, b) => a.notedAt.compareTo(b.notedAt))),
);

final reportProvider = StreamProvider.family<SessionReport?, String>(
  (ref, sessionId) => ref.watch(repoProvider).watchReports(sessionId).map((l) => l.isEmpty ? null : l.last),
);

final sessionAttendanceProvider = StreamProvider.family<List<Attendance>, String>(
  (ref, sessionId) => ref.watch(repoProvider).watchAttendance(sessionId),
);

// ---------------------------------------------------------------- отчёт

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  // Свой мессенджер: подсказки показываются над закреплёнными кнопками, а не поверх них.
  final _snacks = GlobalKey<ScaffoldMessengerState>();

  void _info(String msg) => _snacks.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  final _wentWell = TextEditingController();
  final _toImprove = TextEditingController();
  final _observations = TextEditingController();
  final _raw = TextEditingController();
  final _nextTime = TextEditingController();
  Map<String, String> _playerNotes = {};
  int? _rating;

  /// Нагрузка по ощущениям группы, RPE 1–10.
  int? _rpe;
  List<String> _suggestions = [];
  String? _id;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reports = await ref.read(repoProvider).list(Entities.reports, SessionReport.fromJson, parentId: widget.sessionId);
    final r = reports.isEmpty ? null : reports.last;
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (r == null) return;
      _id = r.id;
      _wentWell.text = r.wentWell;
      _toImprove.text = r.toImprove;
      _observations.text = r.observations;
      _raw.text = r.rawInput;
      _rating = r.rating;
      _rpe = r.rpe;
      _suggestions = [...r.aiSuggestions];
      _nextTime.text = r.nextTime;
      _playerNotes = {...r.playerNotes};
    });
  }

  Future<void> _save({required bool confirmed}) async {
    final report = SessionReport(
      id: _id ??= newId(),
      sessionId: widget.sessionId,
      rawInput: _raw.text.trim(),
      rating: _rating,
      wentWell: _wentWell.text.trim(),
      toImprove: _toImprove.text.trim(),
      observations: _observations.text.trim(),
      aiSuggestions: _suggestions,
      coachConfirmed: confirmed,
      confirmedAt: confirmed ? DateTime.now() : null,
      rpe: _rpe,
      playerNotes: {for (final e in _playerNotes.entries) if (e.value.trim().isNotEmpty) e.key: e.value.trim()},
      nextTime: _nextTime.text.trim(),
    );
    await ref.read(repoProvider).put(Entities.reports, report);
    if (confirmed) {
      ref.read(analyticsProvider).track('report_confirmed', {'ai_suggestions': _suggestions.length, 'rating': _rating});
    }
    if (!mounted) return;
    if (confirmed) {
      context.pushReplacement('/sessions/${widget.sessionId}/summary');
    } else {
      _info('Черновик отчёта сохранён');
    }
  }

  Future<void> _structure() async {
    final text = [_wentWell, _toImprove, _observations, _raw].map((c) => c.text.trim()).join();
    final notes = ref.read(notesProvider(widget.sessionId)).value ?? const [];
    if (text.isEmpty && notes.isEmpty) {
      _info('Напишите или надиктуйте хотя бы пару фраз о занятии');
      return;
    }
    if (ref.read(authProvider).demo) {
      _info('В демо-режиме AI-оформление недоступно — заполните разделы вручную.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _save(confirmed: false);
      await ref.read(syncEngineProvider).sync();
      final r = await ref.read(apiProvider).post('/ai/report', {
        'session_id': widget.sessionId,
        'raw_input': _raw.text.trim(),
        'went_well': _wentWell.text.trim(),
        'to_improve': _toImprove.text.trim(),
        'observations': _observations.text.trim(),
        'rating': _rating,
      }) as Json;
      if (!mounted) return;
      setState(() {
        _wentWell.text = r['went_well'] as String;
        _toImprove.text = r['to_improve'] as String;
        _observations.text = r['observations'] as String;
        _suggestions = (r['suggestions'] as List).cast<String>();
      });
      final warnings = (r['warnings'] as List).cast<String>();
      _info(warnings.isNotEmpty ? warnings.first : 'Готово. Проверьте текст и подтвердите отчёт.');
    } on ApiException catch (e) {
      if (mounted) {
        _info(e.isNetwork ? 'Нет связи: AI-оформление недоступно, заполните отчёт вручную — он сохранится на телефоне.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final t = Theme.of(context);
    final notes = ref.watch(notesProvider(widget.sessionId)).value ?? const [];
    Widget field(TextEditingController c, String label, {String? hint, int lines = 3}) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            controller: c,
            minLines: 2,
            maxLines: lines + 4,
            decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: true),
          ),
        );

    return ScaffoldMessenger(
      key: _snacks,
      child: Scaffold(
      appBar: AppBar(title: const Text('Отчёт о занятии')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          Text('Как прошло занятие?', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: 'Оценка $i',
                iconSize: 40,
                onPressed: () => setState(() => _rating = i),
                icon: Icon(i <= (_rating ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber.shade700),
              ),
          ]),
          const SizedBox(height: 8),
          Text('Нагрузка по ощущениям (RPE): ${_rpe == null ? 'не указана' : '$_rpe из 10'}', style: t.textTheme.titleSmall),
          Text('1 — очень легко, 5 — тяжело, 10 — максимально. Нужна для графика нагрузки команды.',
              style: t.textTheme.bodySmall),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var i = 1; i <= 10; i++)
              ChoiceChip(label: Text('$i'), selected: _rpe == i, onSelected: (v) => setState(() => _rpe = v ? i : null)),
          ]),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Заметки с занятия', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final n in notes) Text('• ${DateFormat('HH:mm').format(n.notedAt)} — ${n.text}'),
          ],
          field(_raw, 'Свободная заметка', hint: 'Можно надиктовать: микрофон на клавиатуре', lines: 5),
          field(_wentWell, 'Что получилось'),
          field(_toImprove, 'Что улучшить'),
          field(_observations, 'Наблюдения по группе'),
          field(_nextTime, 'Что изменить на следующей тренировке', hint: 'Меньше зона в рондо, больше игр 4×4'),
          const SizedBox(height: 16),
          _PlayerNotes(
            sessionId: widget.sessionId,
            notes: _playerNotes,
            onChanged: (m) => setState(() => _playerNotes = m),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('report_ai'),
            onPressed: _busy ? null : _structure,
            icon: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'AI оформляет отчёт…' : 'Оформить с AI'),
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              color: t.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.lightbulb_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Предложения AI на следующие занятия', style: t.textTheme.titleSmall)),
                  ]),
                  Text('Это предположения модели, а не ваши наблюдения. Уберите лишнее.', style: t.textTheme.bodySmall),
                  for (var i = 0; i < _suggestions.length; i++)
                    Row(children: [
                      Expanded(child: Text('• ${_suggestions[i]}')),
                      IconButton(
                        tooltip: 'Убрать',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _suggestions = [..._suggestions]..removeAt(i)),
                      ),
                    ]),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // Кнопки сохранения всегда видны, как бы ни был длинен отчёт.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _save(confirmed: false),
              child: const Text('Черновик', semanticsLabel: 'Сохранить черновик'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('report_confirm'),
                onPressed: _busy ? null : () => _save(confirmed: true),
                child: const Text('Подтвердить отчёт', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    ),
    );
  }
}

// ---------------------------------------------------------------- итог занятия (история)

class SessionSummaryScreen extends ConsumerWidget {
  const SessionSummaryScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(sessionProvider(sessionId));
    return AsyncView(value, builder: (s) {
      if (s == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'Тренировка удалена'));
      final t = Theme.of(context);
      final report = ref.watch(reportProvider(sessionId)).value;
      final notes = ref.watch(notesProvider(sessionId)).value ?? const [];
      final attendance = ref.watch(sessionAttendanceProvider(sessionId)).value ?? const [];
      final present = attendance.where((a) => a.status == 'present' || a.status == 'late').length;
      final actual = (s.actual['blocks'] as Map?)?.cast<String, dynamic>() ?? const {};
      final skipped = ((s.actual['skipped'] as List?) ?? const []).cast<String>().toSet();
      final totalSec = actual.values.fold<int>(0, (a, b) => a + (b as int));

      Widget section(String title, String text) => text.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(text, style: t.textTheme.bodyLarge),
              ]),
            );

      return Scaffold(
        appBar: AppBar(
          title: const Text('Итоги занятия'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                final names = {
                  for (final p in s.teamId == null ? const <Player>[] : ref.read(playersProvider(s.teamId!)).value ?? const <Player>[])
                    p.id: p.fullName,
                };
                final summary = summarizeSession(s, report, attendance);
                if (v == 'copy') {
                  await Clipboard.setData(ClipboardData(text: reportAsText(s, report, summary, names)));
                  if (context.mounted) showInfo(context, 'Отчёт скопирован');
                  return;
                }
                if (v == 'pdf') {
                  final bytes = await reportPdf(s, report, summary, names, await loadPdfFonts());
                  await saveFile(bytes, 'Otchet_${safeFileName(s.title)}.pdf', 'application/pdf');
                  if (context.mounted) showInfo(context, 'PDF отчёта готов: откройте, чтобы распечатать или отправить');
                  return;
                }
                if (v == 'repeat') {
                  final copy = TrainingSession.fromJson(newId(), {
                    ...s.toJson(),
                    'status': 'draft',
                    'scheduled_at': null,
                    'started_at': null,
                    'finished_at': null,
                    'actual': <String, dynamic>{},
                    'conflict_of': null,
                  });
                  await ref.read(repoProvider).put(Entities.sessions, copy);
                  if (context.mounted) context.push('/sessions/${copy.id}');
                } else if (v == 'plan') {
                  context.push('/sessions/${s.id}');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('Отчёт в PDF / печать')),
                PopupMenuItem(value: 'copy', child: Text('Скопировать отчёт текстом')),
                PopupMenuItem(value: 'repeat', child: Text('Повторить как новый план')),
                PopupMenuItem(value: 'plan', child: Text('Открыть план')),
              ],
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          ListTile(
            title: Text(s.title, style: t.textTheme.titleLarge),
            subtitle: Text([
              formatWhen(s.finishedAt ?? s.scheduledAt),
              if (totalSec > 0) 'факт ${(totalSec / 60).round()} из ${s.durationMin} мин',
              if (attendance.isNotEmpty) 'игроков: $present',
            ].join(' · ')),
          ),
          if (s.goal.isNotEmpty) section('Цель', s.goal),
          const SectionTitle('Блоки'),
          for (final b in s.blocks)
            ListTile(
              dense: true,
              // Нажатие — упражнение целиком: схема, как выполнять, на что обратить внимание.
              onTap: b.drillSnapshot == null || b.drillSnapshot!.steps.isEmpty && b.drillSnapshot!.scheme == null
                  ? null
                  : () => showDrillSheet(context, b.drillSnapshot!),
              leading: Icon(
                skipped.contains(b.id) ? Icons.remove_circle_outline : Icons.check_circle_outline,
                color: skipped.contains(b.id) ? t.disabledColor : phaseColors[b.phase],
              ),
              title: Text(b.title),
              trailing: Text(
                actual.containsKey(b.id) && !skipped.contains(b.id)
                    ? '${formatClock(Duration(seconds: actual[b.id] as int))} / ${b.durationMin}:00'
                    : skipped.contains(b.id)
                        ? 'пропущен'
                        : '${b.durationMin} мин',
              ),
            ),
          if (notes.isNotEmpty) ...[
            const SectionTitle('Заметки с поля'),
            for (final n in notes)
              ListTile(dense: true, leading: Text(DateFormat('HH:mm').format(n.notedAt)), title: Text(n.text)),
          ],
          SectionTitle(
            'Отчёт',
            trailing: TextButton(
              onPressed: () => context.push('/sessions/${s.id}/report'),
              child: Text(report == null ? 'Заполнить' : 'Изменить'),
            ),
          ),
          if (report == null)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Отчёт ещё не заполнен.'))
          else ...[
            if (!report.coachConfirmed)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Черновик — не подтверждён тренером')),
            if (report.rating != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Text('Оценка  ', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  for (var i = 1; i <= 5; i++)
                    Icon(i <= report.rating! ? Icons.star : Icons.star_border, color: Colors.amber.shade700, size: 22),
                ]),
              ),
            if (report.rpe != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Нагрузка: RPE ${report.rpe} из 10', style: t.textTheme.titleSmall),
              ),
            section('Что получилось', report.wentWell),
            section('Что улучшить', report.toImprove),
            section('Наблюдения', report.observations),
            section('Что изменить в следующий раз', report.nextTime),
            if (report.playerNotes.isNotEmpty)
              section(
                'По игрокам',
                [
                  for (final e in report.playerNotes.entries)
                    '• ${(s.teamId == null ? null : (ref.watch(playersProvider(s.teamId!)).value ?? const <Player>[]).where((p) => p.id == e.key).firstOrNull)?.fullName ?? 'Игрок'}: ${e.value}',
                ].join('\n'),
              ),
            if (report.aiSuggestions.isNotEmpty)
              section('Предложения AI (не наблюдения тренера)', report.aiSuggestions.map((e) => '• $e').join('\n')),
          ],
          _SummaryCard(summary: summarizeSession(s, report, attendance)),
          if (s.teamId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.how_to_reg_outlined),
                label: Text(attendance.isEmpty ? 'Отметить посещаемость' : 'Посещаемость: $present'),
                onPressed: () => context.push('/attendance/${s.id}?team=${s.teamId}'),
              ),
            ),
        ]),
      );
    });
  }
}


/// Комментарии по игрокам: кто был на занятии (или вся команда) — короткая заметка каждому, кому нужно.
class _PlayerNotes extends ConsumerWidget {
  const _PlayerNotes({required this.sessionId, required this.notes, required this.onChanged});

  final String sessionId;
  final Map<String, String> notes;
  final ValueChanged<Map<String, String>> onChanged;

  Future<void> _edit(BuildContext context, Player p) async {
    final c = TextEditingController(text: notes[p.id]);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(p.fullName),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Например: активен в отборе, но поздно открывается под передачу'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true) onChanged({...notes, p.id: c.text.trim()}..removeWhere((_, v) => v.isEmpty));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider(sessionId)).value;
    if (s?.teamId == null) return const SizedBox.shrink();
    final all = ref.watch(playersProvider(s!.teamId!)).value ?? const <Player>[];
    final att = ref.watch(sessionAttendanceProvider(sessionId)).value ?? const <Attendance>[];
    final was = {for (final a in att) if (a.status == 'present' || a.status == 'late') a.playerId};
    final players = [for (final p in all) if (p.active && (was.isEmpty || was.contains(p.id) || notes.containsKey(p.id))) p];
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Комментарии по игрокам', style: t.textTheme.titleSmall),
      Text(was.isEmpty ? 'Нажмите на игрока, чтобы оставить заметку.' : 'Игроки, отмеченные на занятии. Нажмите, чтобы оставить заметку.',
          style: t.textTheme.bodySmall),
      const SizedBox(height: 6),
      for (final p in players.where((p) => notes.containsKey(p.id)))
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.comment_outlined, color: AppColors.good),
          title: Text(p.fullName),
          subtitle: Text(notes[p.id]!),
          onTap: () => _edit(context, p),
          trailing: IconButton(
            tooltip: 'Удалить заметку',
            icon: const Icon(Icons.close),
            onPressed: () => onChanged({...notes}..remove(p.id)),
          ),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in players.where((p) => !notes.containsKey(p.id)))
          ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(p.lastName.isEmpty ? p.firstName : p.lastName), onPressed: () => _edit(context, p)),
      ]),
    ]);
  }
}


/// Сводка: выполнено, не выполнено, проблемы, что сделать дальше — с основанием каждого пункта.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget group(String title, IconData icon, Color color, List<SummaryItem> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]),
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 2),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: i.text),
                    if (i.basis.isNotEmpty) TextSpan(text: '  · ${i.basis}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ])),
                ),
            ]),
          );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Сводка по занятию', style: t.textTheme.titleMedium),
          group('Что произошло', Icons.check_circle_outline, AppColors.good, [...summary.achieved, ...summary.notDone]),
          group(
            'Что это означает',
            Icons.lightbulb_outline,
            AppColors.warn,
            summary.problems.isNotEmpty || summary.achieved.isEmpty
                ? summary.problems
                : const [SummaryItem('Занятие прошло без отклонений от плана', basis: 'факт и отчёт')],
          ),
          group('Что делать дальше', Icons.arrow_forward, AppColors.red, summary.next),
          if (summary.focus != null) group('На чём сосредоточиться на следующей тренировке', Icons.center_focus_strong, AppColors.red, [summary.focus!]),
          group('Не хватает данных', Icons.info_outline, AppColors.textMuted, [for (final m in summary.missingData) SummaryItem(m)]),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/team/advice'),
              icon: const Icon(Icons.rule, size: 18),
              label: const Text('Все рекомендации: принять или отклонить'),
            ),
          ),
        ]),
      ),
    );
  }
}
