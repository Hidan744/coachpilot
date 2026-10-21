import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'ui/screens/auth/auth_screens.dart';
import 'ui/screens/auth/onboarding_screen.dart';
import 'ui/screens/calendar/calendar_screen.dart';
import 'ui/screens/calendar/import_matches_screen.dart';
import 'ui/screens/calendar/live_match_screen.dart';
import 'ui/screens/calendar/match_stats_screen.dart';
import 'ui/screens/home/home_screen.dart';
import 'ui/screens/library/library_screens.dart';
import 'ui/screens/profile/profile_screen.dart';
import 'ui/screens/sessions/report_screens.dart';
import 'ui/screens/sessions/run_screen.dart';
import 'ui/screens/sessions/sessions_screens.dart';
import 'ui/screens/tactics/lineup_screen.dart';
import 'ui/screens/team/advice_screen.dart';
import 'ui/screens/tactics/tactics_screens.dart';
import 'ui/screens/team/player_development.dart';
import 'ui/screens/team/player_profile.dart';
import 'ui/screens/team/progress_report.dart';
import 'ui/screens/team/team_screens.dart';
import 'ui/theme.dart';
import 'ui/widgets/demo_frame.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.listen(onboardedProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final isAuthPage = loc == '/login' || loc == '/register';
      // Пока идёт загрузка, запоминаем, куда шёл пользователь (прямая ссылка, перезапуск).
      String toSplash() => loc == '/splash'
          ? '/splash${state.uri.hasQuery ? '?${state.uri.query}' : ''}'
          : Uri(path: '/splash', queryParameters: {'from': state.uri.toString()}).toString();
      if (!auth.ready) return loc == '/splash' ? null : toSplash();
      if (!auth.signedIn) return isAuthPage ? null : '/login';
      final onboarded = ref.read(onboardedProvider);
      if (!onboarded.hasValue) return loc == '/splash' ? null : toSplash();
      if (onboarded.value == false) return loc == '/onboarding' ? null : '/onboarding';
      if (loc == '/splash') {
        final from = state.uri.queryParameters['from'];
        return from != null && !from.startsWith('/splash') && from != '/login' ? from : '/home';
      }
      if (isAuthPage || loc == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/tactics', builder: (_, _) => const TacticsListScreen(), routes: [
        GoRoute(path: 'lineup', builder: (_, s) => LineupScreen(formation: s.uri.queryParameters['formation'])),
        GoRoute(path: ':id', builder: (_, s) => TacticBoardScreen(boardId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/run/:id', builder: (_, s) => RunScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(
        path: '/attendance/:sessionId',
        builder: (_, s) => AttendanceScreen(sessionId: s.pathParameters['sessionId']!, teamId: s.uri.queryParameters['team']!),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => _Shell(shell),
        navigatorContainerBuilder: (context, shell, children) => _FadingBranches(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/calendar',
                builder: (_, s) => PlanningScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0),
                routes: [
              GoRoute(path: 'slots', builder: (_, _) => const SlotsScreen()),
              GoRoute(
                path: 'slot/:id',
                builder: (_, s) => SlotFormScreen(slotId: s.pathParameters['id'] == 'new' ? null : s.pathParameters['id']),
              ),
              GoRoute(
                path: 'match/:id',
                builder: (_, s) => MatchFormScreen(
                  matchId: s.pathParameters['id'] == 'new' ? null : s.pathParameters['id'],
                  day: DateTime.tryParse(s.uri.queryParameters['day'] ?? ''),
                ),
                routes: [
                  GoRoute(path: 'stats', builder: (_, s) => MatchStatsScreen(matchId: s.pathParameters['id']!)),
                  GoRoute(path: 'live', builder: (_, s) => LiveMatchScreen(matchId: s.pathParameters['id']!)),
                ],
              ),
              GoRoute(path: 'import', builder: (_, _) => const ImportMatchesScreen()),
            ]),
            GoRoute(path: '/sessions', builder: (_, _) => const SessionsScreen(), routes: [
              GoRoute(
                path: 'new',
                builder: (_, s) => AiWizardScreen(goal: s.uri.queryParameters['goal'], intensity: s.uri.queryParameters['intensity']),
              ),
              GoRoute(path: ':id', builder: (_, s) => PlanEditorScreen(sessionId: s.pathParameters['id']!)),
              GoRoute(path: ':id/summary', builder: (_, s) => SessionSummaryScreen(sessionId: s.pathParameters['id']!)),
              GoRoute(path: ':id/report', builder: (_, s) => ReportScreen(sessionId: s.pathParameters['id']!)),
            ]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/library', builder: (_, _) => const LibraryScreen(), routes: [
              GoRoute(path: 'drill/:id', builder: (_, s) => DrillScreen(drillId: s.pathParameters['id']!)),
              GoRoute(
                path: 'edit/:id',
                builder: (_, s) => DrillEditScreen(drillId: s.pathParameters['id'] == 'new' ? null : s.pathParameters['id']),
              ),
            ]),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/team',
                builder: (_, s) {
                  final tab = int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0;
                  return TeamScreen(key: ValueKey('team_tab_$tab'), initialTab: tab);
                },
                routes: [
              GoRoute(path: 'advice', builder: (_, _) => const AdviceScreen()),
              GoRoute(path: 'new', builder: (_, _) => const TeamEditScreen()),
              GoRoute(path: 'edit/:id', builder: (_, s) => TeamEditScreen(teamId: s.pathParameters['id'])),
              GoRoute(
                  path: 'player/:id',
                  builder: (_, s) => PlayerScreen(
                        playerId: s.pathParameters['id']!,
                        initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
                      ),
                  routes: [
                GoRoute(
                  path: 'test/:testId',
                  builder: (_, s) => PhysicalTestScreen(
                    playerId: s.pathParameters['id']!,
                    testId: s.pathParameters['testId'] == 'new' ? null : s.pathParameters['testId'],
                  ),
                ),
                GoRoute(path: 'report', builder: (_, s) => ProgressReportScreen(playerId: s.pathParameters['id']!)),
                GoRoute(
                  path: 'plan/:planId',
                  builder: (_, s) => DevPlanScreen(
                    playerId: s.pathParameters['id']!,
                    planId: s.pathParameters['planId'] == 'new' ? null : s.pathParameters['planId'],
                  ),
                ),
              ]),
            ]),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});

/// Вкладки нижнего меню сменяются плавно; неактивные остаются в памяти (состояние экранов сохраняется).
class _FadingBranches extends StatelessWidget {
  const _FadingBranches({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: ExcludeSemantics(
              excluding: i != index,
              // Анимация затухания — снаружи TickerMode: уходящая вкладка должна успеть погаснуть.
              child: AnimatedOpacity(
                opacity: i == index ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: AnimatedSlide(
                  offset: i == index ? Offset.zero : const Offset(0, 0.015),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: TickerMode(enabled: i == index, child: children[i]),
                ),
              ),
            ),
          ),
      ]);
}

class _Shell extends StatelessWidget {
  const _Shell(this.shell);

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Главная'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Календарь'),
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Библиотека'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Команда'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Профиль'),
          ],
        ),
      );
}

class CoachPilotApp extends ConsumerWidget {
  const CoachPilotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'CoachPilot',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: ref.watch(routerProvider),
        // В демо на компьютере приложение показывается в рамке телефона, как на мобильном.
        builder: demoOnly ? (context, child) => DemoFrame(onOpen: (path) => _openFromShowcase(ref, path), child: child!) : null,
      );

  /// Вкладки нижнего меню открываются как вкладки, остальные экраны — поверх, с кнопкой «назад».
  static void _openFromShowcase(WidgetRef ref, String path) {
    final router = ref.read(routerProvider);
    const tabs = ['/', '/calendar', '/library', '/team', '/profile'];
    tabs.contains(Uri.parse(path).path) ? router.go(path) : router.push(path);
  }
}
