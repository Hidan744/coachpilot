import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/run_state.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../widgets/common.dart';
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
  final _wentWell = TextEditingController();
  final _toImprove = TextEditingController();
  final _observations = TextEditingController();
  final _raw = TextEditingController();
  int? _rating;
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
      _suggestions = [...r.aiSuggestions];
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
    );
    await ref.read(repoProvider).put(Entities.reports, report);
    if (!mounted) return;
    if (confirmed) {
      context.pushReplacement('/sessions/${widget.sessionId}/summary');
    } else {
      showInfo(context, 'Черновик отчёта сохранён');
    }
  }

  Future<void> _structure() async {
    final text = [_wentWell, _toImprove, _observations, _raw].map((c) => c.text.trim()).join();
    final notes = ref.read(notesProvider(widget.sessionId)).value ?? const [];
    if (text.isEmpty && notes.isEmpty) {
      showInfo(context, 'Напишите или надиктуйте хотя бы пару фраз о занятии');
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
      showInfo(context, warnings.isNotEmpty ? warnings.first : 'Готово. Проверьте текст и подтвердите отчёт.');
    } on ApiException catch (e) {
      if (mounted) {
        showInfo(context, e.isNetwork ? 'Нет связи: AI-оформление недоступно, заполните отчёт вручную — он сохранится на телефоне.' : e.message);
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

    return Scaffold(
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
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Заметки с занятия', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final n in notes) Text('• ${DateFormat('HH:mm').format(n.notedAt)} — ${n.text}'),
          ],
          field(_raw, 'Свободная заметка', hint: 'Можно надиктовать: микрофон на клавиатуре', lines: 5),
          field(_wentWell, 'Что получилось'),
          field(_toImprove, 'Что улучшить'),
          field(_observations, 'Наблюдения по игрокам и группе'),
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
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('report_confirm'),
            onPressed: _busy ? null : () => _save(confirmed: true),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Подтвердить отчёт'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : () => _save(confirmed: false), child: const Text('Сохранить черновик')),
        ]),
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
            section('Что получилось', report.wentWell),
            section('Что улучшить', report.toImprove),
            section('Наблюдения', report.observations),
            if (report.aiSuggestions.isNotEmpty)
              section('Предложения AI (не наблюдения тренера)', report.aiSuggestions.map((e) => '• $e').join('\n')),
          ],
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
