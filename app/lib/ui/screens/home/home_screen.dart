import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../theme.dart';
import '../../widgets/team_switcher.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../calendar/calendar_screen.dart';
import '../profile/profile_screen.dart';
import '../sessions/sessions_screens.dart';
import '../team/performance_providers.dart';
import '../team/team_dashboard.dart';
import '../team/team_screens.dart';

/// Главная — пульт тренера: что сегодня, быстрые действия и дашборд команды.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final team = ref.watch(currentTeamProvider);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
    final reports = ref.watch(allReportsProvider).value ?? const <SessionReport>[];
    final players = team == null ? const <Player>[] : ref.watch(playersProvider(team.id)).value ?? const <Player>[];

    final confirmed = reports.where((r) => r.coachConfirmed).map((r) => r.sessionId).toSet();
    final done = sessions.where((s) => s.status == 'done').toList()
      ..sort((a, b) => (b.finishedAt ?? DateTime(2000)).compareTo(a.finishedAt ?? DateTime(2000)));
    final needReport = done.where((s) => !confirmed.contains(s.id)).take(3).toList();
    final running = sessions.where((s) => s.status == 'in_progress').firstOrNull;

    var i = 0;
    Widget a(Widget w) => Appear(index: i++, child: w);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        // На широком экране содержимое — колонкой по центру, а не на всю ширину.
        child: LayoutBuilder(
          builder: (context, box) => ListView(
              padding: EdgeInsets.fromLTRB(box.maxWidth > 792 ? (box.maxWidth - 760) / 2 : 16, 8,
                  box.maxWidth > 792 ? (box.maxWidth - 760) / 2 : 16, 32),
              children: [
          a(_Hero(name: auth.name, team: team, teamCount: teams.length)),
          const SizedBox(height: 12),
          // Несколько команд — переключение одним касанием, всё ниже показывается по выбранной.
          if (teams.length > 1) ...[const TeamSwitcher(), const SizedBox(height: 8)],
          if (running != null) ...[
            a(_RunningCard(session: running)),
            const SizedBox(height: 12),
          ],
          a(const _NextUp()),
          const SizedBox(height: 12),
          a(const _QuickActions()),
          if (needReport.isNotEmpty) ...[
            const SizedBox(height: 16),
            a(DashCard(
              title: 'Ждут отчёта',
              child: Column(children: [
                for (final s in needReport)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.rate_review_outlined, color: AppColors.red),
                    title: Text(s.title),
                    subtitle: Text(formatWhen(s.finishedAt)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/sessions/${s.id}/report'),
                  ),
              ]),
            )),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: Text('ПУЛЬС КОМАНДЫ',
                  style: TextStyle(fontFamily: AppTheme.display, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ),
            if (team != null)
              TextButton(onPressed: () => context.go('/team?tab=1'), child: const Text('Весь дашборд →')),
          ]),
          const SizedBox(height: 8),
          if (team == null || players.isEmpty)
            a(_EmptyPulse(demo: auth.demo, hasTeam: team != null))
          else
            TeamDashboard(team: team, embedded: true),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 16),
            a(DashCard(
              title: 'Недавние занятия',
              child: Column(children: [for (final s in done.take(3)) SessionTile(s)]),
            )),
          ],
        ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- шапка

class _Hero extends ConsumerWidget {
  const _Hero({required this.name, required this.team, required this.teamCount});

  final String name;
  final Team? team;
  final int teamCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    const greet = 'Привет';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE30613), Color(0xFF8A0710), Color(0xFF1A0A0B)],
          stops: [0, 0.45, 1],
        ),
        boxShadow: [BoxShadow(color: AppColors.red.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))],
      ),
      child: Stack(children: [
        // Разметка поля на фоне — фирменная «тактическая» графика.
        const Positioned.fill(child: CustomPaint(painter: _PitchLines())),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 10, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(AppBrand.label.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 2, color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              const SyncBadge(),
            ]),
            const SizedBox(height: 6),
            Text(
              name.isEmpty ? greet : '$greet, $name',
              style: const TextStyle(fontFamily: AppTheme.display, fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, height: 1.05),
            ),
            const SizedBox(height: 4),
            Text(_cap(DateFormat('EEEE, d MMMM', 'ru').format(now)), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            if (team != null)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.go('/team'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_outlined, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      // Возраст — только если его нет в названии: «Академия U16», а не «Академия U16 · U16».
                      team!.name.contains(AgeGroups.label(team!.ageGroup))
                          ? team!.name
                          : '${team!.name} · ${AgeGroups.label(team!.ageGroup)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white, size: 18),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _PitchLines extends CustomPainter {
  const _PitchLines();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.86, h * 0.5), h * 0.42, p);
    canvas.drawLine(Offset(w * 0.86, -10), Offset(w * 0.86, h + 10), p);
    canvas.drawRect(Rect.fromLTWH(w * 0.62, h * 0.18, w * 0.5, h * 0.64), p);
    // Стрелка движения пунктиром.
    final path = Path()
      ..moveTo(w * 0.55, h * 0.85)
      ..quadraticBezierTo(w * 0.7, h * 0.2, w * 0.95, h * 0.18);
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12) {
        canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), p..color = Colors.white.withValues(alpha: 0.18));
      }
    }
  }

  @override
  bool shouldRepaint(_PitchLines oldDelegate) => false;
}

// ---------------------------------------------------------------- что дальше

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.session});

  final TrainingSession session;

  @override
  Widget build(BuildContext context) => Container(
        decoration: cardDecoration(accent: true),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.timer_outlined, color: AppColors.red, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ИДЁТ ЗАНЯТИЕ', semanticsLabel: 'Идёт занятие', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: AppColors.textMuted)),
              Text(session.title, style: const TextStyle(fontFamily: AppTheme.display, fontSize: 20, fontWeight: FontWeight.w600)),
            ]),
          ),
          FilledButton(onPressed: () => context.push('/run/${session.id}'), child: const Text('Продолжить')),
        ]),
      );
}

/// Ближайшее событие из календаря: матч, тренировка с планом или по расписанию.
class _NextUp extends ConsumerWidget {
  const _NextUp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final matches = ref.watch(matchesProvider).value ?? const <Match>[];
    final slots = ref.watch(slotsProvider).value ?? const <ScheduleSlot>[];
    final sessions = ref.watch(sessionsProvider).value ?? const <TrainingSession>[];
    final now = DateTime.now();
    // Ближайшее событие выбранной команды.
    final current = ref.watch(currentTeamProvider);
    CalendarEvent? next;
    for (var d = 0; d < 14 && next == null; d++) {
      final day = dayOf(now).add(Duration(days: d));
      next = eventsForDay(day, matches: matches, slots: slots, sessions: sessions, teamIds: current == null ? null : {current.id})
          .where((e) => e.end.isAfter(now) && (e.session == null || e.session!.status != 'done'))
          .firstOrNull;
    }
    if (next == null) {
      return Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Icon(Icons.event_available_outlined, color: AppColors.textMuted, size: 30),
          const SizedBox(width: 12),
          const Expanded(child: Text('Ближайших событий нет. Добавьте расписание тренировок и матчи сезона.')),
          TextButton(onPressed: () => context.go('/calendar'), child: const Text('Календарь')),
        ]),
      );
    }
    final e = next;
    final team = teams.where((t) => t.id == e.teamId).firstOrNull;
    final diff = e.start.difference(now);
    final when = diff.isNegative
        ? 'идёт сейчас'
        : diff.inMinutes < 60
            ? 'через ${diff.inMinutes} мин'
            : diff.inHours < 24 && e.start.day == now.day
                ? 'сегодня в ${hm(e.start)}'
                : sameDay(e.start, now.add(const Duration(days: 1)))
                    ? 'завтра в ${hm(e.start)}'
                    : DateFormat('EEEE, d MMMM, HH:mm', 'ru').format(e.start);
    final isMatch = e.kind == CalendarKind.match;
    return Container(
      decoration: cardDecoration(accent: isMatch),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isMatch ? Icons.sports_soccer : Icons.event_note, color: AppColors.red, size: 18),
          const SizedBox(width: 6),
          Text(isMatch ? 'БЛИЖАЙШИЙ МАТЧ' : 'БЛИЖАЙШАЯ ТРЕНИРОВКА',
              style: const TextStyle(fontSize: 11, letterSpacing: 1.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(8)),
            child: Text(when, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          isMatch ? '${e.match!.home ? '' : '@ '}${e.match!.opponent}' : e.title,
          style: const TextStyle(fontFamily: AppTheme.display, fontSize: 24, fontWeight: FontWeight.w700),
        ),
        Text(
          [
            '${hm(e.start)}–${hm(e.end)}',
            if (team != null) team.name,
            if (isMatch) e.match!.home ? 'дома' : 'в гостях',
            if (e.slot?.location.isNotEmpty ?? false) e.slot!.location,
            if (isMatch && e.match!.venue.isNotEmpty) e.match!.venue,
          ].join(' · '),
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              icon: Icon(switch (e.kind) {
                CalendarKind.match => Icons.query_stats,
                CalendarKind.training => Icons.play_arrow,
                CalendarKind.slot => Icons.edit_calendar_outlined,
              }),
              label: Text(switch (e.kind) {
                CalendarKind.match => 'Матч и статистика',
                CalendarKind.training => 'Провести',
                CalendarKind.slot => 'Составить план',
              }),
              onPressed: () => switch (e.kind) {
                CalendarKind.match => context.push('/calendar/match/${e.match!.id}'),
                CalendarKind.training => context.push('/run/${e.session!.id}'),
                CalendarKind.slot =>
                  createSessionAt(context, ref, e.start, teamId: e.slot!.teamId, title: e.slot!.title, durationMin: e.slot!.durationMin),
              },
            ),
          ),
          if (e.kind == CalendarKind.training) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => context.push('/sessions/${e.session!.id}'), child: const Text('План')),
          ],
          if (isMatch) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/tactics'),
              icon: const Icon(Icons.draw_outlined, size: 18),
              label: const Text('Тактика'),
            ),
          ],
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- быстрые действия

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.auto_awesome, 'Конструктор\nтренировки', () => context.push('/sessions/new')),
      (Icons.calendar_month_outlined, 'Календарь\nсезона', () => context.go('/calendar')),
      (Icons.draw_outlined, 'Тактическая\nдоска', () => context.push('/tactics')),
      (Icons.insights_outlined, 'Дашборд\nкоманды', () => context.go('/team?tab=1')),
      (Icons.query_stats, 'Статистика\nигроков', () => context.go('/team?tab=2')),
      (Icons.menu_book_outlined, 'Библиотека\nупражнений', () => context.go('/library')),
    ];
    // Плитки фиксированной высоты: 3 в ряд, на широком экране — все 6 в один ряд.
    return LayoutBuilder(
      builder: (context, box) => GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: box.maxWidth >= 720 ? 6 : 3,
        mainAxisExtent: 108,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      children: [
        for (var k = 0; k < items.length; k++)
          Semantics(
            label: k == 0 ? 'Конструктор тренировки' : items[k].$2.replaceAll('\n', ' '),
            button: true,
            excludeSemantics: true,
            child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: cardDecoration(accent: k == 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: items[k].$3,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: k == 0 ? AppColors.red : AppColors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(items[k].$1, color: k == 0 ? Colors.white : AppColors.red, size: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      items[k].$2,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          ),
      ],
    ),
    );
  }
}

class _EmptyPulse extends ConsumerWidget {
  const _EmptyPulse({required this.demo, required this.hasTeam});

  final bool demo, hasTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        decoration: cardDecoration(),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.insights_outlined, size: 40, color: AppColors.red),
          const SizedBox(height: 8),
          const Text(
            'Здесь появится дашборд: посещаемость, нагрузка, тесты ОФП, результаты матчей и лидеры команды.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          if (demo)
            FilledButton.icon(
              onPressed: () => fillDemoExample(context, ref),
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              label: const Text('Показать на примере'),
            )
          else
            FilledButton.icon(
              onPressed: () => hasTeam ? context.go('/team') : context.push('/team/new'),
              icon: const Icon(Icons.person_add_alt),
              label: Text(hasTeam ? 'Добавить игроков' : 'Создать команду'),
            ),
        ]),
      );
}
