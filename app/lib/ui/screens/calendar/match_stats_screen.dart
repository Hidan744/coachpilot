import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/file_import.dart';
import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../core/stats_import.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../team/performance_providers.dart';
import '../team/team_screens.dart';

/// Статистика матча: кто играл, сколько минут, голы, передачи, отборы, карточки, оценка.
/// Каждое изменение сохраняется сразу.
class MatchStatsScreen extends ConsumerWidget {
  const MatchStatsScreen({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(_matchProvider(matchId));
    return AsyncView(match, builder: (m) {
      if (m == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.event_busy, title: 'Матч удалён'));
      final players = ref.watch(playersProvider(m.teamId)).value ?? const <Player>[];
      final stats = {
        for (final s in ref.watch(matchStatsProvider).value ?? const <MatchStat>[])
          if (s.matchId == m.id) s.playerId: s,
      };
      final played = stats.values.where((s) => s.minutes > 0).length;
      final goals = stats.values.fold<double>(0, (a, s) => a + s['goals']).round();
      final ordered = [...players]..sort((a, b) {
          final pa = (stats[a.id]?.minutes ?? 0) > 0, pb = (stats[b.id]?.minutes ?? 0) > 0;
          if (pa != pb) return pa ? -1 : 1;
          return (a.number ?? 999).compareTo(b.number ?? 999);
        });
      return Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Статистика: ${m.opponent}'),
            Text(DateFormat('d MMMM yyyy', 'ru').format(m.startsAt), style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            IconButton(
              tooltip: 'Загрузить статистику из файла',
              icon: const Icon(Icons.upload_file),
              onPressed: () => _import(context, ref, m, players),
            ),
          ],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Сыграли: $played · голов: $goals${m.hasScore ? ' · счёт ${m.score}' : ''}. '
              'Отметьте, кто играл, — минуты подставятся сами.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          if (players.isEmpty) const EmptyState(icon: Icons.groups_outlined, title: 'В команде нет игроков'),
          for (final p in ordered) _PlayerStatCard(match: m, player: p, stat: stats[p.id]),
        ]),
      );
    });
  }

  Future<void> _import(BuildContext context, WidgetRef ref, Match m, List<Player> players) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: supportedTableExtensions);
    if (f == null) return;
    try {
      final rows = parseStatsTable(readTable(f.name, await f.readAsBytes()), players);
      final repo = ref.read(repoProvider);
      for (final r in rows) {
        await repo.put(
          Entities.matchStats,
          MatchStat(
            id: matchStatId(m.id, r.player.id),
            matchId: m.id,
            playerId: r.player.id,
            started: r.started,
            minutes: r.minutes,
            rating: r.rating,
            stats: r.stats,
          ),
        );
      }
      if (context.mounted) {
        showInfo(context, rows.isEmpty ? 'В файле не нашлось игроков команды' : 'Загружена статистика игроков: ${rows.length}');
      }
    } on ImportException catch (e) {
      if (context.mounted) showInfo(context, e.message);
    }
  }
}

final _matchProvider = StreamProvider.family<Match?, String>(
  (ref, id) => ref.watch(repoProvider).watchOne(Entities.matches, id, Match.fromJson),
);

class _PlayerStatCard extends ConsumerStatefulWidget {
  const _PlayerStatCard({required this.match, required this.player, required this.stat});

  final Match match;
  final Player player;
  final MatchStat? stat;

  @override
  ConsumerState<_PlayerStatCard> createState() => _PlayerStatCardState();
}

class _PlayerStatCardState extends ConsumerState<_PlayerStatCard> {
  bool _more = false;

  MatchStat get _s =>
      widget.stat ??
      MatchStat(id: matchStatId(widget.match.id, widget.player.id), matchId: widget.match.id, playerId: widget.player.id);

  Future<void> _put(MatchStat s) => ref.read(repoProvider).put(Entities.matchStats, s);

  void _bump(String key, int d) {
    final s = _s;
    final next = {...s.stats, key: (s[key] + d).clamp(0, 999).toDouble()};
    // Гол — это удар в створ, удар в створ — удар; точных передач не больше, чем передач.
    double v(String k) => next[k] ?? 0;
    if (v('shots_on') < v('goals')) next['shots_on'] = v('goals');
    if (v('shots') < v('shots_on')) next['shots'] = v('shots_on');
    if (v('passes') < v('passes_ok')) next['passes'] = v('passes_ok');
    _put(s.copyWith(stats: next));
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final p = widget.player;
    final played = s.minutes > 0;
    final keeper = p.position == 'GK';
    final keys = statKeys.where((k) => (_more || k.basic) && (!k.keeper || keeper)).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 16, child: Text(p.number?.toString() ?? p.firstName.characters.first)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Semantics(
              label: 'Играл: ${p.fullName}',
              child: Switch(
                value: played,
                onChanged: (v) => _put(s.copyWith(minutes: v ? widget.match.durationMin : 0, started: v)),
              ),
            ),
          ]),
          if (played) ...[
            Row(children: [
              FilterChip(
                label: const Text('В старте'),
                selected: s.started,
                onSelected: (v) => _put(s.copyWith(started: v)),
              ),
              const Spacer(),
              const Text('Минуты'),
              IconButton(tooltip: 'Меньше минут', onPressed: () => _put(s.copyWith(minutes: (s.minutes - 5).clamp(1, 150))), icon: const Icon(Icons.remove)),
              Text('${s.minutes}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(tooltip: 'Больше минут', onPressed: () => _put(s.copyWith(minutes: (s.minutes + 5).clamp(1, 150))), icon: const Icon(Icons.add)),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in keys) _Counter(label: k.label, value: s[k.key].round(), onChange: (d) => _bump(k.key, d)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Text('Оценка'),
              Expanded(
                child: Slider(
                  value: s.rating ?? 6,
                  min: 1,
                  max: 10,
                  divisions: 18,
                  label: (s.rating ?? 6).toStringAsFixed(1),
                  onChanged: (v) => _put(s.copyWith(rating: v)),
                ),
              ),
              Text(s.rating == null ? '—' : s.rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _more = !_more),
                child: Text(_more ? 'Только основное' : 'Ещё показатели: передачи, перехваты, единоборства…'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onChange});

  final String label;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(color: AppColors.surfaceHighest, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '$label: меньше',
            onPressed: value > 0 ? () => onChange(-1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '$label: больше',
            onPressed: () => onChange(1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ]),
      );
}
