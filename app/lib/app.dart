import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'ui/screens/auth/auth_screens.dart';
import 'ui/screens/auth/onboarding_screen.dart';
import 'ui/screens/calendar/calendar_screen.dart';
import 'ui/screens/calendar/import_matches_screen.dart';
import 'ui/screens/home/home_screen.dart';
import 'ui/screens/library/library_screens.dart';
import 'ui/screens/profile/profile_screen.dart';
import 'ui/screens/sessions/report_screens.dart';
import 'ui/screens/sessions/run_screen.dart';
import 'ui/screens/sessions/sessions_screens.dart';
import 'ui/screens/tactics/tactics_screens.dart';
import 'ui/screens/team/player_development.dart';
import 'ui/screens/team/team_screens.dart';
import 'ui/theme.dart';

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
        GoRoute(path: ':id', builder: (_, s) => TacticBoardScreen(boardId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/run/:id', builder: (_, s) => RunScreen(sessionId: s.pathParameters['id']!)),
      GoRoute(
        path: '/attendance/:sessionId',
        builder: (_, s) => AttendanceScreen(sessionId: s.pathParameters['sessionId']!, teamId: s.uri.queryParameters['team']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/calendar', builder: (_, _) => const PlanningScreen(), routes: [
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
              ),
              GoRoute(path: 'import', builder: (_, _) => const ImportMatchesScreen()),
            ]),
            GoRoute(path: '/sessions', builder: (_, _) => const SessionsScreen(), routes: [
              GoRoute(path: 'new', builder: (_, _) => const AiWizardScreen()),
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
            GoRoute(path: '/team', builder: (_, _) => const TeamScreen(), routes: [
              GoRoute(path: 'new', builder: (_, _) => const TeamEditScreen()),
              GoRoute(path: 'edit/:id', builder: (_, s) => TeamEditScreen(teamId: s.pathParameters['id'])),
              GoRoute(path: 'player/:id', builder: (_, s) => PlayerScreen(playerId: s.pathParameters['id']!), routes: [
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
      );
}
