import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../widgets/common.dart';
import 'import_players_screen.dart';
import 'team_form.dart';

final playersProvider = StreamProvider.family<List<Player>, String>(
  (ref, teamId) => ref.watch(repoProvider).watchPlayers(teamId).map(
        (l) => l..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase())),
      ),
);

final allAttendanceProvider = StreamProvider<List<Attendance>>(
  (ref) => ref.watch(repoProvider).watch(Entities.attendance, Attendance.fromJson),
);

final playerProvider = StreamProvider.family<Player?, String>(
  (ref, id) => ref.watch(repoProvider).watchOne(Entities.players, id, Player.fromJson),
);

final assessmentsProvider = StreamProvider.family<List<PlayerAssessment>, String>(
  (ref, playerId) => ref.watch(repoProvider).watchAssessments(playerId),
);

/// Посещаемость игрока: (был или опоздал, всего отметок).
(int, int) attendanceStats(Iterable<Attendance> all, String playerId) {
  var present = 0, total = 0;
  for (final a in all) {
    if (a.playerId != playerId) continue;
    if (a.status == 'excused') continue; // уважительная причина не портит статистику
    total++;
    if (a.status == 'present' || a.status == 'late') present++;
  }
  return (present, total);
}

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider).value ?? [];
    final team = ref.watch(currentTeamProvider);
    if (team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Команда')),
        body: EmptyState(
          icon: Icons.groups_outlined,
          title: 'Команд пока нет',
          action: FilledButton.icon(
            onPressed: () => context.push('/team/new'),
            icon: const Icon(Icons.add),
            label: const Text('Создать команду'),
          ),
        ),
      );
    }
    final players = ref.watch(playersProvider(team.id));
    final attendance = ref.watch(allAttendanceProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: teams.length > 1
            ? DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: team.id,
                  style: Theme.of(context).textTheme.titleLarge,
                  items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name))],
                  onChanged: (id) => ref.read(currentTeamIdProvider.notifier).select(id!),
                ),
              )
            : Text(team.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'import':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportPlayersScreen(teamId: team.id)));
                case 'edit':
                  context.push('/team/edit/${team.id}');
                case 'new':
                  context.push('/team/new');
                case 'delete':
                  if (await confirm(context, 'Удалить команду «${team.name}»?',
                      text: 'Игроки команды тоже будут удалены. Проведённые тренировки останутся в истории.')) {
                    final repo = ref.read(repoProvider);
                    for (final p in await repo.list(Entities.players, Player.fromJson, parentId: team.id)) {
                      await repo.remove(Entities.players, p.id);
                    }
                    await repo.remove(Entities.teams, team.id);
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Импорт игроков (Excel, Word)')),
              PopupMenuItem(value: 'edit', child: Text('Изменить команду')),
              PopupMenuItem(value: 'new', child: Text('Новая команда')),
              PopupMenuItem(value: 'delete', child: Text('Удалить команду')),
            ],
          ),
          const SyncBadge(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_player'),
        onPressed: () => showPlayerForm(context, ref, teamId: team.id),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Игрок'),
      ),
      body: AsyncView(players, builder: (list) {
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(label: Text(AgeGroups.label(team.ageGroup))),
              Chip(label: Text(Levels.all[team.level] ?? team.level)),
              Chip(label: Text('В составе: ${list.where((p) => p.active).length}')),
            ]),
          ),
          SectionTitle('Игроки'),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Добавьте игроков, чтобы отмечать посещаемость и вести карточки развития.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Загрузить список из Excel или Word'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ImportPlayersScreen(teamId: team.id)),
                  ),
                ),
              ]),
            ),
          for (final p in list) _PlayerTile(player: p, stats: attendanceStats(attendance, p.id)),
        ]);
      }),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({required this.player, required this.stats});

  final Player player;
  final (int, int) stats;

  @override
  Widget build(BuildContext context) {
    final (present, total) = stats;
    final pct = total == 0 ? null : (present * 100 / total).round();
    return ListTile(
      leading: CircleAvatar(child: Text(player.number?.toString() ?? player.firstName.characters.first.toUpperCase())),
      title: Text(player.fullName, style: TextStyle(color: player.active ? null : Theme.of(context).disabledColor)),
      subtitle: Text([
        if (player.position != null) Positions.all[player.position] ?? player.position!,
        if (player.birthYear != null) '${player.birthYear} г.р.',
        if (!player.active) 'не в составе',
      ].join(' · ')),
      trailing: pct == null ? null : Text('$pct%', style: Theme.of(context).textTheme.titleMedium),
      onTap: () => context.push('/team/player/${player.id}'),
    );
  }
}

Future<void> showPlayerForm(BuildContext context, WidgetRef ref, {required String teamId, Player? player}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _PlayerForm(teamId: teamId, player: player),
    ),
  );
}

class _PlayerForm extends ConsumerStatefulWidget {
  const _PlayerForm({required this.teamId, this.player});

  final String teamId;
  final Player? player;

  @override
  ConsumerState<_PlayerForm> createState() => _PlayerFormState();
}

class _PlayerFormState extends ConsumerState<_PlayerForm> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.player?.firstName);
  late final _last = TextEditingController(text: widget.player?.lastName);
  late final _year = TextEditingController(text: widget.player?.birthYear?.toString());
  late final _number = TextEditingController(text: widget.player?.number?.toString());
  late String? _position = widget.player?.position;
  late bool _active = widget.player?.active ?? true;
  final _firstFocus = FocusNode();
  final _added = <String>[];

  @override
  void dispose() {
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    if (!_form.currentState!.validate()) return;
    final p = Player(
      id: widget.player?.id ?? newId(),
      teamId: widget.teamId,
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      birthYear: int.tryParse(_year.text),
      number: int.tryParse(_number.text),
      position: _position,
      notes: widget.player?.notes ?? '',
      active: _active,
    );
    await ref.read(repoProvider).put(Entities.players, p);
    if (widget.player == null) ref.read(analyticsProvider).track('player_added');
    if (!mounted) return;
    if (addAnother) {
      // Подсказка внутри формы, а не SnackBar: тот перекрывал бы кнопки панели.
      setState(() {
        _added.add(p.fullName);
        _first.clear();
        _last.clear();
        _number.clear();
      });
      _firstFocus.requestFocus();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.player == null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Новый игрок' : 'Игрок', style: Theme.of(context).textTheme.titleLarge),
          if (_added.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Добавлены: ${_added.join(', ')}', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _first,
            focusNode: _firstFocus,
            autofocus: isNew,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Имя'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Введите имя' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Фамилия (необязательно)'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Год рождения'),
                validator: (v) {
                  if ((v ?? '').isEmpty) return null;
                  final y = int.tryParse(v!);
                  return y == null || y < 1940 || y > DateTime.now().year ? 'Неверный год' : null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _number,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Номер'),
                validator: (v) => (v ?? '').isEmpty || (int.tryParse(v!) ?? -1) >= 0 ? null : 'Число',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final e in Positions.all.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _position == e.key,
                onSelected: (s) => setState(() => _position = s ? e.key : null),
              ),
          ]),
          if (!isNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('В составе'),
            ),
          const SizedBox(height: 16),
          FilledButton(key: const Key('player_save'), onPressed: _save, child: const Text('Сохранить')),
          if (isNew) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => _save(addAnother: true), child: const Text('Сохранить и добавить ещё')),
          ],
        ]),
      ),
    );
  }
}

class TeamEditScreen extends ConsumerWidget {
  const TeamEditScreen({super.key, this.teamId});

  final String? teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = teamId == null ? null : (ref.watch(teamsProvider).value ?? []).where((t) => t.id == teamId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(team == null ? 'Новая команда' : 'Команда')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TeamForm(team: team, onSaved: (_) => context.pop()),
      ),
    );
  }
}

// ---------------------------------------------------------------- карточка игрока

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider(playerId));
    return AsyncView(player, builder: (p) {
      if (p == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, title: 'Игрок удалён'));
      final attendance = ref.watch(allAttendanceProvider).value ?? const [];
      final (present, total) = attendanceStats(attendance, p.id);
      final assessments = ref.watch(assessmentsProvider(p.id)).value ?? const [];
      final t = Theme.of(context);

      // Последняя оценка по каждому навыку и изменение относительно предыдущей.
      final bySkill = <String, List<PlayerAssessment>>{};
      for (final a in assessments) {
        bySkill.putIfAbsent(a.skill, () => []).add(a);
      }
      for (final l in bySkill.values) {
        l.sort((a, b) => b.assessedAt.compareTo(a.assessedAt));
      }

      return Scaffold(
        appBar: AppBar(title: Text(p.fullName), actions: [
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
        ]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addAssessment(context, ref, p),
          icon: const Icon(Icons.star_outline),
          label: const Text('Оценить'),
        ),
        body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: _Stat(label: 'Посещаемость', value: total == 0 ? '—' : '${(present * 100 / total).round()}%')),
              const SizedBox(width: 12),
              Expanded(child: _Stat(label: 'Занятий отмечено', value: '$total')),
            ]),
          ),
          ListTile(
            title: const Text('Данные'),
            subtitle: Text([
              if (p.position != null) Positions.all[p.position] ?? p.position!,
              if (p.birthYear != null) '${p.birthYear} г.р.',
              if (p.number != null) '№${p.number}',
              if (!p.active) 'не в составе',
            ].join(' · ').ifEmpty('Не указаны')),
          ),
          ListTile(
            title: const Text('Заметки тренера'),
            subtitle: Text(p.notes.ifEmpty('Нет заметок')),
            trailing: const Icon(Icons.edit_note),
            onTap: () => _editNotes(context, ref, p),
          ),
          const SectionTitle('Оценки навыков'),
          if (bySkill.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Оценок пока нет. Шкала 1–5, с датой и комментарием.')),
          for (final e in bySkill.entries)
            ListTile(
              title: Text(Skills.all[e.key] ?? e.key),
              subtitle: Text([
                DateFormat('d MMM yyyy', 'ru').format(e.value.first.assessedAt),
                if (e.value.first.comment.isNotEmpty) e.value.first.comment,
                if (e.value.length > 1) 'история: ${e.value.reversed.map((a) => a.score).join(' → ')}',
              ].join('\n')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.value.length > 1) _Trend(e.value.first.score - e.value[1].score),
                Text('${e.value.first.score}/5', style: t.textTheme.titleLarge),
              ]),
            ),
        ]),
      );
    });
  }

  Future<void> _editNotes(BuildContext context, WidgetRef ref, Player p) async {
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

  Future<void> _addAssessment(BuildContext context, WidgetRef ref, Player p) async {
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
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class _Trend extends StatelessWidget {
  const _Trend(this.delta);

  final int delta;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Icon(
          delta > 0 ? Icons.trending_up : (delta < 0 ? Icons.trending_down : Icons.trending_flat),
          color: delta > 0 ? Colors.green : (delta < 0 ? Colors.orange : null),
        ),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

// ---------------------------------------------------------------- посещаемость

/// Отметка посещаемости на занятие: одно касание переключает статус.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key, required this.sessionId, required this.teamId});

  final String sessionId;
  final String teamId;

  static const _cycle = ['present', 'absent', 'late', 'injured', 'excused'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final players = ref.watch(playersProvider(teamId));
    final marks = ref.watch(_sessionAttendanceProvider(sessionId)).value ?? const [];
    final byPlayer = {for (final a in marks) a.playerId: a.status};
    final present = byPlayer.values.where((s) => s == 'present' || s == 'late').length;

    Future<void> mark(Player p, String status) => ref.read(repoProvider).put(
          Entities.attendance,
          Attendance(id: attendanceId(sessionId, p.id), sessionId: sessionId, playerId: p.id, status: status),
        );

    return Scaffold(
      appBar: AppBar(title: Text('Посещаемость · $present')),
      body: AsyncView(players, builder: (list) {
        final active = list.where((p) => p.active).toList();
        if (active.isEmpty) {
          return const EmptyState(icon: Icons.person_add_alt, title: 'В команде нет игроков', text: 'Добавьте игроков на вкладке «Команда».');
        }
        return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.done_all),
              label: const Text('Отметить всех присутствующими'),
              onPressed: () async {
                for (final p in active) {
                  if (!byPlayer.containsKey(p.id)) await mark(p, 'present');
                }
              },
            ),
          ),
          for (final p in active)
            ListTile(
              title: Text(p.fullName),
              onTap: () {
                final cur = byPlayer[p.id];
                final next = cur == null ? 'present' : _cycle[(_cycle.indexOf(cur) + 1) % _cycle.length];
                mark(p, next);
              },
              trailing: _StatusChip(byPlayer[p.id]),
            ),
        ]);
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: () => popOr(context, '/sessions'), child: const Text('Готово')),
        ),
      ),
    );
  }
}

final _sessionAttendanceProvider = StreamProvider.family<List<Attendance>, String>(
  (ref, sessionId) => ref.watch(repoProvider).watchAttendance(sessionId),
);

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      'present' => Colors.green,
      'late' => Colors.amber.shade700,
      'absent' => cs.error,
      'injured' => Colors.purple,
      'excused' => Colors.blueGrey,
      _ => cs.outline,
    };
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: status == null ? 0.05 : 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        status == null ? 'Отметить' : AttendanceStatus.labels[status]!,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
