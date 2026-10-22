import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/parent_report.dart';
import '../../../core/performance.dart';
import '../../../core/dev_weeks.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import 'team_screens.dart';

final devPlansProvider = StreamProvider.family<List<DevelopmentPlan>, String>(
  (ref, playerId) => ref.watch(repoProvider).watchDevPlans(playerId),
);

final parentNotesProvider = StreamProvider.family<List<ParentNote>, String>(
  (ref, playerId) => ref.watch(repoProvider).watchParentNotes(playerId),
);

String _range(DateTime? a, DateTime? b) {
  if (a == null && b == null) return '';
  final f = DateFormat('d MMM', 'ru');
  return '${a == null ? '…' : f.format(a)} – ${b == null ? '…' : f.format(b)}';
}

// ---------------------------------------------------------------- план развития

/// Блок «План развития» на экране игрока.
class DevelopmentSection extends ConsumerWidget {
  const DevelopmentSection(this.player, {super.key});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = [...ref.watch(devPlansProvider(player.id)).value ?? const <DevelopmentPlan>[]]
      ..sort((a, b) => (b.startsOn ?? DateTime(2000)).compareTo(a.startsOn ?? DateTime(2000)));
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'План развития',
        trailing: TextButton.icon(
          onPressed: () => context.push('/team/player/${player.id}/plan/new'),
          icon: const Icon(Icons.add),
          label: const Text('План'),
        ),
      ),
      if (plans.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Индивидуальные цели и задания на неделю или сезон: что отработать, сколько раз, '
            'на что обратить внимание. ${ref.watch(adultPlayerProvider(player.id)) ? 'Игрок увидит план в отчёте.' : 'Игрок и родители увидят план по ссылке.'}',
            style: t.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      for (final p in plans)
        Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: InkWell(
            onTap: () => context.push('/team/player/${player.id}/plan/${p.id}'),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(6)),
                    child: Text(PlanPeriods.all[p.period]!.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_range(p.startsOn, p.endsOn), style: t.textTheme.bodySmall)),
                  if (!p.shared) const Tooltip(message: 'Только для тренера', child: Icon(Icons.lock_outline, size: 16)),
                ]),
                const SizedBox(height: 6),
                Text(p.title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (p.keyGoal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Цель: ${p.keyGoal}', style: t.textTheme.bodySmall),
                  ),
                for (final x in p.targets.take(4)) TargetRow(x),
                if (p.items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: p.doneCount / p.items.length, minHeight: 6),
                  ),
                  const SizedBox(height: 4),
                  Text('Выполнено ${p.doneCount} из ${p.items.length}', style: t.textTheme.bodySmall),
                ],
              ]),
            ),
          ),
        ),
    ]);
  }
}

class DevPlanScreen extends ConsumerStatefulWidget {
  const DevPlanScreen({super.key, required this.playerId, this.planId});

  final String playerId;
  final String? planId;

  @override
  ConsumerState<DevPlanScreen> createState() => _DevPlanScreenState();
}

class _DevPlanScreenState extends ConsumerState<DevPlanScreen> {
  final _title = TextEditingController();
  final _comment = TextEditingController();
  final _keyGoal = TextEditingController();
  List<PlanTarget> _targets = [];
  final _newItem = TextEditingController();
  String _period = 'week';
  DateTime? _from, _to;
  final _focus = <String>{};
  List<PlanItem> _items = [];
  bool _shared = true;
  bool _loaded = false;
  String _newKind = 'task';
  List<PlanWeek> _weeks = [];
  int _perWeek = 2;
  int _minutes = 20;

  /// Составить понедельный план по выбранным навыкам, возрасту игрока и доступному времени.
  Future<void> _buildWeeks() async {
    final n = PlanPeriods.weeks(_period);
    if (n == null) return;
    if (_focus.isEmpty) return showInfo(context, 'Отметьте, над чем работаем — от этого зависят упражнения');
    if (_weeks.any((w) => w.done || w.comment.isNotEmpty) &&
        !await confirm(context, 'Пересоставить недели?', text: 'Отметки и комментарии по неделям будут заменены.', ok: 'Пересоставить')) {
      return;
    }
    final repo = ref.read(repoProvider);
    final player = await repo.get(Entities.players, widget.playerId, Player.fromJson);
    final library = await repo.list(Entities.drills, Drill.fromJson);
    if (!mounted) return;
    setState(() => _weeks = buildPlanWeeks(
          weeks: n,
          focus: _focus.toList(),
          library: library,
          age: player == null ? 12 : playerAge(player),
          sessionsPerWeek: _perWeek,
          minutes: _minutes,
        ));
  }

  Future<void> _editWeek(int i) async {
    final w = _weeks[i];
    final priority = TextEditingController(text: w.priority);
    final comment = TextEditingController(text: w.comment);
    var sessions = w.sessions;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Неделя ${w.n}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: priority, decoration: const InputDecoration(labelText: 'Приоритет недели'), maxLength: 200),
              Row(children: [
                const Expanded(child: Text('Занятий в неделю')),
                IconButton(onPressed: sessions > 0 ? () => set(() => sessions--) : null, icon: const Icon(Icons.remove_circle_outline)),
                Text('$sessions'),
                IconButton(onPressed: sessions < 7 ? () => set(() => sessions++) : null, icon: const Icon(Icons.add_circle_outline)),
              ]),
              TextField(
                controller: comment,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Комментарий: как прошла неделя, результат замера'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Готово')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _weeks[i] = w.copyWith(
          priority: priority.text.trim().isEmpty ? w.priority : priority.text.trim(),
          comment: comment.text.trim(),
          sessions: sessions,
        ));
  }

  @override
  void initState() {
    super.initState();
    if (widget.planId == null) {
      _setPeriod('week');
      _loaded = true;
    } else {
      ref.read(repoProvider).get(Entities.devPlans, widget.planId!, DevelopmentPlan.fromJson).then((p) {
        if (p == null || !mounted) return;
        setState(() {
          _title.text = p.title;
          _comment.text = p.comment;
          _keyGoal.text = p.keyGoal;
          _targets = [...p.targets];
          _period = p.period;
          _from = p.startsOn;
          _to = p.endsOn;
          _focus.addAll(p.focus);
          _items = [...p.items];
          _shared = p.shared;
          _weeks = [...p.weeks];
          _loaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _comment.dispose();
    _keyGoal.dispose();
    _newItem.dispose();
    super.dispose();
  }

  void _setPeriod(String p) {
    final (a, b) = periodRange(p, DateTime.now());
    setState(() {
      _period = p;
      _from = a;
      _to = b;
    });
  }

  void _addItem() {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(PlanItem(text: text, kind: _newKind));
      _newItem.clear();
    });
  }

  Future<void> _save() async {
    if (_items.isNotEmpty || _newItem.text.trim().isNotEmpty) _addItem();
    final title = _title.text.trim().isEmpty
        ? (_focus.isEmpty ? 'План: ${PlanPeriods.all[_period]!.toLowerCase()}' : _focus.map((f) => Skills.all[f]).join(', '))
        : _title.text.trim();
    await ref.read(repoProvider).put(
          Entities.devPlans,
          DevelopmentPlan(
            id: widget.planId ?? newId(),
            playerId: widget.playerId,
            period: _period,
            title: title,
            startsOn: _from,
            endsOn: _to,
            focus: _focus.toList(),
            items: _items,
            comment: _comment.text.trim(),
            shared: _shared,
            keyGoal: _keyGoal.text.trim(),
            targets: _targets,
            weeks: PlanPeriods.weeks(_period) == null ? const [] : _weeks.take(PlanPeriods.weeks(_period)!).toList(),
          ),
        );
    if (mounted) popOr(context, '/team/player/${widget.playerId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final goals = [for (var i = 0; i < _items.length; i++) if (_items[i].kind == 'goal') i];
    final tasks = [for (var i = 0; i < _items.length; i++) if (_items[i].kind != 'goal') i];

    Widget item(int i) => CheckboxListTile(
          key: ValueKey('item_$i'),
          contentPadding: const EdgeInsets.only(left: 4),
          controlAffinity: ListTileControlAffinity.leading,
          value: _items[i].done,
          onChanged: (v) => setState(() => _items[i] = _items[i].copyWith(done: v ?? false)),
          title: Text(
            _items[i].text,
            style: _items[i].done ? const TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textMuted) : null,
          ),
          secondary: IconButton(
            tooltip: 'Убрать пункт',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _items.removeAt(i)),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.planId == null ? 'Новый план развития' : 'План развития'),
        actions: [
          if (widget.planId != null)
            IconButton(
              tooltip: 'Удалить план',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Удалить план?')) {
                  await ref.read(repoProvider).remove(Entities.devPlans, widget.planId!);
                  if (context.mounted) popOr(context, '/team/player/${widget.playerId}');
                }
              },
            ),
          TextButton(onPressed: _save, child: const Text('Сохранить')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final e in PlanPeriods.all.entries)
            ChoiceChip(label: Text(e.value), selected: _period == e.key, onSelected: (_) => _setPeriod(e.key)),
        ]),
        const SizedBox(height: 8),
        Text(_range(_from, _to), style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название (например, «Игра левой ногой»)')),
        const SizedBox(height: 12),
        TextField(
          controller: _keyGoal,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Ключевая цель (например, «Быстрее на первых метрах»)'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Показатели: сейчас → цель', style: t.textTheme.titleMedium)),
          TextButton.icon(
            onPressed: () async {
              final x = await editTarget(context, ref, widget.playerId);
              if (x != null) setState(() => _targets.add(x));
            },
            icon: const Icon(Icons.add),
            label: const Text('Показатель'),
          ),
        ]),
        if (_targets.isEmpty)
          Text('Например: бег 10 м 1,92 → 1,80 с; точных передач за игру 70% → 80%. Контрольные замеры — в конце цикла.',
              style: t.textTheme.bodySmall),
        for (var i = 0; i < _targets.length; i++)
          InkWell(
            onTap: () async {
              final x = await editTarget(context, ref, widget.playerId, initial: _targets[i]);
              if (x == null) return;
              setState(() => x.name.isEmpty ? _targets.removeAt(i) : _targets[i] = x);
            },
            child: TargetRow(_targets[i], detailed: true),
          ),
        const SizedBox(height: 16),
        Text('Над чем работаем', style: t.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in Skills.all.entries)
            FilterChip(
              label: Text(e.value),
              selected: _focus.contains(e.key),
              onSelected: (v) => setState(() => v ? _focus.add(e.key) : _focus.remove(e.key)),
            ),
        ]),
        if (PlanPeriods.weeks(_period) != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: Text(
                _weeks.isEmpty ? 'План по неделям' : 'По неделям: выполнено ${_weeks.where((w) => w.done).length} из ${_weeks.length}',
                style: t.textTheme.titleMedium,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<int>(
              value: _perWeek,
              items: [for (final n in [1, 2, 3, 4]) DropdownMenuItem(value: n, child: Text('$n доп. занятия в неделю'))],
              onChanged: (v) => setState(() => _perWeek = v!),
            ),
            DropdownButton<int>(
              value: _minutes,
              items: [for (final m in [15, 20, 30, 45]) DropdownMenuItem(value: m, child: Text('по $m мин'))],
              onChanged: (v) => setState(() => _minutes = v!),
            ),
            FilledButton.tonalIcon(
              onPressed: _buildWeeks,
              icon: const Icon(Icons.view_week_outlined),
              label: Text(_weeks.isEmpty ? 'Составить по неделям' : 'Пересоставить'),
            ),
          ]),
          if (_weeks.isEmpty)
            Text('Неделя за неделей: приоритет, упражнения из каталога, нагрузка, ориентир и как проверить прогресс. '
                'Сначала отметьте, над чем работаем.', style: t.textTheme.bodySmall),
          for (var i = 0; i < _weeks.length; i++)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Checkbox(value: _weeks[i].done, onChanged: (v) => setState(() => _weeks[i] = _weeks[i].copyWith(done: v ?? false))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 10),
                      Text('Неделя ${_weeks[i].n} · ${_weeks[i].priority}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (_weeks[i].drills.isNotEmpty) Text('Упражнения: ${_weeks[i].drills.join(', ')}'),
                      Text('${_weeks[i].sessions} занятия · ${_weeks[i].load}', style: t.textTheme.bodySmall),
                      if (_weeks[i].expected.isNotEmpty)
                        Text(_weeks[i].expected, style: t.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                      if (_weeks[i].criteria.isNotEmpty) Text('Как проверить: ${_weeks[i].criteria}', style: t.textTheme.bodySmall),
                      if (_weeks[i].comment.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Комментарий: ${_weeks[i].comment}', style: const TextStyle(color: AppColors.good)),
                        ),
                    ]),
                  ),
                  IconButton(tooltip: 'Изменить неделю', icon: const Icon(Icons.edit_note), onPressed: () => _editWeek(i)),
                ]),
              ),
            ),
          if (_weeks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Ориентиры — рекомендации, а не гарантированный результат: темп у каждого игрока свой.',
                  style: t.textTheme.bodySmall),
            ),
        ],
        const SizedBox(height: 16),
        if (goals.isNotEmpty) ...[
          Text('Цели', style: t.textTheme.titleMedium),
          for (final i in goals) item(i),
        ],
        if (tasks.isNotEmpty) ...[
          Text('Задания', style: t.textTheme.titleMedium),
          for (final i in tasks) item(i),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'task', label: Text('Задание')),
                  ButtonSegment(value: 'goal', label: Text('Цель')),
                ],
                selected: {_newKind},
                onSelectionChanged: (s) => setState(() => _newKind = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _newItem,
                decoration: InputDecoration(
                  labelText: _newKind == 'goal' ? 'Цель (например, «Уверенный приём левой»)' : 'Задание (например, «100 передач левой у стенки»)',
                  suffixIcon: IconButton(tooltip: 'Добавить пункт', onPressed: _addItem, icon: const Icon(Icons.add_circle)),
                ),
                onSubmitted: (_) => _addItem(),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _comment,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Комментарий тренера'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _shared,
          onChanged: (v) => setState(() => _shared = v),
          title: Text(ref.watch(adultPlayerProvider(widget.playerId)) ? 'Видно игроку' : 'Видно игроку и родителям'),
          subtitle: Text(ref.watch(adultPlayerProvider(widget.playerId))
              ? 'Попадёт в отчёт игрока'
              : 'Попадёт на страницу по ссылке и в сообщение для родителей'),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('Сохранить план')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- родителям

/// Блок «Родителям»: сообщения тренера, ссылка на страницу игрока и текст для мессенджера.
class ParentSection extends ConsumerWidget {
  const ParentSection(this.player, {super.key, required this.present, required this.total});

  final Player player;
  final int present, total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final notes = [...ref.watch(parentNotesProvider(player.id)).value ?? const <ParentNote>[]]
      ..sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        'Родителям',
        trailing: TextButton.icon(
          onPressed: () => showParentNoteForm(context, ref, player.id),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('Написать'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _share(context, ref),
              icon: const Icon(Icons.link),
              label: const Text('Ссылка для родителей'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Скопировать сообщение для родителей',
            onPressed: () => _copyText(context, ref),
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ]),
      ),
      if (!ref.watch(authProvider).demo) _FamilyAccess(player),
      if (notes.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Что важно знать родителям: питание, сон, настрой, дополнительные занятия. '
            'Родители видят посещаемость, план развития и ваши сообщения по ссылке.',
            style: t.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      for (final n in notes)
        Card(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: ListTile(
            title: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(6)),
                child: Text(ParentNoteCategories.all[n.category] ?? n.category, style: t.textTheme.labelSmall),
              ),
              const SizedBox(width: 8),
              Text(DateFormat('d MMM', 'ru').format(n.writtenAt), style: t.textTheme.bodySmall),
              const Spacer(),
              if (!n.shared) const Tooltip(message: 'Только для тренера', child: Icon(Icons.lock_outline, size: 16)),
            ]),
            subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(n.text)),
            onTap: () => showParentNoteForm(context, ref, player.id, note: n),
          ),
        ),
    ]);
  }

  Future<String> _message(WidgetRef ref) async {
    final repo = ref.read(repoProvider);
    final team = await repo.get(Entities.teams, player.teamId, Team.fromJson);
    return parentMessage(
      player: player,
      team: team,
      present: present,
      total: total,
      plans: await repo.list(Entities.devPlans, DevelopmentPlan.fromJson, parentId: player.id),
      notes: await repo.list(Entities.parentNotes, ParentNote.fromJson, parentId: player.id),
      coach: ref.read(authProvider).demo ? '' : ref.read(authProvider).name,
    );
  }

  Future<void> _copyText(BuildContext context, WidgetRef ref) async {
    final text = await _message(ref);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showInfo(context, 'Сообщение скопировано — вставьте его в чат с родителями');
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    if (ref.read(authProvider).demo) {
      final text = await _message(ref);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Для родителей'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('Ссылка на страницу игрока работает после регистрации: данные хранятся на сервере. '
                  'В демо-режиме можно отправить родителям текст:'),
              const SizedBox(height: 12),
              Text(text),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Закрыть')),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('Скопировать'),
            ),
          ],
        ),
      );
      return;
    }
    // Данные ребёнка открываются по ссылке только после отметки о согласии родителя.
    if (!player.consent.given && !ref.read(adultPlayerProvider(player.id))) {
      final by = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Согласие родителя'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('По ссылке видны данные ребёнка. Отметьте, что родитель дал согласие на их обработку '
                '(бумажный бланк или сообщение).'),
            const SizedBox(height: 12),
            TextField(controller: by, decoration: const InputDecoration(labelText: 'Кто дал согласие (ФИО родителя)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Согласие получено')),
          ],
        ),
      );
      if (ok != true) return;
      await ref.read(repoProvider).put(
            Entities.players,
            Player.fromJson(player.id, {
              ...player.toJson(),
              'parent_consent': ParentConsent(given: true, by: by.text.trim(), on: DateTime.now()).toJson(),
            }),
          );
    }
    if (!context.mounted) return;
    try {
      // Игрок и его данные должны дойти до сервера раньше, чем родитель откроет ссылку.
      await ref.read(syncEngineProvider).sync().timeout(const Duration(seconds: 20), onTimeout: () {});
      final r = await ref.read(apiProvider).post('/players/${player.id}/share') as Json;
      final url = r['url'] as String;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Ссылка для игрока и родителей'),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('По ссылке без входа в приложение видны посещаемость, оценки, план развития и ваши сообщения. '
                'Заметки «только для тренера» не показываются.'),
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(d);
                if (await confirm(context, 'Отключить ссылку?', text: 'Старая ссылка перестанет открываться.', ok: 'Отключить')) {
                  await ref.read(apiProvider).delete('/players/${player.id}/share');
                  if (context.mounted) showInfo(context, 'Ссылка отключена');
                }
              },
              child: const Text('Отключить'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (d.mounted) Navigator.pop(d);
                if (context.mounted) showInfo(context, 'Ссылка скопирована');
              },
              child: const Text('Скопировать'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) showInfo(context, e.message);
    }
  }
}

Future<void> showParentNoteForm(BuildContext context, WidgetRef ref, String playerId, {ParentNote? note}) async {
  var category = note?.category ?? 'general';
  var shared = note?.shared ?? true;
  final text = TextEditingController(text: note?.text);
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(note == null ? 'Сообщение родителям' : 'Сообщение', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in ParentNoteCategories.all.entries)
              ChoiceChip(label: Text(e.value), selected: category == e.key, onSelected: (_) => set(() => category = e.key)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: text,
            minLines: 3,
            maxLines: 8,
            autofocus: note == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Текст',
              hintText: switch (category) {
                'nutrition' => 'Например: завтрак за 2–3 часа до игры, больше воды в жару',
                'psychology' => 'Например: переживает после ошибок — поддержите, не ругайте за промахи',
                'extra_training' => 'Например: 15 минут жонглирования дома 3 раза в неделю',
                'health' => 'Например: после ушиба 3 дня без беговой нагрузки',
                'behavior' => 'Например: опаздывает на тренировки — помогите с режимом',
                _ => 'Что важно знать родителям',
              },
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: shared,
            onChanged: (v) => set(() => shared = v),
            title: const Text('Видно родителям'),
            subtitle: const Text('Выключите, чтобы оставить заметку только для себя'),
          ),
          Row(children: [
            if (note != null)
              TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Удалить')),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Сохранить')),
          ]),
        ]),
      ),
    ),
  );
  final repo = ref.read(repoProvider);
  if (res == 'delete' && note != null) {
    await repo.remove(Entities.parentNotes, note.id);
  } else if (res == 'save' && text.text.trim().isNotEmpty) {
    await repo.put(
      Entities.parentNotes,
      ParentNote(
        id: note?.id ?? newId(),
        playerId: playerId,
        category: category,
        text: text.text.trim(),
        writtenAt: note?.writtenAt ?? DateTime.now(),
        shared: shared,
      ),
    );
  }
}


/// Показатель программы: название, приоритет, «сейчас → цель» и полоса прогресса.
class TargetRow extends StatelessWidget {
  const TargetRow(this.t, {super.key, this.detailed = false});

  final PlanTarget t;
  final bool detailed;

  String _n(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ','));

  @override
  Widget build(BuildContext context) {
    final color = switch (t.priority) {
      'high' => AppColors.red,
      'low' => AppColors.good,
      _ => AppColors.warn,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (t.kind != 'other')
                TextSpan(text: '  ${PlanTarget.kinds[t.kind]}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ])),
          ),
          if (t.reached)
            const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check_circle, size: 16, color: AppColors.good)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(6)),
            child: Text(PlanTarget.priorities[t.priority] ?? '', style: TextStyle(fontSize: 11, color: color)),
          ),
        ]),
        const SizedBox(height: 2),
        Text(
          'Сейчас: ${_n(t.current)} · Цель: ${_n(t.target)} ${t.unit}${t.gap == null ? '' : ' · разрыв ${_n(double.parse(t.gap!.toStringAsFixed(2)))}'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (t.due != null)
          Text(
            'Срок: до ${DateFormat('dd.MM.yyyy').format(t.due!)}${t.overdue(DateTime.now()) ? ' — срок прошёл' : ''}',
            style: TextStyle(fontSize: 12, color: t.overdue(DateTime.now()) ? AppColors.warn : AppColors.textMuted),
          ),
        if (t.checkpoints.length >= 2)
          Text(
            'Динамика: ${t.checkpoints.map((c) => _n(c.value)).join(' → ')} ${t.unit}',
            style: const TextStyle(fontSize: 12),
          ),
        const SizedBox(height: 4),
        TargetBar(progress: t.progress, height: 7),
        if (detailed && t.measure.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Как измеряем: ${t.measure}', style: const TextStyle(fontSize: 12))),
        if (detailed && t.comment.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('Комментарий: ${t.comment}', style: const TextStyle(fontSize: 12))),
      ]),
    );
  }
}

/// Диалог показателя. Возвращает null при отмене и показатель с пустым названием — при удалении.
Future<PlanTarget?> editTarget(BuildContext context, WidgetRef ref, String playerId, {PlanTarget? initial}) async {
  final name = TextEditingController(text: initial?.name);
  final cur = TextEditingController(text: initial?.current?.toString().replaceAll('.', ','));
  final tgt = TextEditingController(text: initial?.target?.toString().replaceAll('.', ','));
  final unit = TextEditingController(text: initial?.unit);
  final measure = TextEditingController(text: initial?.measure);
  final comment = TextEditingController(text: initial?.comment);
  var priority = initial?.priority ?? 'medium';
  var kind = initial?.kind ?? 'other';
  var due = initial?.due;
  final checkpoints = [...?initial?.checkpoints];
  final pointValue = TextEditingController();
  final tests = (await ref.read(repoProvider).list(Entities.physicalTests, PhysicalTest.fromJson))
      .where((t) => t.playerId == playerId)
      .toList()
    ..sort((a, b) => a.testedOn.compareTo(b.testedOn));
  if (!context.mounted) return null;
  double? parse(String s) => double.tryParse(s.replaceAll(',', '.').trim());
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Показатель', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (initial == null)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in physicalMetrics)
                  ActionChip(
                    label: Text(m.label),
                    onPressed: () => set(() {
                      name.text = m.label;
                      unit.text = m.unit;
                      kind = 'physical';
                      final last = tests.where((t) => t.results[m.key] != null).lastOrNull;
                      if (last != null) cur.text = last.results[m.key].toString().replaceAll('.', ',');
                      measure.text = m.hint.isEmpty ? 'Контрольный тест в конце цикла' : m.hint;
                    }),
                  ),
                for (final x in const ['Точность передач, %', 'Удары в створ, %', 'Выигранные единоборства, %'])
                  ActionChip(
                    label: Text(x),
                    onPressed: () => set(() {
                      name.text = x.split(',').first;
                      unit.text = '%';
                      kind = x.startsWith('Выигранные') ? 'tactical' : 'technical';
                      measure.text = 'Статистика матчей за цикл';
                    }),
                  ),
              ]),
            const SizedBox(height: 8),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: cur, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Сейчас'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: tgt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Цель'))),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Ед.'))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final e in PlanTarget.priorities.entries)
                ChoiceChip(label: Text(e.value), selected: priority == e.key, onSelected: (_) => set(() => priority = e.key)),
            ]),
            const SizedBox(height: 8),
            Text('Вид цели', style: Theme.of(c).textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (final e in PlanTarget.kinds.entries)
                ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key)),
            ]),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(due == null ? 'Срок не задан' : 'Срок: ${DateFormat('d MMMM yyyy', 'ru').format(due!)}'),
              trailing: Wrap(children: [
                for (final w in const [4, 8, 12])
                  TextButton(
                    onPressed: () => set(() => due = DateTime.now().add(Duration(days: 7 * w))),
                    child: Text('$w нед.'),
                  ),
              ]),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: due ?? DateTime.now().add(const Duration(days: 28)),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (d != null) set(() => due = d);
              },
            ),
            Text('Контрольные замеры', style: Theme.of(c).textTheme.labelLarge),
            for (var i = 0; i < checkpoints.length; i++)
              Row(children: [
                Expanded(
                  child: Text('${DateFormat('dd.MM.yyyy').format(checkpoints[i].on)} — '
                      '${checkpoints[i].value.toString().replaceAll('.', ',')} ${unit.text}'),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => set(() => checkpoints.removeAt(i))),
              ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: pointValue,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Новый замер сегодня'),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Записать'),
                onPressed: () {
                  final v = parse(pointValue.text);
                  if (v == null) return;
                  set(() {
                    // Стартовое значение — первой точкой, чтобы видеть динамику от начала.
                    if (checkpoints.isEmpty && parse(cur.text) != null && parse(cur.text) != v) {
                      checkpoints.add(TargetCheckpoint(DateTime.now().subtract(const Duration(days: 1)), parse(cur.text)!, note: 'старт'));
                    }
                    checkpoints.add(TargetCheckpoint(DateTime.now(), v));
                    cur.text = pointValue.text;
                    pointValue.clear();
                  });
                },
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: measure, decoration: const InputDecoration(labelText: 'Как измеряем')),
            const SizedBox(height: 8),
            TextField(controller: comment, decoration: const InputDecoration(labelText: 'Комментарий')),
            const SizedBox(height: 12),
            Row(children: [
              if (initial != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Удалить')),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Готово')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (res == 'delete') return const PlanTarget(name: '');
  if (res != 'save' || name.text.trim().isEmpty) return null;
  return PlanTarget(
    name: name.text.trim(),
    current: parse(cur.text),
    target: parse(tgt.text),
    unit: unit.text.trim(),
    measure: measure.text.trim(),
    comment: comment.text.trim(),
    priority: priority,
    kind: kind,
    due: due,
    checkpoints: checkpoints,
  );
}


final _familyProvider = FutureProvider.autoDispose.family<List<dynamic>, String>(
  (ref, playerId) async => await ref.read(apiProvider).get('/players/$playerId/family') as List,
);

/// Аккаунты родителей и игрока: код для подключения и список, у кого есть доступ.
class _FamilyAccess extends ConsumerWidget {
  const _FamilyAccess(this.player);

  final Player player;

  Future<void> _code(BuildContext context, WidgetRef ref, String role) async {
    try {
      await ref.read(syncEngineProvider).sync().timeout(const Duration(seconds: 20), onTimeout: () {});
      final r = await ref.read(apiProvider).post('/players/${player.id}/invite', {'role': role}) as Json;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(role == 'parent' ? 'Код для родителя' : 'Код для игрока'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(r['code'] as String, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const SizedBox(height: 8),
            const Text('Родитель или игрок регистрируется в CoachPilot, выбирает «Родитель» или «Игрок» и вводит код. '
                'Код одноразовый, действует 7 дней.'),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: r['code'] as String));
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('Скопировать'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) showInfo(context, e.isNetwork ? 'Нужен интернет' : e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fam = ref.watch(_familyProvider(player.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _code(context, ref, 'parent'),
              icon: const Icon(Icons.family_restroom, size: 18),
              label: const Text('Код родителю'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _code(context, ref, 'player'),
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('Код игроку'),
            ),
          ),
        ]),
        for (final f in (fam.value ?? const []).cast<Json>())
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(f['role'] == 'parent' ? Icons.family_restroom : Icons.person_outline),
            title: Text('${f['name']} — ${f['role'] == 'parent' ? 'родитель' : 'игрок'}'),
            subtitle: const Text('Видит расписание и открытые для семьи материалы'),
            trailing: IconButton(
              tooltip: 'Отозвать доступ',
              icon: const Icon(Icons.link_off),
              onPressed: () async {
                if (!await confirm(context, 'Отозвать доступ у ${f['name']}?', ok: 'Отозвать')) return;
                await ref.read(apiProvider).delete('/players/${player.id}/family/${f['id']}');
                ref.invalidate(_familyProvider(player.id));
              },
            ),
          ),
      ]),
    );
  }
}
