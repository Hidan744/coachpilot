import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/lineup.dart';
import '../../../core/performance.dart';
import '../../../core/tactics.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../tactics/lineup_screen.dart';
import '../tactics/tactics_screens.dart';
import '../team/performance_providers.dart';
import '../team/team_screens.dart';

/// Действие в Live-режиме: подпись, значок и какие показатели меняются.
class LiveEvent {
  const LiveEvent(this.id, this.label, this.icon, this.changes, {this.color, this.keeper = false});

  final String id, label;
  final IconData icon;
  final Map<String, double> changes;
  final Color? color;

  /// Только для вратаря.
  final bool keeper;
}

const liveEvents = [
  LiveEvent('goal', 'Гол', Icons.sports_soccer, {'goals': 1}, color: AppColors.good),
  LiveEvent('assist', 'Голевая', Icons.call_split, {'assists': 1}, color: AppColors.good),
  LiveEvent('shot_on', 'Удар в створ', Icons.gps_fixed, {'shots_on': 1}),
  LiveEvent('shot_off', 'Удар мимо', Icons.gps_not_fixed, {'shots': 1}),
  LiveEvent('key_pass', 'Ключевая передача', Icons.insights, {'key_passes': 1}),
  LiveEvent('dribble', 'Обводка', Icons.directions_run, {'dribbles': 1}),
  LiveEvent('cross', 'Навес', Icons.turn_right, {'crosses': 1}),
  LiveEvent('tackle', 'Отбор', Icons.shield_outlined, {'tackles': 1}),
  LiveEvent('interception', 'Перехват', Icons.back_hand_outlined, {'interceptions': 1}),
  LiveEvent('recovery', 'Подбор', Icons.replay, {'recoveries': 1}),
  LiveEvent('duel_won', 'Единоборство +', Icons.sports_kabaddi, {'duels': 1, 'duels_won': 1}),
  LiveEvent('duel_lost', 'Единоборство −', Icons.sports_kabaddi_outlined, {'duels': 1}, color: AppColors.warn),
  LiveEvent('loss', 'Потеря', Icons.remove_circle_outline, {'losses': 1}, color: AppColors.warn),
  LiveEvent('foul', 'Фол', Icons.front_hand_outlined, {'fouls': 1}, color: AppColors.warn),
  LiveEvent('yellow', 'Жёлтая', Icons.square, {'yellow': 1}, color: Color(0xFFFFD54F)),
  LiveEvent('red', 'Красная', Icons.square, {'red': 1}, color: AppColors.red),
  LiveEvent('save', 'Сейв', Icons.sports_handball, {'saves': 1}, keeper: true),
];

final _liveMatchProvider = StreamProvider.family<Match?, String>(
  (ref, id) => ref.watch(repoProvider).watchOne(Entities.matches, id, Match.fromJson),
);

/// Запись журнала: что отмечено и как было до этого — для отмены.
class _Entry {
  _Entry(this.minute, this.text, {this.before = const [], this.matchBefore});

  final int minute;
  final String text;
  final List<MatchStat> before;
  final Match? matchBefore;
}

/// Live: помощник отмечает действия игроков прямо во время матча.
/// Выбрал игрока → нажал действие. Всё сохраняется сразу в статистику матча.
class LiveMatchScreen extends ConsumerStatefulWidget {
  const LiveMatchScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<LiveMatchScreen> createState() => _LiveMatchScreenState();
}

class _LiveMatchScreenState extends ConsumerState<LiveMatchScreen> {
  final _clock = Stopwatch();
  Timer? _tick;
  int _offset = 0; // секунды: начало 2-го тайма
  String? _selected;
  final _log = <_Entry>[];

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _seconds => _offset + _clock.elapsed.inSeconds;
  int get _minute => _seconds ~/ 60 + 1;

  void _toggleClock() {
    setState(() {
      if (_clock.isRunning) {
        _clock.stop();
        _tick?.cancel();
      } else {
        _clock.start();
        _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      }
    });
  }

  void _secondHalf(Match m) => setState(() {
        _offset = m.durationMin ~/ 2 * 60;
        _clock
          ..reset()
          ..start();
        _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      });

  Future<void> _record(Match m, Player p, MatchStat? current, LiveEvent e, int ourGoals) async {
    final repo = ref.read(repoProvider);
    final base = current ?? MatchStat(id: matchStatId(m.id, p.id), matchId: m.id, playerId: p.id);
    var stats = base.stats;
    for (final c in e.changes.entries) {
      stats = applyStatDelta(stats, c.key, c.value);
    }
    // Отметил действие — значит, игрок на поле: минуты по умолчанию — весь матч, их можно поправить потом.
    final next = base.copyWith(stats: stats, minutes: base.minutes > 0 ? base.minutes : m.durationMin, started: base.minutes > 0 ? null : true);
    await repo.put(Entities.matchStats, next);
    Match? matchBefore;
    if (e.id == 'goal') {
      matchBefore = m;
      await _saveScore(m, ourGoals + 1, m.scoreAgainst ?? 0);
    }
    setState(() => _log.insert(0, _Entry(_minute, '${_short(p)} — ${e.label}', before: [current ?? base], matchBefore: matchBefore)));
  }

  Future<void> _opponentGoal(Match m, List<Player> players, Map<String, MatchStat> stats, int ourGoals) async {
    // Пропущенный — вратарю, который сейчас на поле (если отмечен).
    final keeper = players.where((p) => p.position == 'GK' && (stats[p.id]?.minutes ?? 0) > 0).firstOrNull;
    MatchStat? before;
    if (keeper != null) {
      before = stats[keeper.id]!;
      await ref.read(repoProvider).put(Entities.matchStats, before.copyWith(stats: applyStatDelta(before.stats, 'conceded', 1)));
    }
    await _saveScore(m, ourGoals, (m.scoreAgainst ?? 0) + 1);
    setState(() => _log.insert(0, _Entry(_minute, 'Гол соперника', before: [?before], matchBefore: m)));
  }

  Future<void> _saveScore(Match m, int ours, int theirs) => ref
      .read(repoProvider)
      .put(Entities.matches, Match.fromJson(m.id, m.toJson()..['score_for'] = ours..['score_against'] = theirs..['status'] = 'played'));

  /// Стартовый состав: отмеченные игроки на поле с первой минуты.
  Future<void> _setStarters(Match m, List<Player> picked, Map<String, MatchStat> stats) async {
    final repo = ref.read(repoProvider);
    final before = <MatchStat>[];
    for (final p in picked) {
      final cur = stats[p.id] ?? MatchStat(id: matchStatId(m.id, p.id), matchId: m.id, playerId: p.id);
      before.add(cur);
      await repo.put(Entities.matchStats, cur.copyWith(started: true, minutes: m.durationMin));
    }
    setState(() => _log.insert(0, _Entry(_minute, 'Стартовый состав: ${picked.length} игроков', before: before)));
  }

  /// Замена: ушедший играл до этой минуты, вышедший — с этой минуты до конца.
  Future<MatchStat> _substitute(Match m, Player out, Player into, Map<String, MatchStat> stats) async {
    final repo = ref.read(repoProvider);
    final minute = clampMinute(_minute, m.durationMin);
    final o = stats[out.id] ?? MatchStat(id: matchStatId(m.id, out.id), matchId: m.id, playerId: out.id, started: true, minutes: m.durationMin);
    final i = stats[into.id] ?? MatchStat(id: matchStatId(m.id, into.id), matchId: m.id, playerId: into.id);
    // Вышедший на замену уходит: из его минут вычитаем оставшееся время.
    final outMinutes = o.started ? minute : (o.minutes - (m.durationMin - minute)).clamp(1, m.durationMin);
    await repo.put(Entities.matchStats, o.copyWith(minutes: outMinutes, started: o.started || o.minutes == 0));
    final next = i.copyWith(started: false, minutes: (m.durationMin - minute).clamp(1, m.durationMin));
    await repo.put(Entities.matchStats, next);
    if (_selected == out.id) _selected = into.id;
    setState(() => _log.insert(0, _Entry(minute, 'Замена: ${_short(into)} вместо ${_short(out)}', before: [o, i])));
    if (mounted) showInfo(context, 'Замена на $minute′: ${_short(into)} вместо ${_short(out)}');
    return next;
  }

  /// Действие игрока со скамейки, когда состав уже на поле: сначала замена — кого он меняет.
  Future<void> _act(Match m, Player p, LiveEvent e, Map<String, MatchStat> stats, List<Player> onField, int ourGoals) async {
    var current = stats[p.id];
    if (onField.isNotEmpty && (current?.minutes ?? 0) == 0) {
      final out = await _pickPlayer('${_short(p)} на скамейке. Кого он меняет?', onField);
      if (out == null || !mounted) return;
      current = await _substitute(m, out, p, stats);
    }
    await _record(m, p, current, e, ourGoals);
  }

  Future<Player?> _pickPlayer(String title, List<Player> from) => showModalBottomSheet<Player>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (c, scroll) => ListView(controller: scroll, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(title, style: Theme.of(c).textTheme.titleMedium)),
            for (final p in from)
              ListTile(
                leading: CircleAvatar(child: Text(p.number?.toString() ?? '—')),
                title: Text(p.fullName),
                subtitle: Text(Positions.all[p.position] ?? ''),
                onTap: () => Navigator.pop(c, p),
              ),
          ]),
        ),
      );

  Future<void> _startersSheet(Match m, List<Player> players, Map<String, MatchStat> stats, List<Player> suggested) async {
    final picked = {for (final p in suggested) p.id};
    final need = playersInFormation(_formation(m));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Стартовый состав', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              suggested.isEmpty
                  ? 'Отметьте, кто выходит с первой минуты.'
                  : 'Отмечены игроки из подбора состава под схему ${_formation(m)}. Поправьте, если нужно.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in players)
                FilterChip(
                  label: Text('${p.number ?? ''} ${_short(p)}'.trim()),
                  selected: picked.contains(p.id),
                  onSelected: (v) => set(() => v ? picked.add(p.id) : picked.remove(p.id)),
                ),
            ]),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              child: Text('На поле: ${picked.length}${picked.length == need ? '' : ' (по схеме $need)'}'),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) await _setStarters(m, [for (final p in players) if (picked.contains(p.id)) p], stats);
  }

  Future<void> _manualSub(Match m, List<Player> onField, List<Player> bench, Map<String, MatchStat> stats) async {
    if (bench.isEmpty) return showInfo(context, 'На скамейке никого нет');
    final out = await _pickPlayer('Кто уходит?', onField);
    if (out == null || !mounted) return;
    final into = await _pickPlayer('Кто выходит вместо ${_short(out)}?', bench);
    if (into != null) await _substitute(m, out, into, stats);
  }

  /// Схема на матч: доска этого матча, иначе последняя доска команды, иначе обычная для формата.
  String _formation(Match m) {
    final boards = ref.read(boardsProvider).value ?? const <TacticBoard>[];
    final board = boards.where((b) => b.matchId == m.id && b.formation.isNotEmpty).firstOrNull ??
        boards.where((b) => b.teamId == m.teamId && b.formation.isNotEmpty).lastOrNull;
    final team = (ref.read(teamsProvider).value ?? const <Team>[]).where((t) => t.id == m.teamId).firstOrNull;
    final options = formationsFor(team?.defaultPlayers ?? 11);
    return board != null && options.contains(board.formation) ? board.formation : options[options.length > 1 ? 1 : 0];
  }

  Future<void> _undo() async {
    if (_log.isEmpty) return;
    final e = _log.removeAt(0);
    final repo = ref.read(repoProvider);
    for (final b in e.before) {
      await repo.put(Entities.matchStats, b);
    }
    if (e.matchBefore != null) await repo.put(Entities.matches, e.matchBefore!);
    if (mounted) {
      setState(() {});
      showInfo(context, 'Отменено: ${e.text}');
    }
  }

  String _short(Player p) => p.lastName.isEmpty ? p.firstName : '${p.lastName} ${p.firstName.characters.first}.';

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(_liveMatchProvider(widget.matchId));
    return AsyncView(match, builder: (m) {
      if (m == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'Матч удалён'));
      final players = (ref.watch(playersProvider(m.teamId)).value ?? const <Player>[]).where((p) => p.active).toList()
        ..sort((a, b) => (a.number ?? 999).compareTo(b.number ?? 999));
      final stats = {
        for (final s in ref.watch(matchStatsProvider).value ?? const <MatchStat>[])
          if (s.matchId == m.id) s.playerId: s,
      };
      final selected = players.where((p) => p.id == _selected).firstOrNull;
      // Наши голы: счёт матча, а если его ещё нет — сумма голов, уже отмеченных игрокам.
      final ourGoals = m.scoreFor ?? stats.values.fold<double>(0, (a, s) => a + s['goals']).round();
      final keeper = selected?.position == 'GK';
      // Кто на поле и кто на скамейке — по статистике матча.
      final onField = [for (final p in players) if (onFieldNow(stats[p.id], m.durationMin)) p];
      final bench = [for (final p in players) if ((stats[p.id]?.minutes ?? 0) == 0) p];
      final data = ref.watch(lineupDataProvider((m.teamId, m.id)));
      final minute = clampMinute(_minute, m.durationMin);
      final advice = data == null || onField.isEmpty
          ? const <SubAdvice>[]
          : substitutionAdvice(
              onField: onField,
              bench: bench,
              live: stats,
              minute: minute,
              ourGoals: ourGoals,
              theirGoals: m.scoreAgainst ?? 0,
              season: data.$2,
              ready: data.$3,
            );
      final events = [for (final e in liveEvents) if (!e.keeper || keeper) e];
      final mm = (_seconds ~/ 60).toString().padLeft(2, '0'), ss = (_seconds % 60).toString().padLeft(2, '0');

      return Scaffold(
        appBar: AppBar(
          title: Text('Live: ${m.opponent}'),
          actions: [
            IconButton(
              tooltip: 'Вся статистика матча',
              icon: const Icon(Icons.table_rows_outlined),
              onPressed: () => context.push('/calendar/match/${m.id}/stats'),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
          // Счёт и время.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF3A0A0D), Color(0xFF151517)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$ourGoals : ${m.scoreAgainst ?? 0}',
                      style: const TextStyle(fontFamily: AppTheme.display, fontSize: 40, fontWeight: FontWeight.w700)),
                  Text('Мы — ${m.opponent}', style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$mm:$ss', style: const TextStyle(fontFamily: AppTheme.display, fontSize: 28, fontWeight: FontWeight.w700)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.filled(
                    tooltip: _clock.isRunning ? 'Пауза' : 'Старт',
                    onPressed: _toggleClock,
                    icon: Icon(_clock.isRunning ? Icons.pause : Icons.play_arrow),
                  ),
                  TextButton(onPressed: () => _secondHalf(m), child: const Text('2-й тайм')),
                ]),
              ]),
            ]),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _opponentGoal(m, players, stats, ourGoals),
            icon: const Icon(Icons.sports_soccer, color: AppColors.warn),
            label: const Text('Гол соперника'),
          ),
          const SizedBox(height: 12),
          if (onField.isEmpty)
            _LiveCard(
              icon: Icons.groups_2_outlined,
              title: 'Стартовый состав',
              text: 'Отметьте, кто выходит с первой минуты, — тогда приложение подскажет замены по ходу матча.',
              child: FilledButton.icon(
                onPressed: () {
                  final formation = _formation(m);
                  final suggested = data == null || players.length < playersInFormation(formation)
                      ? const <Player>[]
                      : suggestLineup(formation: formation, style: 'press', players: players, season: data.$2, ready: data.$3)
                          .players
                          .whereType<Player>()
                          .toList();
                  _startersSheet(m, players, stats, suggested);
                },
                icon: const Icon(Icons.checklist),
                label: const Text('Отметить стартовый состав'),
              ),
            )
          else if (advice.isEmpty)
            // Менять некого — одна строка, чтобы не отодвигать кнопки действий.
            Row(children: [
              const Icon(Icons.swap_vert, color: AppColors.textMuted, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Замены $minute′: пока менять некого', style: const TextStyle(color: AppColors.textMuted)),
              ),
              TextButton(onPressed: () => _manualSub(m, onField, bench, stats), child: Text('Замена · на поле ${onField.length}')),
            ])
          else
            _LiveCard(
              icon: Icons.swap_vert,
              title: 'Подсказки замен · $minute′',
              text: 'По действиям в этом матче, карточкам, нагрузке за неделю и счёту.',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final a in advice) _SubTile(advice: a, onApply: a.into == null ? null : () => _substitute(m, a.out, a.into!, stats)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _manualSub(m, onField, bench, stats),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text('Сделать замену вручную · на поле ${onField.length}'),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 12),
          Text(selected == null ? '1. Выберите игрока' : '1. Игрок: ${selected.fullName}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in players)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: onFieldNow(stats[p.id], m.durationMin) ? AppColors.red : AppColors.outline,
                  child: Text(p.number?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
                label: Text(_short(p)),
                selected: _selected == p.id,
                onSelected: (_) => setState(() => _selected = p.id),
              ),
          ]),
          const SizedBox(height: 12),
          const Text('2. Нажмите действие', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) => GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: box.maxWidth >= 560 ? 4 : 3,
                mainAxisExtent: 76,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              children: [
                for (final e in events)
                  Material(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: selected == null
                          ? () => showInfo(context, 'Сначала выберите игрока')
                          : () => _act(m, selected, e, stats, onField, ourGoals),
                      child: Opacity(
                        opacity: selected == null ? 0.45 : 1,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(e.icon, color: e.color ?? AppColors.text),
                          const SizedBox(height: 4),
                          Text(e.label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Журнал матча', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: _log.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
              label: const Text('Отменить последнее'),
            ),
          ]),
          if (_log.isEmpty)
            const Text('Здесь появятся отмеченные действия с минутой матча.', style: TextStyle(color: AppColors.textMuted)),
          for (final e in _log.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 44, child: Text("${e.minute}'", style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700))),
                Expanded(child: Text(e.text)),
              ]),
            ),
        ]),
      );
    });
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.icon, required this.title, required this.text, required this.child});

  final IconData icon;
  final String title, text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ]),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

/// Подсказка замены: кто уходит и почему, кто выходит и что это даёт.
class _SubTile extends StatelessWidget {
  const _SubTile({required this.advice, required this.onApply});

  final SubAdvice advice;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final a = advice;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.arrow_downward, color: AppColors.red, size: 18),
          Flexible(child: Text(' ${shortName(a.out)}', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (a.into != null) ...[
            const SizedBox(width: 10),
            const Icon(Icons.arrow_upward, color: AppColors.good, size: 18),
            Flexible(child: Text(' ${shortName(a.into!)}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
          const Spacer(),
          if (onApply != null) FilledButton.tonal(onPressed: onApply, child: const Text('Заменить')),
        ]),
        const SizedBox(height: 4),
        for (final w in a.why) Text('• $w', style: const TextStyle(fontSize: 13)),
        Text(a.plan, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}
