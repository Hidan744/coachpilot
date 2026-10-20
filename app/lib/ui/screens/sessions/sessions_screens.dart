import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/plan_rules.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../library/library_screens.dart';

final sessionsProvider = StreamProvider<List<TrainingSession>>(
  (ref) => ref.watch(repoProvider).watchSessions(),
);

final sessionProvider = StreamProvider.family<TrainingSession?, String>(
  (ref, id) => ref.watch(repoProvider).watchOne(Entities.sessions, id, TrainingSession.fromJson),
);

String formatWhen(DateTime? d) => d == null ? 'Без даты' : DateFormat('EEE, d MMM, HH:mm', 'ru').format(d);

const phaseColors = {
  'warmup': Color(0xFFFFB300),
  'main': Color(0xFFE30613),
  'game': Color(0xFF4CD27A),
  'cooldown': Color(0xFF9E9EAA),
};

// ---------------------------------------------------------------- список

class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key, this.embedded = false});

  /// Внутри вкладки «Календарь»: без собственной шапки.
  final bool embedded;

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  String _tab = 'upcoming';

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);
    final teams = {for (final t in ref.watch(teamsProvider).value ?? <Team>[]) t.id: t};
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Тренировки'), actions: const [SyncBadge()]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'manual',
          tooltip: 'Создать вручную',
          onPressed: () => createManualSession(context, ref),
          child: const Icon(Icons.edit_note),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'ai',
          onPressed: () => context.push('/sessions/new'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Создать с AI'),
        ),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upcoming', label: Text('План')),
              ButtonSegment(value: 'drafts', label: Text('Черновики')),
              ButtonSegment(value: 'done', label: Text('История')),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: AsyncView(sessions, builder: (all) {
            final list = all.where((s) => switch (_tab) {
                  'drafts' => s.status == 'draft',
                  'done' => s.status == 'done' || s.status == 'cancelled',
                  _ => s.status == 'planned' || s.status == 'in_progress',
                }).toList()
              ..sort((a, b) {
                final da = a.scheduledAt ?? a.finishedAt ?? DateTime(2100);
                final db = b.scheduledAt ?? b.finishedAt ?? DateTime(2100);
                return _tab == 'done' ? db.compareTo(da) : da.compareTo(db);
              });
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.event_note_outlined,
                title: switch (_tab) {
                  'drafts' => 'Черновиков нет',
                  'done' => 'Проведённых тренировок пока нет',
                  _ => 'Запланированных тренировок нет',
                },
                text: _tab == 'upcoming' ? 'Создайте план с AI за минуту или соберите вручную из библиотеки.' : null,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 160),
              itemCount: list.length,
              itemBuilder: (_, i) => SessionTile(list[i], team: teams[list[i].teamId]),
            );
          }),
        ),
      ]),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile(this.s, {super.key, this.team});

  final TrainingSession s;
  final Team? team;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          child: Icon(switch (s.status) {
            'done' => Icons.check,
            'in_progress' => Icons.timer_outlined,
            'draft' => Icons.edit_outlined,
            _ => Icons.sports_soccer,
          }),
        ),
        title: Text(s.title),
        subtitle: Text([
          formatWhen(s.scheduledAt ?? s.finishedAt),
          if (team != null) team!.name,
          '${s.durationMin} мин',
          if (s.conflictOf != null) 'копия из-за конфликта',
        ].join(' · ')),
        trailing: s.aiGenerated ? const Icon(Icons.auto_awesome, size: 18) : null,
        onTap: () => context.push(s.status == 'done' ? '/sessions/${s.id}/summary' : '/sessions/${s.id}'),
      );
}

Future<void> createManualSession(BuildContext context, WidgetRef ref) async {
  final team = ref.read(currentTeamProvider);
  final s = TrainingSession(
    id: newId(),
    teamId: team?.id,
    title: 'Новая тренировка',
    durationMin: 60,
    playersExpected: team?.defaultPlayers,
    equipment: team?.equipment ?? const [],
    scheduledAt: _nextSlot(),
  );
  await ref.read(repoProvider).put(Entities.sessions, s);
  if (context.mounted) context.push('/sessions/${s.id}');
}

DateTime _nextSlot() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, 18);
}

// ---------------------------------------------------------------- мастер AI

const goalSuggestions = [
  'Передачи и открывания',
  'Удары по воротам',
  'Обводка и игра 1×1',
  'Владение мячом',
  'Оборона и отбор',
  'Переходы и контратаки',
];

const focusLabels = {'technique': 'Техника', 'tactics': 'Тактика', 'physical': 'Физика', 'game': 'Игра'};

class AiWizardScreen extends ConsumerStatefulWidget {
  const AiWizardScreen({super.key});

  @override
  ConsumerState<AiWizardScreen> createState() => _AiWizardScreenState();
}

class _AiWizardScreenState extends ConsumerState<AiWizardScreen> {
  final _goal = TextEditingController();
  final _constraints = TextEditingController();
  Team? _team;
  int _players = 14;
  int _duration = 75;
  String? _field = 'half';
  Set<String> _equipment = {'balls', 'cones', 'bibs'};
  final Set<String> _focus = {};
  DateTime? _when = _nextSlot();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = ref.read(currentTeamProvider);
    if (t != null) _applyTeam(t);
  }

  void _applyTeam(Team t) {
    _team = t;
    _players = t.defaultPlayers;
    _equipment = {...t.equipment, 'balls', 'cones'};
  }

  Map<String, dynamic> _request({String answer = '', bool useAi = true}) => {
        'team_id': _team?.id,
        'age_group': _team?.ageGroup ?? 'U12',
        'level': _team?.level ?? 'amateur',
        'players': _players,
        'duration_min': _duration,
        'goal': _goal.text.trim(),
        'field_type': _field,
        'equipment': _equipment.toList(),
        'focus': _focus.toList(),
        'constraints': _constraints.text.trim(),
        'answer': answer,
        'use_ai': useAi,
      };

  Future<void> _generate({String answer = ''}) async {
    if (_goal.text.trim().length < 3) {
      showInfo(context, 'Опишите цель занятия — от неё зависит подбор упражнений');
      return;
    }
    if (ref.read(authProvider).demo) return _offline();
    setState(() => _busy = true);
    final started = DateTime.now();
    try {
      // Команда должна быть на сервере, чтобы AI учёл историю её занятий.
      await ref.read(syncEngineProvider).sync();
      final resp = await ref.read(apiProvider).post('/ai/plan', _request(answer: answer)) as Json;
      ref.read(analyticsProvider).track('ai_plan_generated', {
        'source': resp['source'],
        'ms': DateTime.now().difference(started).inMilliseconds,
        'warnings': (resp['warnings'] as List).length,
        'clarifying': resp['clarifying_question'] != null,
      });
      if (!mounted) return;
      final question = resp['clarifying_question'] as String?;
      if (question != null && (resp['blocks'] as List).isEmpty) {
        final a = await _ask(question);
        if (a != null && a.isNotEmpty) await _generate(answer: [answer, a].where((s) => s.isNotEmpty).join('\n'));
        return;
      }
      await _saveDraft(
        blocks: (resp['blocks'] as List).map((b) => TrainingBlock.fromJson(b as Json)).toList(),
        title: resp['title'] as String,
        assumptions: (resp['assumptions'] as List).cast<String>(),
        warnings: (resp['warnings'] as List).cast<String>(),
        ai: resp['source'] == 'ai',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        final offline = await confirm(context, 'Нет связи с сервером',
            text: 'AI-генерация работает через интернет. Собрать план из библиотеки на телефоне без AI?',
            ok: 'Собрать без AI');
        if (offline) await _offline();
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offline() async {
    if (_goal.text.trim().length < 3) {
      showInfo(context, 'Опишите цель занятия');
      return;
    }
    final library = await ref.read(repoProvider).list(Entities.drills, Drill.fromJson);
    final team = _team ??
        Team(id: '', name: '', ageGroup: 'U12', level: 'amateur', defaultPlayers: _players, equipment: _equipment.toList());
    final blocks = planByRules(
      library: library,
      team: team,
      players: _players,
      durationMin: _duration,
      goal: _goal.text.trim(),
      equipment: _equipment.toList(),
      focus: _focus.toList(),
    );
    if (blocks.isEmpty) {
      if (mounted) showInfo(context, 'В библиотеке нет подходящих упражнений — ослабьте требования к инвентарю.');
      return;
    }
    ref.read(analyticsProvider).track('ai_plan_generated', {'source': 'offline_rules'});
    await _saveDraft(
      blocks: blocks,
      title: _goal.text.trim(),
      assumptions: const ['План собран по правилам из библиотеки, без AI.'],
      warnings: const [],
      ai: false,
    );
  }

  Future<void> _saveDraft({
    required List<TrainingBlock> blocks,
    required String title,
    required List<String> assumptions,
    required List<String> warnings,
    required bool ai,
  }) async {
    final s = TrainingSession(
      id: newId(),
      teamId: _team?.id,
      title: title.isEmpty ? 'Тренировка' : title,
      goal: _goal.text.trim(),
      durationMin: _duration,
      playersExpected: _players,
      fieldType: _field,
      equipment: _equipment.toList(),
      scheduledAt: _when,
      aiGenerated: ai,
      aiAssumptions: [...assumptions, ...warnings.map((w) => '⚠ $w')],
      blocks: blocks,
    );
    await ref.read(repoProvider).put(Entities.sessions, s);
    // Исходный вариант AI — чтобы измерить, насколько тренер правит план (метрика качества AI).
    await ref.read(dbProvider).setKv('ai_original:${s.id}', jsonEncode(blocks.map(_blockSig).toList()));
    if (mounted) context.pushReplacement('/sessions/${s.id}');
  }

  Future<String?> _ask(String question) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('AI уточняет'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(question),
          const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Ваш ответ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Продолжить')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final label = t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(title: const Text('Тренировка с AI')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          if (teams.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _team?.id,
              decoration: const InputDecoration(labelText: 'Команда'),
              items: [for (final x in teams) DropdownMenuItem(value: x.id, child: Text('${x.name} · ${AgeGroups.label(x.ageGroup)}'))],
              onChanged: (id) => setState(() => _applyTeam(teams.firstWhere((x) => x.id == id))),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _goal,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Цель занятия', hintText: 'Например: передачи в одно касание под давлением'),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final g in goalSuggestions)
              ActionChip(label: Text(g), onPressed: () => setState(() => _goal.text = g)),
          ]),
          const SizedBox(height: 16),
          Text('Длительность: $_duration мин', style: label),
          Slider(value: _duration.toDouble(), min: 30, max: 120, divisions: 18, label: '$_duration', onChanged: (v) => setState(() => _duration = v.round())),
          Text('Игроков на занятии: $_players', style: label),
          Slider(value: _players.toDouble(), min: 4, max: 30, divisions: 26, label: '$_players', onChanged: (v) => setState(() => _players = v.round())),
          Text('Площадка', style: label),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in const {'full': 'Всё поле', 'half': 'Половина поля', 'third': 'Треть поля', 'box': 'Мини-поле / зал'}.entries)
              ChoiceChip(label: Text(e.value), selected: _field == e.key, onSelected: (_) => setState(() => _field = e.key)),
          ]),
          const SizedBox(height: 16),
          Text('Инвентарь', style: label),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Equipment.all.entries)
              FilterChip(
                label: Text(e.value),
                selected: _equipment.contains(e.key),
                onSelected: (v) => setState(() => v ? _equipment.add(e.key) : _equipment.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 16),
          Text('Акцент (необязательно)', style: label),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final e in focusLabels.entries)
              FilterChip(
                label: Text(e.value),
                selected: _focus.contains(e.key),
                onSelected: (v) => setState(() => v ? _focus.add(e.key) : _focus.remove(e.key)),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _constraints,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Контекст и ограничения',
              hintText: 'Матч в субботу; двое после болезни; что не получилось в прошлый раз',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(formatWhen(_when)),
            subtitle: const Text('Дата и время'),
            onTap: () async {
              final d = await pickDateTime(context, _when);
              if (d != null) setState(() => _when = d);
            },
          ),
          const SizedBox(height: 16),
          Text(
            ref.watch(authProvider).demo
                ? 'Демо-режим: план собирается из библиотеки по правилам, без AI. '
                    'С аккаунтом план составляет AI с учётом истории команды.'
                : 'AI предложит черновик плана из упражнений библиотеки. Вы сможете изменить любой блок. '
                    'Имена игроков в AI не передаются.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('ai_generate'),
            onPressed: _busy ? null : () => _generate(),
            icon: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'AI составляет план…' : 'Сгенерировать план'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _offline,
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Собрать из библиотеки без AI'),
          ),
        ]),
      ),
    );
  }
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: now.subtract(const Duration(days: 365)),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial ?? DateTime(2000, 1, 1, 18)));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

// ---------------------------------------------------------------- редактор плана

class PlanEditorScreen extends ConsumerWidget {
  const PlanEditorScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(sessionProvider(sessionId));
    return AsyncView(value, builder: (s) {
      if (s == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'Тренировка удалена'));
      return _PlanEditor(s);
    });
  }
}

class _PlanEditor extends ConsumerWidget {
  const _PlanEditor(this.s);

  final TrainingSession s;

  Future<void> _save(WidgetRef ref, TrainingSession next) => ref.read(repoProvider).put(Entities.sessions, next);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final team = teams.where((x) => x.id == s.teamId).firstOrNull;
    final planned = s.plannedMinutes;
    final diff = planned - s.durationMin;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.status == 'draft' ? 'Черновик плана' : 'План тренировки'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'duplicate':
                  final copy = TrainingSession.fromJson(newId(), {
                    ...s.toJson(),
                    'status': 'draft',
                    'title': '${s.title} (копия)',
                    'started_at': null,
                    'finished_at': null,
                    'actual': <String, dynamic>{},
                    'conflict_of': null,
                  });
                  await ref.read(repoProvider).put(Entities.sessions, copy);
                  if (context.mounted) context.pushReplacement('/sessions/${copy.id}');
                case 'delete':
                  if (await confirm(context, 'Удалить тренировку?')) {
                    await ref.read(repoProvider).remove(Entities.sessions, s.id);
                    if (context.mounted) popOr(context, '/sessions');
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
              PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
        ListTile(
          title: Text(s.title, style: t.textTheme.titleLarge),
          subtitle: Text([formatWhen(s.scheduledAt), if (team != null) team.name].join(' · ')),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editHeader(context, ref, teams),
        ),
        if (s.goal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Цель: ${s.goal}', style: t.textTheme.bodyLarge),
          ),
        if (s.aiAssumptions.isNotEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            color: t.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(s.aiGenerated ? Icons.auto_awesome : Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Text(s.aiGenerated ? 'Предложение AI — проверьте и отредактируйте' : 'Как собран план',
                      style: t.textTheme.titleSmall),
                ]),
                const SizedBox(height: 6),
                for (final a in s.aiAssumptions) Text('• $a'),
              ]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            Expanded(child: Text('Блоки', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            _DurationBadge(planned: planned, target: s.durationMin),
          ]),
        ),
        if (diff != 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              diff > 0 ? 'План длиннее занятия на $diff мин' : 'До длительности занятия не хватает ${-diff} мин',
              style: const TextStyle(color: AppColors.warn),
            ),
          ),
        if (s.blocks.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Добавьте упражнения из библиотеки или пустые блоки.')),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final blocks = [...s.blocks];
            final b = blocks.removeAt(from);
            blocks.insert(to, b);
            _save(ref, s.copyWith(blocks: blocks));
          },
          children: [
            for (var i = 0; i < s.blocks.length; i++)
              _BlockCard(
                key: ValueKey(s.blocks[i].id),
                index: i,
                block: s.blocks[i],
                onChanged: (b) => _save(ref, s.copyWith(blocks: [...s.blocks]..[i] = b)),
                onDelete: () => _save(ref, s.copyWith(blocks: [...s.blocks]..removeAt(i))),
                onOpen: () => showBlockSheet(context, ref, s, i),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Из библиотеки'),
                onPressed: () async {
                  final d = await pickDrill(context);
                  if (d == null) return;
                  final phase = d.category == 'warmup'
                      ? 'warmup'
                      : d.category == 'cooldown'
                          ? 'cooldown'
                          : d.category == 'game'
                              ? 'game'
                              : 'main';
                  await _save(ref, s.copyWith(blocks: [
                    ...s.blocks,
                    TrainingBlock(id: newId(), phase: phase, title: d.title, durationMin: d.durationMin, drillId: d.id, drill: d.toJson()),
                  ]));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Пустой блок'),
                onPressed: () => _save(ref, s.copyWith(blocks: [
                  ...s.blocks,
                  TrainingBlock(id: newId(), phase: 'main', title: 'Блок', durationMin: 10),
                ])),
              ),
            ),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (s.teamId != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Посещаемость'),
                  onPressed: () => context.push('/attendance/${s.id}?team=${s.teamId}'),
                ),
              ),
            if (s.teamId != null) const SizedBox(width: 8),
            Expanded(
              child: s.status == 'draft'
                  ? FilledButton.icon(
                      key: const Key('plan_save'),
                      icon: const Icon(Icons.check),
                      label: const Text('Сохранить', maxLines: 1),
                      onPressed: s.blocks.isEmpty
                          ? null
                          : () async {
                              await _save(ref, s.copyWith(status: 'planned'));
                              await trackPlanSaved(ref, s);
                              if (context.mounted) showInfo(context, 'План сохранён и доступен офлайн');
                            },
                    )
                  : FilledButton.icon(
                      key: const Key('plan_run'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Провести'),
                      onPressed: s.blocks.isEmpty ? null : () => context.push('/run/${s.id}'),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _editHeader(BuildContext context, WidgetRef ref, List<Team> teams) async {
    final title = TextEditingController(text: s.title);
    final goal = TextEditingController(text: s.goal);
    var duration = s.durationMin;
    var when = s.scheduledAt;
    var teamId = s.teamId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Тренировка'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 12),
              TextField(controller: goal, decoration: const InputDecoration(labelText: 'Цель'), maxLines: 2, minLines: 1),
              const SizedBox(height: 12),
              if (teams.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: teamId,
                  decoration: const InputDecoration(labelText: 'Команда'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Без команды')),
                    for (final x in teams) DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (v) => set(() => teamId = v),
                ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Длительность'),
                const Spacer(),
                IconButton(onPressed: () => set(() => duration = (duration - 5).clamp(5, 300)), icon: const Icon(Icons.remove)),
                Text('$duration мин'),
                IconButton(onPressed: () => set(() => duration = (duration + 5).clamp(5, 300)), icon: const Icon(Icons.add)),
              ]),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatWhen(when)),
                onTap: () async {
                  final x = await pickDateTime(d, when);
                  if (x != null) set(() => when = x);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final json = s.toJson()
      ..['title'] = title.text.trim().isEmpty ? s.title : title.text.trim()
      ..['goal'] = goal.text.trim()
      ..['duration_min'] = duration
      ..['team_id'] = teamId
      ..['scheduled_at'] = when?.toUtc().toIso8601String();
    await ref.read(repoProvider).putJson(Entities.sessions, s.id, json);
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.planned, required this.target});

  final int planned, target;

  @override
  Widget build(BuildContext context) {
    final ok = planned == target;
    final color = ok ? AppColors.good : AppColors.warn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Text('Σ $planned / $target мин', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    super.key,
    required this.index,
    required this.block,
    required this.onChanged,
    required this.onDelete,
    required this.onOpen,
  });

  final int index;
  final TrainingBlock block;
  final ValueChanged<TrainingBlock> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = phaseColors[block.phase]!;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator)),
            ),
            Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Phases.all[block.phase]!, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                Text(block.title, style: Theme.of(context).textTheme.titleMedium),
                if (block.drill?['source'] == 'ai')
                  const Text('Новое упражнение от AI', style: TextStyle(fontSize: 12)),
              ]),
            ),
            IconButton(
              tooltip: 'Меньше',
              onPressed: block.durationMin > 1 ? () => onChanged(block.copyWith(durationMin: block.durationMin - 1)) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 44,
              child: Text('${block.durationMin}\nмин', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Больше',
              onPressed: () => onChanged(block.copyWith(durationMin: block.durationMin + 1)),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Карточка блока: упражнение, заметка, фаза, замена и удаление.
Future<void> showBlockSheet(BuildContext context, WidgetRef ref, TrainingSession s, int i) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (c, scroll) => _BlockSheet(session: s, index: i, scroll: scroll),
    ),
  );
}

class _BlockSheet extends ConsumerStatefulWidget {
  const _BlockSheet({required this.session, required this.index, required this.scroll});

  final TrainingSession session;
  final int index;
  final ScrollController scroll;

  @override
  ConsumerState<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends ConsumerState<_BlockSheet> {
  late TrainingBlock _b = widget.session.blocks[widget.index];
  late final _title = TextEditingController(text: _b.title);
  late final _notes = TextEditingController(text: _b.notes);

  Future<void> _save({bool close = true}) async {
    final blocks = [...widget.session.blocks];
    blocks[widget.index] = TrainingBlock(
      id: _b.id,
      phase: _b.phase,
      title: _title.text.trim().isEmpty ? _b.title : _title.text.trim(),
      durationMin: _b.durationMin,
      drillId: _b.drillId,
      drill: _b.drill,
      notes: _notes.text.trim(),
    );
    await ref.read(repoProvider).put(Entities.sessions, widget.session.copyWith(blocks: blocks));
    if (close && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final drill = _b.drillSnapshot;
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название блока')),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final e in Phases.all.entries)
          ChoiceChip(label: Text(e.value), selected: _b.phase == e.key, onSelected: (_) => setState(() => _b = _b.copyWith(phase: e.key))),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Заметка / адаптация к группе'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: FilledButton(onPressed: _save, child: const Text('Сохранить'))),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Заменить'),
          onPressed: () async {
            final d = await pickDrill(context);
            if (d == null) return;
            setState(() {
              _b = TrainingBlock(id: _b.id, phase: _b.phase, title: d.title, durationMin: _b.durationMin, drillId: d.id, drill: d.toJson(), notes: _notes.text);
              _title.text = d.title;
            });
          },
        ),
        IconButton(
          tooltip: 'Удалить блок',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final blocks = [...widget.session.blocks]..removeAt(widget.index);
            await ref.read(repoProvider).put(Entities.sessions, widget.session.copyWith(blocks: blocks));
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      if (drill != null && drill.source == 'ai' && drill.id == _b.id)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Сохранить упражнение в «Мои»'),
            onPressed: () async {
              final mine = Drill.fromJson(newId(), {...drill.toJson(), 'source': 'user'});
              await ref.read(repoProvider).put(Entities.drills, mine);
              if (context.mounted) showInfo(context, 'Упражнение добавлено в библиотеку');
            },
          ),
        ),
      const Divider(height: 32),
      if (drill != null) DrillDetails(drill) else const Text('Опишите задание в заметке или замените блок упражнением из библиотеки.'),
    ]);
  }
}


String _blockSig(TrainingBlock b) => '${b.drillId ?? b.title}|${b.durationMin}|${b.phase}';

/// Сколько блоков тренер изменил относительно предложения AI.
Future<void> trackPlanSaved(WidgetRef ref, TrainingSession s) async {
  final db = ref.read(dbProvider);
  final raw = await db.getKv('ai_original:${s.id}');
  final original = raw == null ? null : (jsonDecode(raw) as List).cast<String>();
  final now = s.blocks.map(_blockSig).toList();
  final edited = original == null
      ? null
      : now.where((x) => !original.contains(x)).length + original.where((x) => !now.contains(x)).length;
  await ref.read(analyticsProvider).track('plan_saved', {
    'ai': s.aiGenerated,
    'blocks': s.blocks.length,
    'edited': ?edited,
  });
  if (raw != null) await db.deleteKv('ai_original:${s.id}');
}
