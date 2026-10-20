import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
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
  _Entry(this.minute, this.text, {this.before, this.matchBefore});

  final int minute;
  final String text;
  final MatchStat? before;
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
    setState(() => _log.insert(0, _Entry(_minute, '${_short(p)} — ${e.label}', before: current ?? base, matchBefore: matchBefore)));
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
    setState(() => _log.insert(0, _Entry(_minute, 'Гол соперника', before: before, matchBefore: m)));
  }

  Future<void> _saveScore(Match m, int ours, int theirs) => ref
      .read(repoProvider)
      .put(Entities.matches, Match.fromJson(m.id, m.toJson()..['score_for'] = ours..['score_against'] = theirs..['status'] = 'played'));

  Future<void> _undo() async {
    if (_log.isEmpty) return;
    final e = _log.removeAt(0);
    final repo = ref.read(repoProvider);
    if (e.before != null) await repo.put(Entities.matchStats, e.before!);
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
          Text(selected == null ? '1. Выберите игрока' : '1. Игрок: ${selected.fullName}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in players)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: (stats[p.id]?.minutes ?? 0) > 0 ? AppColors.red : AppColors.outline,
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
                          : () => _record(m, selected, stats[selected.id], e, ourGoals),
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
