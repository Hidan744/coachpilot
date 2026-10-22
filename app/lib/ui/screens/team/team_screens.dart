import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../widgets/common.dart';
import '../../widgets/team_switcher.dart';
import 'import_players_screen.dart';
import 'team_dashboard.dart';
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

/// Взрослая команда игрока: у взрослых нет раздела для родителей.
final adultPlayerProvider = Provider.family<bool, String>((ref, playerId) {
  final player = ref.watch(playerProvider(playerId)).value;
  final teams = ref.watch(teamsProvider).value ?? const <Team>[];
  return teams.where((t) => t.id == player?.teamId).firstOrNull?.ageGroup == 'adult';
});

/// Есть ли у команды игрока работа с родителями (по типу команды).
final parentsEnabledProvider = Provider.family<bool, String>((ref, playerId) {
  final player = ref.watch(playerProvider(playerId)).value;
  final teams = ref.watch(teamsProvider).value ?? const <Team>[];
  return teams.where((t) => t.id == player?.teamId).firstOrNull?.hasParents ?? true;
});

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
  const TeamScreen({super.key, this.initialTab = 0});

  /// 0 — состав, 1 — дашборд, 2 — статистика.
  final int initialTab;

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

    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(team.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'excel':
                    exportTeamExcel(context, ref, team);
                  case 'demo':
                    fillTeamWithDemo(context, ref, team);
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
              itemBuilder: (_) => [
                if (ref.read(authProvider).demo) const PopupMenuItem(value: 'demo', child: Text('Заполнить демо-данными')),
                const PopupMenuItem(value: 'import', child: Text('Импорт игроков (Excel, Word)')),
                const PopupMenuItem(value: 'excel', child: Text('Выгрузить отчёт в Excel')),
                const PopupMenuItem(value: 'edit', child: Text('Изменить команду')),
                const PopupMenuItem(value: 'new', child: Text('Новая команда')),
                const PopupMenuItem(value: 'delete', child: Text('Удалить команду')),
              ],
            ),
            const SyncBadge(),
          ],
          // Если команд несколько — переключатель на виду, над вкладками.
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(teams.length > 1 ? 100 : 48),
            child: Column(children: [
              if (teams.length > 1) const TeamSwitcher(padding: EdgeInsets.fromLTRB(16, 4, 16, 8)),
              const TabBar(tabs: [Tab(text: 'Состав'), Tab(text: 'Дашборд'), Tab(text: 'Статистика')]),
            ]),
          ),
        ),
        floatingActionButton: Builder(
          // Кнопка «Игрок» — только на вкладке состава.
          builder: (context) {
            final tabs = DefaultTabController.of(context);
            return ListenableBuilder(
              listenable: tabs,
              builder: (context, _) => tabs.index != 0
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      key: const Key('add_player'),
                      onPressed: () => showPlayerForm(context, ref, teamId: team.id),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Игрок'),
                    ),
            );
          },
        ),
        body: TabBarView(children: [
          AsyncView(players, builder: (list) {
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
              if (list.isNotEmpty) _RosterList(players: list, attendance: attendance),
            ]);
          }),
          TeamDashboard(team: team),
          TeamStatsTable(team: team),
        ]),
      ),
    );
  }
}

/// Состав с поиском и фильтрами: по имени и номеру, по позиции, показывать ли выбывших.
class _RosterList extends StatefulWidget {
  const _RosterList({required this.players, required this.attendance});

  final List<Player> players;
  final List<Attendance> attendance;

  @override
  State<_RosterList> createState() => _RosterListState();
}

class _RosterListState extends State<_RosterList> {
  String _query = '';
  String? _position;
  bool _inactive = false;
  String _sort = 'number';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final p in widget.players)
        if ((_inactive || p.active) &&
            (_position == null || p.position == _position) &&
            (q.isEmpty || '${p.fullName} ${p.number ?? ''}'.toLowerCase().contains(q)))
          p,
    ]..sort((a, b) => switch (_sort) {
          'name' => a.fullName.compareTo(b.fullName),
          'attendance' => () {
              final (ap, at) = attendanceStats(widget.attendance, a.id);
              final (bp, bt) = attendanceStats(widget.attendance, b.id);
              return (bt == 0 ? -1 : bp / bt).compareTo(at == 0 ? -1 : ap / at);
            }(),
          _ => (a.number ?? 999).compareTo(b.number ?? 999),
        });
    final inactive = widget.players.where((p) => !p.active).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Поиск по имени или номеру', isDense: true),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
          for (final e in {null: 'Все', ...Positions.all}.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(e.value), selected: _position == e.key, onSelected: (_) => setState(() => _position = e.key)),
            ),
          if (inactive > 0)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(label: Text('Выбывшие ($inactive)'), selected: _inactive, onSelected: (v) => setState(() => _inactive = v)),
            ),
          PopupMenuButton<String>(
            tooltip: 'Сортировка',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'number', child: Text('По номеру')),
              PopupMenuItem(value: 'name', child: Text('По имени')),
              PopupMenuItem(value: 'attendance', child: Text('По посещаемости')),
            ],
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.sort)),
          ),
        ]),
      ),
      if (shown.isEmpty)
        const Padding(padding: EdgeInsets.all(16), child: Text('Никого не нашли — измените поиск или фильтр.')),
      for (final p in shown) _PlayerTile(player: p, stats: attendanceStats(widget.attendance, p.id)),
    ]);
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
  late String? _foot = widget.player?.dominantFoot;
  late String? _level = widget.player?.level;
  late final _strengths = TextEditingController(text: widget.player?.strengths);
  late final _weaknesses = TextEditingController(text: widget.player?.weaknesses);
  late final _goals = TextEditingController(text: widget.player?.goals);
  late bool _consent = widget.player?.consent.given ?? false;
  late final _consentBy = TextEditingController(text: widget.player?.consent.by);
  late final _consentNote = TextEditingController(text: widget.player?.consent.note);
  late DateTime? _consentOn = widget.player?.consent.on;
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
      dominantFoot: _foot,
      level: _level,
      strengths: _strengths.text.trim(),
      weaknesses: _weaknesses.text.trim(),
      goals: _goals.text.trim(),
      consent: ParentConsent(
        given: _consent,
        by: _consentBy.text.trim(),
        on: _consent ? (_consentOn ?? DateTime.now()) : null,
        note: _consentNote.text.trim(),
      ),
    );
    final old = widget.player;
    final change = old == null ? '' : Player.diff(old, p);
    final changes = [...?old?.changes, if (change.isNotEmpty) ProfileChange(DateTime.now(), change)];
    await ref.read(repoProvider).put(
          Entities.players,
          Player.fromJson(p.id, {...p.toJson(), 'changes': [for (final c in changes.skip(changes.length > 100 ? changes.length - 100 : 0)) c.toJson()]}),
        );
    if (widget.player == null) ref.read(analyticsProvider).track('player_added');
    if (!mounted) return;
    if (addAnother) {
      // Подсказка внутри формы, а не SnackBar: тот перекрывал бы кнопки панели.
      setState(() {
        _added.add(p.fullName);
        _first.clear();
        _last.clear();
        _number.clear();
        _strengths.clear();
        _weaknesses.clear();
        _goals.clear();
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
          // Подробный профиль — не обязателен, чтобы быстро добавлять состав.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: !isNew && (_foot != null || _level != null || _strengths.text.isNotEmpty || _goals.text.isNotEmpty),
            title: const Text('Профиль: нога, уровень, сильные стороны, цели'),
            children: [
              Align(alignment: Alignment.centerLeft, child: Text('Ведущая нога', style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final e in Feet.all.entries)
                  ChoiceChip(label: Text(e.value), selected: _foot == e.key, onSelected: (s) => setState(() => _foot = s ? e.key : null)),
              ]),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: Text('Уровень подготовки', style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in Levels.all.entries)
                  ChoiceChip(label: Text(e.value), selected: _level == e.key, onSelected: (s) => setState(() => _level = s ? e.key : null)),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _strengths,
                maxLines: 2,
                minLines: 1,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Сильные стороны', hintText: 'Скорость, игра левой, видение поля'),
              ),
              TextFormField(
                controller: _weaknesses,
                maxLines: 2,
                minLines: 1,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Зоны развития', hintText: 'Игра головой, слабая нога'),
              ),
              TextFormField(
                controller: _goals,
                maxLines: 2,
                minLines: 1,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Индивидуальные цели', hintText: 'Стабильно играть в основе к весне'),
              ),
            ],
          ),
          // Данные детей: ссылка родителям открывается только при отметке о согласии.
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _consent,
            leading: Icon(_consent ? Icons.verified_user_outlined : Icons.privacy_tip_outlined),
            title: Text(_consent ? 'Согласие родителя получено' : 'Согласие родителя на обработку данных'),
            subtitle: const Text('Нужно для детей и юношей; без него ссылка родителям не создаётся'),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (v) => setState(() {
                  _consent = v;
                  _consentOn ??= DateTime.now();
                }),
                title: const Text('Согласие получено'),
              ),
              if (_consent) ...[
                TextFormField(controller: _consentBy, maxLength: 100, decoration: const InputDecoration(labelText: 'Кто дал согласие (ФИО родителя)')),
                TextFormField(
                  controller: _consentNote,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Где хранится документ', hintText: 'Бумажный бланк в папке команды'),
                ),
              ],
            ],
          ),
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
