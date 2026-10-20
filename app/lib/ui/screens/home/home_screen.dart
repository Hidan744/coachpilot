import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../calendar/calendar_screen.dart';
import '../sessions/sessions_screens.dart';

final _allReportsProvider = StreamProvider<List<SessionReport>>(
  (ref) => ref.watch(repoProvider).watch(Entities.reports, SessionReport.fromJson),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final name = ref.watch(authProvider).name;
    final team = ref.watch(currentTeamProvider);
    final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
    final reports = ref.watch(_allReportsProvider).value ?? const <SessionReport>[];
    final teams = {for (final x in ref.watch(teamsProvider).value ?? <Team>[]) x.id: x};

    final upcoming = sessions.where((s) => s.status == 'planned' || s.status == 'in_progress').toList()
      ..sort((a, b) {
        if (a.status != b.status) return a.status == 'in_progress' ? -1 : 1;
        return (a.scheduledAt ?? DateTime(2100)).compareTo(b.scheduledAt ?? DateTime(2100));
      });
    final next = upcoming.firstOrNull;
    final confirmed = reports.where((r) => r.coachConfirmed).map((r) => r.sessionId).toSet();
    final done = sessions.where((s) => s.status == 'done').toList()
      ..sort((a, b) => (b.finishedAt ?? DateTime(2000)).compareTo(a.finishedAt ?? DateTime(2000)));
    final needReport = done.where((s) => !confirmed.contains(s.id)).take(3).toList();
    final drafts = sessions.where((s) => s.status == 'draft').length;
    final now = DateTime.now();
    final nextMatch = ([...ref.watch(matchesProvider).value ?? const <Match>[]]
          ..retainWhere((m) => m.status == 'scheduled' && m.startsAt.isAfter(now.subtract(const Duration(hours: 2))))
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(name.isEmpty ? 'CoachPilot' : 'Привет, $name'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (next != null)
          Card(
            color: t.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(next.status == 'in_progress' ? 'Идёт занятие' : 'Ближайшая тренировка', style: t.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(next.title, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text([
                  formatWhen(next.scheduledAt),
                  if (teams[next.teamId] != null) teams[next.teamId]!.name,
                  '${next.blocks.length} блоков · ${next.durationMin} мин',
                ].join(' · ')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text(next.status == 'in_progress' ? 'Продолжить' : 'Провести'),
                      onPressed: () => context.push('/run/${next.id}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => context.push('/sessions/${next.id}'), child: const Text('План')),
                ]),
              ]),
            ),
          ),
        if (nextMatch != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.sports_soccer, color: AppColors.red),
              title: Text('Матч: ${nextMatch.opponent}'),
              subtitle: Text([
                DateFormat('d MMMM, EE HH:mm', 'ru').format(nextMatch.startsAt),
                nextMatch.home ? 'дома' : 'в гостях',
                if (teams[nextMatch.teamId] != null) teams[nextMatch.teamId]!.name,
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/calendar/match/${nextMatch.id}'),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          onPressed: () => context.push('/sessions/new'),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Создать тренировку с AI'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.go('/calendar'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Календарь'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => context.push('/tactics'),
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Тактика'),
            ),
          ),
        ]),
        if (drafts > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(onPressed: () => context.go('/sessions'), child: Text('Черновиков планов: $drafts')),
          ),
        if (needReport.isNotEmpty) ...[
          const SectionTitle('Ждут отчёта'),
          for (final s in needReport)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.rate_review_outlined),
                title: Text(s.title),
                subtitle: Text(formatWhen(s.finishedAt)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/sessions/${s.id}/report'),
              ),
            ),
        ],
        if (done.isNotEmpty) ...[
          const SectionTitle('Недавние занятия'),
          for (final s in done.take(3)) SessionTile(s, team: teams[s.teamId]),
        ],
        if (team != null) ...[
          const SectionTitle('Команда'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(team.name),
              subtitle: Text('${AgeGroups.label(team.ageGroup)} · ${Levels.all[team.level] ?? team.level}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/team'),
            ),
          ),
        ],
        if (next == null && done.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: Icons.sports_soccer,
              title: 'Первая тренировка — за минуту',
              text: 'Укажите цель занятия, а AI предложит план из проверенных упражнений. Потом проведёте его прямо с телефона.',
            ),
          ),
      ]),
    );
  }
}
