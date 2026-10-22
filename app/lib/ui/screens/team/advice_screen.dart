import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/performance.dart';
import '../../../core/providers.dart';
import '../../../core/recommendations.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/team_switcher.dart';
import '../calendar/calendar_screen.dart';
import '../library/library_screens.dart';
import '../sessions/sessions_screens.dart';
import 'performance_providers.dart';
import 'player_profile.dart';
import 'team_screens.dart';

/// Решения тренера по рекомендациям команды.
final adviceDecisionsProvider = StreamProvider.family<List<AdviceDecision>, String>(
  (ref, teamId) => ref.watch(repoProvider).watchAdviceDecisions(teamId),
);

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
    final decisions = {for (final d in ref.watch(adviceDecisionsProvider(team.id)).value ?? const <AdviceDecision>[]) d.key: d};
    final rejected = [for (final a in rec.all) if (decisions[a.key]?.status == 'rejected') a];
    Widget section(String title, String hint, List<Advice> items) {
      final shown = [for (final a in items) if (decisions[a.key]?.status != 'rejected') a];
      return shown.isEmpty
          ? const SizedBox.shrink()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 16),
              Text(title, style: t.textTheme.titleMedium),
              Text(hint, style: t.textTheme.bodySmall),
              for (final a in shown) _AdviceTile(a, teamId: team.id, decision: decisions[a.key]),
            ]);
    }
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
        section('План и факт', 'Пропуски, время занятий против плана, повторяющиеся темы, выполненные цели', rec.planFact),
        section('Нагрузка и интенсивность команды', 'По нагрузке за неделю, оценкам RPE и календарю матчей', rec.team),
        section('Следующая тренировка', 'По итогам последнего проведённого занятия', rec.nextSession),
        section('Цели на эту неделю', 'Цели сезона и текущие недели индивидуальных программ', rec.week),
        section('Кому нужна дополнительная работа', 'По тестам ОФП, статистике матчей, оценкам навыков и посещаемости', rec.players),
        if (rejected.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Отклонённые (${rejected.length})'),
            children: [for (final a in rejected) _AdviceTile(a, teamId: team.id, decision: decisions[a.key])],
          ),
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

class _AdviceTile extends ConsumerWidget {
  const _AdviceTile(this.a, {required this.teamId, this.decision});

  final Advice a;
  final String teamId;
  final AdviceDecision? decision;

  static (IconData, Color) _look(String kind) => switch (kind) {
        'up' => (Icons.trending_up, AppColors.good),
        'down' => (Icons.trending_down, AppColors.warn),
        'keep' => (Icons.check_circle_outline, AppColors.good),
        'work' => (Icons.build_circle_outlined, AppColors.red),
        _ => (Icons.info_outline, AppColors.textMuted),
      };

  Future<void> _decide(WidgetRef ref, String status, {String note = ''}) => ref.read(repoProvider).put(
        Entities.adviceDecisions,
        AdviceDecision(
          id: decision?.id ?? newId(),
          teamId: teamId,
          key: a.key,
          status: status,
          note: note,
          title: a.title,
          decidedAt: DateTime.now(),
        ),
      );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: decision?.note.isNotEmpty == true ? decision!.note : a.next);
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Своё действие'),
        content: TextField(controller: c, maxLines: 4, minLines: 2, autofocus: true, decoration: const InputDecoration(labelText: 'Что сделаю')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) await _decide(ref, 'edited', note: text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = _look(a.kind);
    final d = decision;
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            TextSpan(text: value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          ])),
        );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                if (d != null)
                  Chip(
                    label: Text(AdviceDecision.labels[d.status]!, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ]),
              const SizedBox(height: 2),
              Text(a.text),
              if (a.basis.isNotEmpty) row('Данные', a.basis),
              if (d?.status == 'edited')
                row('Действие (тренер)', d!.note, bold: true)
              else if (a.next.isNotEmpty)
                row('Действие', a.next, bold: true),
              if (a.expected.isNotEmpty) row('Ожидаемая цель', a.expected),
              row('Уверенность', [confidenceLabels[a.confidence] ?? a.confidence, if (a.limits.isNotEmpty) a.limits].join(' — ')),
              Wrap(spacing: 0, children: [
                if (a.route != null)
                  TextButton.icon(
                    onPressed: () => context.push(a.route!),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Сделать'),
                  ),
                if (d?.status != 'accepted')
                  TextButton(onPressed: () => _decide(ref, 'accepted'), child: const Text('Принять')),
                TextButton(onPressed: () => _edit(context, ref), child: const Text('Изменить')),
                if (d?.status != 'rejected')
                  TextButton(onPressed: () => _decide(ref, 'rejected'), child: const Text('Отклонить'))
                else
                  TextButton(onPressed: () => ref.read(repoProvider).remove(Entities.adviceDecisions, d!.id), child: const Text('Вернуть')),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
