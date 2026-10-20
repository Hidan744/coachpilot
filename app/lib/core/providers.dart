import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import 'analytics.dart';
import 'demo_data.dart';
import '../data/models.dart';
import '../data/repo.dart';
import '../sync/api_client.dart';
import '../sync/sync_engine.dart';

const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

/// Сборка-демо без сервера (публичная web-версия): сразу открывается демо-режим.
const demoOnly = bool.fromEnvironment('DEMO_ONLY');

/// Демо сразу с примером: команда, тренировки, матчи, статистика, ОФП — всё видно с первого экрана.
const demoSample = bool.fromEnvironment('DEMO_SAMPLE');

/// Переопределяются в main() и в тестах.
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError());
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiProvider = Provider<ApiClient>((ref) => ApiClient(baseUrl: apiUrl, tokens: ref.watch(tokenStoreProvider)));

final analyticsProvider = Provider<Analytics>((ref) => Analytics(ref.watch(dbProvider), ref.watch(apiProvider)));

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(dbProvider), ref.watch(apiProvider));
  final analytics = ref.watch(analyticsProvider);
  engine.afterSync = (status) async {
    if (status.conflicts > 0) await analytics.track('sync_conflict', {'count': status.conflicts});
    if (status.error == null) await analytics.flush();
  };
  ref.onDispose(engine.dispose);
  return engine;
});

final repoProvider = Provider<Repo>((ref) {
  final repo = Repo(ref.watch(dbProvider));
  Timer? debounce;
  // Локальная правка → синхронизация через 2 секунды (правки подряд объединяются).
  repo.onLocalChange = () {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () {
      final auth = ref.read(authProvider);
      if (auth.signedIn && !auth.demo) ref.read(syncEngineProvider).sync();
    });
  };
  ref.onDispose(() => debounce?.cancel());
  return repo;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.status;
});

final pendingCountProvider = StreamProvider<int>((ref) => ref.watch(repoProvider).watchPendingCount());

// ------------------------------------------------------------------ авторизация

class AuthState {
  const AuthState({this.ready = false, this.signedIn = false, this.profile, this.demo = false});

  final bool ready;
  final bool signedIn;
  final Json? profile;

  /// Демо-режим: без аккаунта и сервера, данные только на этом устройстве, планы без AI.
  final bool demo;

  String get name => profile?['name'] as String? ?? '';
}

class AuthController extends Notifier<AuthState> {
  static const _profileKey = 'profile';

  AppDb get _db => ref.read(dbProvider);
  ApiClient get _api => ref.read(apiProvider);

  Timer? _periodic;
  StreamSubscription? _connectivity;

  @override
  AuthState build() {
    ref.onDispose(_stopBackgroundSync);
    _api.onSessionExpired = () => logout(remote: false);
    Future.microtask(_restore);
    return const AuthState();
  }

  /// Вход без сети: если на устройстве есть сессия, пускаем сразу с сохранённым профилем.
  Future<void> _restore() async {
    if (await _db.getKv(_demoKey) == '1') {
      state = AuthState(ready: true, signedIn: true, demo: true, profile: _demoProfile);
      return;
    }
    if (demoOnly) return startDemo();
    if (await _api.hasSession) {
      final cached = await _db.getKv(_profileKey);
      state = AuthState(ready: true, signedIn: true, profile: cached == null ? null : jsonDecode(cached) as Json);
      unawaited(ref.read(analyticsProvider).track('app_open'));
      _startBackgroundSync();
      unawaited(_refreshProfile());
    } else {
      state = const AuthState(ready: true);
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final me = await _api.get('/me') as Json;
      await _db.setKv(_profileKey, jsonEncode(me));
      if (state.signedIn) state = AuthState(ready: true, signedIn: true, profile: me);
    } on ApiException {
      // офлайн — остаёмся с сохранённым профилем
    }
  }

  Future<void> login(String email, String password) =>
      _signIn(_api.postPublic('/auth/login', {'email': email.trim(), 'password': password}));

  Future<void> register(String name, String email, String password) => _signIn(signup: true, _api.postPublic('/auth/register', {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'consent_personal_data': true,
      }));

  Future<void> _signIn(Future<dynamic> request, {bool signup = false}) async {
    final tokens = await request as Json;
    await _api.saveTokens(tokens);
    final me = await _api.get('/me') as Json;
    // Другой аккаунт на этом устройстве — локальные данные прежнего не смешиваем.
    final prevUser = await _db.getKv('user_id');
    if (prevUser != null && prevUser != me['id']) await _db.wipe();
    await _db.setKv('user_id', me['id'] as String);
    await _db.setKv(_profileKey, jsonEncode(me));
    // Первая синхронизация до входа в приложение: на новом устройстве сразу видны данные.
    await ref.read(syncEngineProvider).sync().timeout(const Duration(seconds: 20), onTimeout: () {});
    state = AuthState(ready: true, signedIn: true, profile: me);
    unawaited(ref.read(analyticsProvider).track(signup ? 'signup' : 'login'));
    _startBackgroundSync();
  }

  Future<void> updateProfile(Json changes) async {
    final me = await _api.patch('/me', changes) as Json;
    await _db.setKv(_profileKey, jsonEncode(me));
    state = AuthState(ready: true, signedIn: true, profile: me);
  }

  static const _demoKey = 'demo';

  /// Версия примера данных: при изменении примера старые демо-данные в браузере заменяются новыми.
  static const _sampleKey = 'demo_sample';
  static const _sampleVersion = '3';
  static const _demoProfile = {'name': 'Тренер', 'email': 'Демо-режим'};

  /// Попробовать без регистрации: всё работает на устройстве, без синхронизации и AI.
  Future<void> startDemo() async {
    if (demoSample && await _db.getKv('demo_empty') != '1') {
      final repo = ref.read(repoProvider);
      final hasTeams = (await repo.list(Entities.teams, Team.fromJson)).isNotEmpty;
      // Пример обновился с прошлого визита (или его не было) — заполняем заново,
      // чтобы все графики и статистика были на месте, а не старые пустые данные.
      if (!hasTeams || await _db.getKv(_sampleKey) != _sampleVersion) {
        if (hasTeams) await _db.wipe();
        final teamId = await _db.transaction(() => seedDemoData(repo));
        await _db.setKv('current_team', teamId);
        await _db.setKv(_sampleKey, _sampleVersion);
        ref.read(currentTeamIdProvider.notifier).select(teamId);
      }
    }
    await _db.setKv(_demoKey, '1');
    unawaited(ref.read(analyticsProvider).track('demo_started'));
    state = const AuthState(ready: true, signedIn: true, demo: true, profile: _demoProfile);
  }

  /// Начать демо заново: с примером данных или с чистого листа.
  Future<void> resetDemo({required bool sample}) async {
    await _db.wipe();
    await _db.deleteKv(_demoKey);
    if (!sample) await _db.setKv('demo_empty', '1');
    state = const AuthState(ready: true);
    if (sample) {
      // Пример заполняется сразу, без онбординга.
      final repo = ref.read(repoProvider);
      final teamId = await _db.transaction(() => seedDemoData(repo));
      await _db.setKv('current_team', teamId);
      await _db.setKv(_sampleKey, _sampleVersion);
      ref.read(currentTeamIdProvider.notifier).select(teamId);
    }
    await startDemo();
  }

  Future<void> logout({bool remote = true}) async {
    _stopBackgroundSync();
    if (state.demo) {
      await _db.wipe();
      await _db.deleteKv(_demoKey);
      state = const AuthState(ready: true);
      if (demoOnly) await startDemo();
      return;
    }
    if (remote) {
      final refresh = await _api.refreshToken;
      if (refresh != null) {
        try {
          await _api.postPublic('/auth/logout', {'refresh_token': refresh});
        } on ApiException {
          // офлайн — токен истечёт сам
        }
      }
    }
    await _api.clearTokens();
    await _db.wipe();
    state = const AuthState(ready: true);
  }

  Future<void> deleteAccount(String password) async {
    await _api.post('/account/delete', {'password': password});
    await logout(remote: false);
  }

  void _startBackgroundSync() {
    _stopBackgroundSync();
    final engine = ref.read(syncEngineProvider);
    unawaited(engine.sync());
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => engine.sync());
    try {
      _connectivity = Connectivity().onConnectivityChanged.listen((r) {
        if (!r.contains(ConnectivityResult.none)) engine.sync();
      });
    } catch (_) {
      // плагин недоступен (тесты) — работает периодическая синхронизация
    }
  }

  void _stopBackgroundSync() {
    _periodic?.cancel();
    _connectivity?.cancel();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

// ------------------------------------------------------------------ данные

final teamsProvider = StreamProvider<List<Team>>((ref) => ref.watch(repoProvider).watchTeams());

final onboardedProvider = FutureProvider<bool>((ref) async {
  final teams = await ref.watch(teamsProvider.future);
  if (teams.isNotEmpty) return true;
  return await ref.watch(dbProvider).getKv('onboarding_skipped') == '1';
});

/// Текущая выбранная команда (сохраняется между запусками).
class CurrentTeamController extends Notifier<String?> {
  @override
  String? build() {
    Future.microtask(() async {
      final saved = await ref.read(dbProvider).getKv('current_team');
      if (saved != null && state == null) state = saved;
    });
    return null;
  }

  void select(String teamId) {
    state = teamId;
    ref.read(dbProvider).setKv('current_team', teamId);
  }
}

final currentTeamIdProvider = NotifierProvider<CurrentTeamController, String?>(CurrentTeamController.new);

final currentTeamProvider = Provider<Team?>((ref) {
  final teams = ref.watch(teamsProvider).value ?? [];
  if (teams.isEmpty) return null;
  final id = ref.watch(currentTeamIdProvider);
  return teams.firstWhere((t) => t.id == id, orElse: () => teams.first);
});
