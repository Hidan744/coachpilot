import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/parent_report.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

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
            'на что обратить внимание. Игрок и родители увидят план по ссылке.',
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
  final _newItem = TextEditingController();
  String _period = 'week';
  DateTime? _from, _to;
  final _focus = <String>{};
  List<PlanItem> _items = [];
  bool _shared = true;
  bool _loaded = false;
  String _newKind = 'task';

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
          _period = p.period;
          _from = p.startsOn;
          _to = p.endsOn;
          _focus.addAll(p.focus);
          _items = [...p.items];
          _shared = p.shared;
          _loaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _comment.dispose();
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
        SegmentedButton<String>(
          segments: [for (final e in PlanPeriods.all.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_period},
          onSelectionChanged: (s) => _setPeriod(s.first),
        ),
        const SizedBox(height: 8),
        Text(_range(_from, _to), style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название (например, «Игра левой ногой»)')),
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
          title: const Text('Видно игроку и родителям'),
          subtitle: const Text('Попадёт на страницу по ссылке и в сообщение для родителей'),
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
