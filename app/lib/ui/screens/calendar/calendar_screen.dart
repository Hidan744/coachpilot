import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../sessions/sessions_screens.dart';
import '../tactics/tactics_screens.dart';

final matchesProvider = StreamProvider<List<Match>>((ref) => ref.watch(repoProvider).watchMatches());
final slotsProvider = StreamProvider<List<ScheduleSlot>>((ref) => ref.watch(repoProvider).watchSlots());

const _teamPalette = [
  AppColors.red,
  Color(0xFF4FC3F7),
  Color(0xFFFFCA28),
  Color(0xFF66BB6A),
  Color(0xFFBA68C8),
  Color(0xFF4DB6AC),
  Color(0xFFFF8A65),
  Color(0xFFF06292),
];

/// Цвет команды в календаре — по порядку команд, чтобы у каждой был свой.
Color teamColor(String? teamId, List<Team> teams) {
  final i = teams.indexWhere((t) => t.id == teamId);
  return i < 0 ? AppColors.textMuted : _teamPalette[i % _teamPalette.length];
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String hm(DateTime d) => DateFormat('HH:mm').format(d);

// ---------------------------------------------------------------- вкладка «Календарь»

/// Вкладка планирования: календарь сезона и список тренировок.
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  DateTime _day = dayOf(DateTime.now());

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Календарь'),
          actions: [
            IconButton(
              tooltip: 'Расписание тренировок',
              icon: const Icon(Icons.schedule),
              onPressed: () => context.push('/calendar/slots'),
            ),
            IconButton(
              tooltip: 'Тактическая доска',
              icon: const Icon(Icons.draw_outlined),
              onPressed: () => context.push('/tactics'),
            ),
            const SyncBadge(),
          ],
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Календарь'), Tab(text: 'Тренировки')]),
        ),
        floatingActionButton: _tabs.index == 0
            ? FloatingActionButton.extended(
                heroTag: 'cal_add',
                onPressed: () => _addMenu(context),
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              )
            : null,
        body: TabBarView(
          controller: _tabs,
          children: [
            CalendarView(day: _day, onDay: (d) => setState(() => _day = d)),
            const SessionsScreen(embedded: true),
          ],
        ),
      );

  Future<void> _addMenu(BuildContext context) async {
    // Выбор возвращается из шторки и выполняется один раз: двойное касание не открывает экран дважды.
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(DateFormat('d MMMM, EEEE', 'ru').format(_day), style: Theme.of(c).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.sports_soccer, color: AppColors.red),
              title: const Text('Матч'),
              subtitle: const Text('Соперник, дата, стадион'),
              onTap: () => Navigator.pop(c, 'match'),
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Регулярная тренировка'),
              subtitle: const Text('Например, U16 по пн и ср с 10:00 до 12:00'),
              onTap: () => Navigator.pop(c, 'slot'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Разовая тренировка'),
              subtitle: const Text('План на этот день'),
              onTap: () => Navigator.pop(c, 'session'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Календарь игр из файла'),
              subtitle: const Text('Excel, Word или текст'),
              onTap: () => Navigator.pop(c, 'import'),
            ),
          ]),
        ),
      );
    if (!context.mounted) return;
    switch (choice) {
      case 'match':
        context.push('/calendar/match/new?day=${_day.toIso8601String()}');
      case 'slot':
        context.push('/calendar/slot/new');
      case 'session':
        createSessionAt(context, ref, DateTime(_day.year, _day.month, _day.day, 18), teamId: ref.read(currentTeamProvider)?.id);
      case 'import':
        context.push('/calendar/import');
    }
  }
}

/// Тренировка на дату (из расписания или разовая) — сразу открывается план.
Future<void> createSessionAt(
  BuildContext context,
  WidgetRef ref,
  DateTime at, {
  String? teamId,
  String? title,
  int durationMin = 90,
}) async {
  final teams = ref.read(teamsProvider).value ?? const <Team>[];
  final team = teams.where((t) => t.id == teamId).firstOrNull;
  final s = TrainingSession(
    id: newId(),
    teamId: team?.id,
    title: title ?? 'Тренировка${team == null ? '' : ' ${team.name}'}',
    durationMin: durationMin,
    playersExpected: team?.defaultPlayers,
    equipment: team?.equipment ?? const [],
    scheduledAt: at,
    status: 'planned',
  );
  await ref.read(repoProvider).put(Entities.sessions, s);
  if (context.mounted) context.push('/sessions/${s.id}');
}

class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key, required this.day, required this.onDay});

  final DateTime day;
  final ValueChanged<DateTime> onDay;

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _month = DateTime(widget.day.year, widget.day.month);
  Set<String>? _teams;

  void _shiftMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final matches = ref.watch(matchesProvider).value ?? const <Match>[];
    final slots = ref.watch(slotsProvider).value ?? const <ScheduleSlot>[];
    final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
    List<CalendarEvent> on(DateTime d) =>
        eventsForDay(d, matches: matches, slots: slots, sessions: sessions, teamIds: _teams);
    final grid = monthGrid(_month);
    final today = dayOf(DateTime.now());
    final events = on(widget.day);

    return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
      if (teams.length > 1)
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: const Text('Все команды'),
                  selected: _teams == null,
                  onSelected: (_) => setState(() => _teams = null),
                ),
              ),
              for (final tm in teams)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: CircleAvatar(backgroundColor: teamColor(tm.id, teams), radius: 6),
                    label: Text(tm.name),
                    selected: _teams?.contains(tm.id) ?? false,
                    onSelected: (v) => setState(() {
                      final next = {...?_teams};
                      v ? next.add(tm.id) : next.remove(tm.id);
                      _teams = next.isEmpty ? null : next;
                    }),
                  ),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(children: [
          IconButton(tooltip: 'Предыдущий месяц', onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(
              _cap(DateFormat('LLLL yyyy', 'ru').format(_month)),
              textAlign: TextAlign.center,
              style: t.textTheme.titleLarge?.copyWith(fontFamily: AppTheme.display, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(tooltip: 'Следующий месяц', onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right)),
          TextButton(
            onPressed: () {
              setState(() => _month = DateTime(today.year, today.month));
              widget.onDay(today);
            },
            child: const Text('Сегодня'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (var i = 1; i <= 7; i++)
            Expanded(
              child: Center(
                child: Text(Weekdays.short[i],
                    style: t.textTheme.labelMedium?.copyWith(color: i >= 6 ? AppColors.red : AppColors.textMuted)),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.9,
          children: [
            for (final d in grid)
              _DayCell(
                day: d,
                inMonth: d.month == _month.month,
                today: d == today,
                selected: d == widget.day,
                events: on(d),
                teams: teams,
                onTap: () {
                  if (d.month != _month.month) setState(() => _month = DateTime(d.year, d.month));
                  widget.onDay(d);
                },
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      SectionTitle(_cap(DateFormat('d MMMM, EEEE', 'ru').format(widget.day))),
      if (events.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            slots.isEmpty && matches.isEmpty
                ? 'Добавьте матчи сезона и регулярные тренировки команд — они появятся в календаре.'
                : 'В этот день ничего не запланировано.',
            style: t.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      for (final e in events) EventCard(e, teams: teams),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.selected,
    required this.events,
    required this.teams,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth, today, selected;
  final List<CalendarEvent> events;
  final List<Team> teams;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasMatch = events.any((e) => e.kind == CalendarKind.match);
    final label = [
      DateFormat('d MMMM', 'ru').format(day),
      if (hasMatch) 'матч',
      if (events.any((e) => e.kind != CalendarKind.match)) 'тренировки: ${events.where((e) => e.kind != CalendarKind.match).length}',
    ].join(', ');
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected ? AppColors.red.withValues(alpha: 0.18) : (hasMatch ? AppColors.surfaceHigh : null),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.red : (today ? AppColors.textMuted : Colors.transparent),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: today || hasMatch ? FontWeight.w800 : FontWeight.w500,
                color: inMonth ? (hasMatch ? AppColors.red : AppColors.text) : AppColors.outline,
              ),
            ),
            const SizedBox(height: 3),
            Wrap(spacing: 2, runSpacing: 2, alignment: WrapAlignment.center, children: [
              for (final e in events.take(4))
                e.kind == CalendarKind.match
                    ? const Icon(Icons.sports_soccer, size: 9, color: AppColors.red)
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: e.kind == CalendarKind.slot ? null : teamColor(e.teamId, teams),
                          border: Border.all(color: teamColor(e.teamId, teams), width: 1.4),
                        ),
                      ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Карточка события дня.
class EventCard extends ConsumerWidget {
  const EventCard(this.e, {super.key, required this.teams, this.showDate = false});

  final CalendarEvent e;
  final List<Team> teams;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final team = teams.where((x) => x.id == e.teamId).firstOrNull;
    final color = e.kind == CalendarKind.match ? AppColors.red : teamColor(e.teamId, teams);
    final when = '${showDate ? '${DateFormat('d MMM, EE', 'ru').format(e.start)} · ' : ''}${hm(e.start)}–${hm(e.end)}';
    final (icon, kindLabel) = switch (e.kind) {
      CalendarKind.match => (Icons.sports_soccer, 'Матч'),
      CalendarKind.training => (Icons.event_note, SessionStatus.labels[e.session!.status] ?? ''),
      CalendarKind.slot => (Icons.repeat, 'По расписанию'),
    };
    final m = e.match;
    final subtitle = [
      when,
      if (team != null) team.name,
      if (m != null) m.home ? 'дома' : 'в гостях',
      if (m != null && m.venue.isNotEmpty) m.venue,
      if (e.slot != null && e.slot!.location.isNotEmpty) e.slot!.location,
      if (m != null && m.competition.isNotEmpty) m.competition,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => switch (e.kind) {
          CalendarKind.match => context.push('/calendar/match/${m!.id}'),
          CalendarKind.training =>
            context.push(e.session!.status == 'done' ? '/sessions/${e.session!.id}/summary' : '/sessions/${e.session!.id}'),
          CalendarKind.slot => createSessionAt(context, ref, e.start,
              teamId: e.slot!.teamId, title: e.slot!.title, durationMin: e.slot!.durationMin),
        },
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text(kindLabel.toUpperCase(), style: t.textTheme.labelSmall?.copyWith(color: color, letterSpacing: 1)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    m != null ? '${m.home ? '' : '@ '}${m.opponent}' : e.title,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.textTheme.bodySmall),
                  if (e.kind == CalendarKind.slot)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Нажмите, чтобы составить план', style: t.textTheme.labelMedium?.copyWith(color: AppColors.red)),
                    ),
                ]),
              ),
            ),
            if (m != null && m.hasScore)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(m.score, style: t.textTheme.headlineSmall?.copyWith(fontFamily: AppTheme.display, fontWeight: FontWeight.w700)),
                ),
              )
            else
              const Center(child: Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- матч

class MatchFormScreen extends ConsumerStatefulWidget {
  const MatchFormScreen({super.key, this.matchId, this.day});

  final String? matchId;
  final DateTime? day;

  @override
  ConsumerState<MatchFormScreen> createState() => _MatchFormScreenState();
}

class _MatchFormScreenState extends ConsumerState<MatchFormScreen> {
  final _opponent = TextEditingController();
  final _venue = TextEditingController();
  final _competition = TextEditingController();
  final _notes = TextEditingController();
  final _for = TextEditingController();
  final _against = TextEditingController();
  String? _teamId;
  late DateTime _at;
  int _duration = 90;
  bool _home = true;
  String _status = 'scheduled';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final d = widget.day ?? DateTime.now();
    _at = DateTime(d.year, d.month, d.day, 18);
    _teamId = ref.read(currentTeamProvider)?.id;
    if (widget.matchId == null) {
      _loaded = true;
    } else {
      ref.read(repoProvider).get(Entities.matches, widget.matchId!, Match.fromJson).then((m) {
        if (m == null || !mounted) return;
        setState(() {
          _teamId = m.teamId;
          _opponent.text = m.opponent;
          _venue.text = m.venue;
          _competition.text = m.competition;
          _notes.text = m.notes;
          _for.text = m.scoreFor?.toString() ?? '';
          _against.text = m.scoreAgainst?.toString() ?? '';
          _at = m.startsAt;
          _duration = m.durationMin;
          _home = m.home;
          _status = m.status;
          _loaded = true;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_opponent, _venue, _competition, _notes, _for, _against]) {
      c.dispose();
    }
    super.dispose();
  }

  Match? _build() {
    final team = _teamId;
    if (team == null || _opponent.text.trim().isEmpty) return null;
    return Match(
      id: widget.matchId ?? newId(),
      teamId: team,
      opponent: _opponent.text.trim(),
      startsAt: _at,
      durationMin: _duration,
      home: _home,
      venue: _venue.text.trim(),
      competition: _competition.text.trim(),
      status: _status,
      scoreFor: int.tryParse(_for.text.trim()),
      scoreAgainst: int.tryParse(_against.text.trim()),
      notes: _notes.text.trim(),
    );
  }

  Future<void> _save() async {
    final m = _build();
    if (m == null) {
      showInfo(context, _teamId == null ? 'Сначала создайте команду' : 'Укажите соперника');
      return;
    }
    await ref.read(repoProvider).put(Entities.matches, m);
    if (mounted) popOr(context, '/calendar');
  }

  Future<void> _tactics() async {
    final m = _build();
    if (m == null) return _save();
    final repo = ref.read(repoProvider);
    await repo.put(Entities.matches, m);
    final boards = await repo.list(Entities.boards, TacticBoard.fromJson);
    final existing = boards.where((b) => b.matchId == m.id).firstOrNull;
    final id = existing?.id ?? await createBoard(ref, teamId: m.teamId, matchId: m.id, title: 'Матч: ${m.opponent}');
    if (mounted) context.push('/tactics/$id');
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('ru'),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (tm != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, tm.hour, tm.minute));
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.matchId == null ? 'Новый матч' : 'Матч'),
        actions: [
          if (widget.matchId != null)
            IconButton(
              tooltip: 'Удалить матч',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Удалить матч?')) {
                  await ref.read(repoProvider).remove(Entities.matches, widget.matchId!);
                  if (context.mounted) popOr(context, '/calendar');
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (teams.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Сначала добавьте команду во вкладке «Команда».'))
        else
          DropdownButtonFormField<String>(
            initialValue: teams.any((x) => x.id == _teamId) ? _teamId : null,
            decoration: const InputDecoration(labelText: 'Команда'),
            items: [for (final tm in teams) DropdownMenuItem(value: tm.id, child: Text(tm.name))],
            onChanged: (v) => setState(() => _teamId = v),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _opponent,
          decoration: const InputDecoration(labelText: 'Соперник'),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text(DateFormat('d MMM yyyy, EE', 'ru').format(_at)),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _pickTime, icon: const Icon(Icons.access_time), label: Text(hm(_at))),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Дома'), icon: Icon(Icons.home_outlined)),
            ButtonSegment(value: false, label: Text('В гостях'), icon: Icon(Icons.directions_bus_outlined)),
          ],
          selected: {_home},
          onSelectionChanged: (s) => setState(() => _home = s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _venue, decoration: const InputDecoration(labelText: 'Стадион / адрес')),
        const SizedBox(height: 12),
        TextField(controller: _competition, decoration: const InputDecoration(labelText: 'Турнир (первенство, кубок, товарищеский)')),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: const [40, 50, 60, 70, 80, 90].contains(_duration) ? _duration : null,
          decoration: const InputDecoration(labelText: 'Длительность матча'),
          items: [for (final d in const [40, 50, 60, 70, 80, 90]) DropdownMenuItem(value: d, child: Text('$d мин'))],
          onChanged: (v) => setState(() => _duration = v ?? 90),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [for (final e in MatchStatus.labels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {_status},
          onSelectionChanged: (s) => setState(() => _status = s.first),
        ),
        if (_status == 'played') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _for,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Забили'),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text(':', style: TextStyle(fontSize: 24))),
            Expanded(
              child: TextField(
                controller: _against,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Пропустили'),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Заметки (сбор, форма, выезд)')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _tactics, icon: const Icon(Icons.draw_outlined), label: const Text('Тактика на матч')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- расписание

class SlotsScreen extends ConsumerWidget {
  const SlotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final slots = ref.watch(slotsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Расписание тренировок')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'slot_add',
        onPressed: () => context.push('/calendar/slot/new'),
        icon: const Icon(Icons.add),
        label: const Text('Регулярная тренировка'),
      ),
      body: AsyncView(slots, builder: (all) {
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.schedule,
            title: 'Расписания пока нет',
            text: 'Задайте, когда тренируется каждая команда: например, U16 — пн и ср с 10:00 до 12:00, '
                'основа — ежедневно с 16:00 до 18:00. Тренировки появятся в календаре на весь сезон.',
          );
        }
        final byStart = [...all]..sort((a, b) {
            final d = (a.weekdays.firstOrNull ?? 8).compareTo(b.weekdays.firstOrNull ?? 8);
            return d != 0 ? d : a.startMinutes.compareTo(b.startMinutes);
          });
        return ListView(padding: const EdgeInsets.only(bottom: 120, top: 8), children: [
          for (final s in byStart)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: teamColor(s.teamId, teams), radius: 8),
                title: Text(s.title),
                subtitle: Text([
                  '${s.daysLabel} · ${s.startTime}–${s.endTime}',
                  teams.where((x) => x.id == s.teamId).firstOrNull?.name ?? '',
                  if (s.location.isNotEmpty) s.location,
                  if (s.validFrom != null || s.validTo != null)
                    'сезон: ${s.validFrom == null ? '…' : DateFormat('d.MM.yy').format(s.validFrom!)} – '
                        '${s.validTo == null ? '…' : DateFormat('d.MM.yy').format(s.validTo!)}',
                ].where((x) => x.isNotEmpty).join('\n')),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/calendar/slot/${s.id}'),
              ),
            ),
        ]);
      }),
    );
  }
}

class SlotFormScreen extends ConsumerStatefulWidget {
  const SlotFormScreen({super.key, this.slotId});

  final String? slotId;

  @override
  ConsumerState<SlotFormScreen> createState() => _SlotFormScreenState();
}

class _SlotFormScreenState extends ConsumerState<SlotFormScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  String? _teamId;
  final _days = <int>{};
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  int _duration = 90;
  DateTime? _from, _to;
  bool _loaded = false;
  bool _titleTouched = false;

  @override
  void initState() {
    super.initState();
    _teamId = ref.read(currentTeamProvider)?.id;
    if (widget.slotId == null) {
      _loaded = true;
      _autoTitle();
    } else {
      ref.read(repoProvider).get(Entities.slots, widget.slotId!, ScheduleSlot.fromJson).then((s) {
        if (s == null || !mounted) return;
        final p = s.startTime.split(':');
        setState(() {
          _teamId = s.teamId;
          _title.text = s.title;
          _titleTouched = true;
          _location.text = s.location;
          _days.addAll(s.weekdays);
          _start = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
          _duration = s.durationMin;
          _from = s.validFrom;
          _to = s.validTo;
          _loaded = true;
        });
      });
    }
  }

  void _autoTitle() {
    if (_titleTouched) return;
    final team = (ref.read(teamsProvider).value ?? const <Team>[]).where((x) => x.id == _teamId).firstOrNull;
    _title.text = team == null ? 'Тренировка' : 'Тренировка ${team.name}';
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  String get _startStr => '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_teamId == null) return showInfo(context, 'Сначала создайте команду');
    if (_days.isEmpty) return showInfo(context, 'Выберите дни недели');
    if (_from != null && _to != null && _to!.isBefore(_from!)) return showInfo(context, 'Конец сезона раньше начала');
    await ref.read(repoProvider).put(
          Entities.slots,
          ScheduleSlot(
            id: widget.slotId ?? newId(),
            teamId: _teamId!,
            title: _title.text.trim().isEmpty ? 'Тренировка' : _title.text.trim(),
            weekdays: _days.toList()..sort(),
            startTime: _startStr,
            durationMin: _duration,
            location: _location.text.trim(),
            validFrom: _from,
            validTo: _to,
          ),
        );
    if (mounted) popOr(context, '/calendar/slots');
  }

  Future<DateTime?> _date(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
        locale: const Locale('ru'),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final endMin = _start.hour * 60 + _start.minute + _duration;
    final end = '${(endMin ~/ 60 % 24).toString().padLeft(2, '0')}:${(endMin % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.slotId == null ? 'Регулярная тренировка' : 'Тренировка по расписанию'),
        actions: [
          if (widget.slotId != null)
            IconButton(
              tooltip: 'Удалить из расписания',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Удалить из расписания?', text: 'Уже составленные планы тренировок останутся.')) {
                  await ref.read(repoProvider).remove(Entities.slots, widget.slotId!);
                  if (context.mounted) popOr(context, '/calendar/slots');
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (teams.isEmpty)
          const Text('Сначала добавьте команду во вкладке «Команда».')
        else
          DropdownButtonFormField<String>(
            initialValue: teams.any((x) => x.id == _teamId) ? _teamId : null,
            decoration: const InputDecoration(labelText: 'Команда'),
            items: [for (final tm in teams) DropdownMenuItem(value: tm.id, child: Text(tm.name))],
            onChanged: (v) => setState(() {
              _teamId = v;
              _autoTitle();
            }),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Название'),
          onChanged: (_) => _titleTouched = true,
        ),
        const SizedBox(height: 16),
        Text('Дни недели', style: t.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
              label: Text(Weekdays.short[d]),
              selected: _days.contains(d),
              onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
            ),
          ActionChip(label: const Text('Пн–Пт'), onPressed: () => setState(() => _days..clear()..addAll([1, 2, 3, 4, 5]))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: Text('Начало $_startStr'),
              onPressed: () async {
                final tm = await showTimePicker(context: context, initialTime: _start);
                if (tm != null) setState(() => _start = tm);
              },
            ),
          ),
          const SizedBox(width: 12),
          Text('до $end', style: t.textTheme.titleMedium),
        ]),
        const SizedBox(height: 12),
        Text('Длительность', style: t.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final d in const [60, 75, 90, 105, 120])
            ChoiceChip(label: Text('$d мин'), selected: _duration == d, onSelected: (_) => setState(() => _duration = d)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _location, decoration: const InputDecoration(labelText: 'Место (поле, манеж)')),
        const SizedBox(height: 16),
        Text('Сезон (необязательно)', style: t.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _date(_from);
                if (d != null) setState(() => _from = d);
              },
              child: Text(_from == null ? 'С …' : 'С ${DateFormat('d.MM.yyyy').format(_from!)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _date(_to ?? _from);
                if (d != null) setState(() => _to = d);
              },
              child: Text(_to == null ? 'По …' : 'По ${DateFormat('d.MM.yyyy').format(_to!)}'),
            ),
          ),
          if (_from != null || _to != null)
            IconButton(
              tooltip: 'Без ограничения дат',
              onPressed: () => setState(() => _from = _to = null),
              icon: const Icon(Icons.clear),
            ),
        ]),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ]),
    );
  }
}
