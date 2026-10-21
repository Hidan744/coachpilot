import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../core/recommendations.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/team_switcher.dart';
import '../calendar/calendar_screen.dart';
import '../library/library_screens.dart';
import '../sessions/sessions_screens.dart';
import 'performance_providers.dart';
import 'player_profile.dart';
import 'team_screens.dart';

/// Раздел рекомендаций: что сделать, почему, на каких данных и какой следующий шаг.
class AdviceScreen extends ConsumerWidget {
  const AdviceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(currentTeamProvider);
    if (team == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Рекомендации')),
        body: const EmptyState(icon: Icons.groups_outlined, title: 'Нет команды', text: 'Создайте команду — рекомендации строятся по её данным.'),
      );
    }
    final players = [for (final p in ref.watch(playersProvider(team.id)).value ?? const <Player>[]) if (p.active) p];
    final snapshots = [for (final p in players) ?ref.watch(playerSnapshotProvider(p.id))];
    final matches = ref.watch(matchesProvider).value ?? const <Match>[];
    final teamMatches = {for (final m in matches) if (m.teamId == team.id) m.id};
    final rec = coachRecommendations(
      team: team,
      players: snapshots,
      sessions: ref.watch(sessionsProvider).value ?? const [],
      reports: {for (final r in ref.watch(allReportsProvider).value ?? const <SessionReport>[]) r.sessionId: r},
      attendance: ref.watch(allAttendanceProvider).value ?? const [],
      matches: matches,
      plans: [
        for (final p in ref.watch(allDevPlansProvider).value ?? const <DevelopmentPlan>[])
          if (players.any((x) => x.id == p.playerId)) p,
      ],
      library: ref.watch(drillsProvider).value ?? const [],
      season: seasonStats([for (final s in ref.watch(matchStatsProvider).value ?? const <MatchStat>[]) if (teamMatches.contains(s.matchId)) s]),
    );
    final t = Theme.of(context);
    Widget section(String title, String hint, List<Advice> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 16),
            Text(title, style: t.textTheme.titleMedium),
            Text(hint, style: t.textTheme.bodySmall),
            for (final a in items) _AdviceTile(a),
          ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Рекомендации')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        const TeamSwitcher(padding: EdgeInsets.only(bottom: 8)),
        Text(
          'Рекомендации считаются по правилам из данных вашей команды: отчётов, посещаемости, тестов ОФП, оценок и статистики. '
          'Это не нейросеть и не измерения: у каждого пункта указано основание. Решение остаётся за тренером.',
          style: t.textTheme.bodySmall,
        ),
        if (rec.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: 'Пока рекомендовать нечего',
              text: 'Данных мало, чтобы делать выводы. Ниже — что нужно собрать.',
            ),
          ),
        section('Нагрузка и интенсивность команды', 'По нагрузке за неделю, оценкам RPE и календарю матчей', rec.team),
        section('Следующая тренировка', 'По итогам последнего проведённого занятия', rec.nextSession),
        section('Цели на эту неделю', 'Цели сезона и текущие недели индивидуальных программ', rec.week),
        section('Кому нужна дополнительная работа', 'По тестам ОФП, статистике матчей, оценкам навыков и посещаемости', rec.players),
        if (rec.missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Каких данных не хватает', style: t.textTheme.titleMedium),
          for (final m in rec.missing)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.playlist_add_check, color: AppColors.textMuted),
              title: Text(m),
            ),
        ],
      ]),
    );
  }
}

class _AdviceTile extends StatelessWidget {
  const _AdviceTile(this.a);

  final Advice a;

  static (IconData, Color) _look(String kind) => switch (kind) {
        'up' => (Icons.trending_up, AppColors.good),
        'down' => (Icons.trending_down, AppColors.warn),
        'keep' => (Icons.check_circle_outline, AppColors.good),
        'work' => (Icons.build_circle_outlined, AppColors.red),
        _ => (Icons.info_outline, AppColors.textMuted),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look(a.kind);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(a.text),
              if (a.basis.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Основание: ${a.basis}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ),
              if (a.next.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Следующий шаг: ${a.next}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              if (a.route != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push(a.route!),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Сделать'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
