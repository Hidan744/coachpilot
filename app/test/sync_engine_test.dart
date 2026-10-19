// Интеграционный тест синхронизации: два «устройства» (две локальные БД)
// работают через настоящий backend. Запуск:
//   CP_API_URL=http://localhost:8000 flutter test test/sync_engine_test.dart
// Без CP_API_URL тест пропускается.
import 'dart:io';
import 'dart:math';

import 'package:coachpilot/data/db.dart';
import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/data/repo.dart';
import 'package:coachpilot/sync/api_client.dart';
import 'package:coachpilot/sync/sync_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class Device {
  Device(String url, TokenStore tokens)
      : db = AppDb(NativeDatabase.memory()),
        api = ApiClient(baseUrl: url, tokens: tokens) {
    repo = Repo(db);
    sync = SyncEngine(db, api);
  }

  final AppDb db;
  final ApiClient api;
  late final Repo repo;
  late final SyncEngine sync;
}

void main() {
  final url = Platform.environment['CP_API_URL'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('SyncEngine (backend: $url)', skip: url == null ? 'CP_API_URL не задан' : null, () {
    late Device phone, tablet;

    setUp(() async {
      final tokens = MemoryTokenStore(); // один аккаунт на двух устройствах
      phone = Device(url!, tokens);
      tablet = Device(url, tokens);
      final email = 'sync${Random().nextInt(1 << 32)}@test.ru';
      final t = await phone.api.postPublic('/auth/register', {
        'email': email,
        'password': 'secret123',
        'name': 'Тест',
        'consent_personal_data': true,
      });
      await phone.api.saveTokens(t as Json);
    });

    tearDown(() async {
      await phone.db.close();
      await tablet.db.close();
    });

    test('офлайн-создание на одном устройстве появляется на другом', () async {
      final team = Team(id: newId(), name: 'U12 Звезда', ageGroup: 'U12', level: 'amateur', defaultPlayers: 14);
      await phone.repo.put(Entities.teams, team);
      final p = Player(id: newId(), teamId: team.id, firstName: 'Саша', birthYear: 2014);
      await phone.repo.put(Entities.players, p);
      expect(await phone.repo.watchPendingCount().first, 2);

      await phone.sync.sync();
      expect(phone.sync.current.error, isNull);
      expect(await phone.repo.watchPendingCount().first, 0);

      await tablet.sync.sync();
      final teams = await tablet.repo.watchTeams().first;
      expect(teams.single.name, 'U12 Звезда');
      final players = await tablet.repo.watchPlayers(team.id).first;
      expect(players.single.firstName, 'Саша');
    });

    test('удаление доходит до другого устройства', () async {
      final team = Team(id: newId(), name: 'T', ageGroup: 'U10', level: 'beginner', defaultPlayers: 10);
      await phone.repo.put(Entities.teams, team);
      await phone.sync.sync();
      await tablet.sync.sync();
      expect((await tablet.repo.watchTeams().first).length, 1);

      await tablet.repo.remove(Entities.teams, team.id);
      await tablet.sync.sync();
      await phone.sync.sync();
      expect(await phone.repo.watchTeams().first, isEmpty);
    });

    test('конфликт плана: правка не теряется, сохраняется копией', () async {
      final s = TrainingSession(
        id: newId(),
        title: 'Передачи',
        durationMin: 60,
        blocks: const [TrainingBlock(id: 'b1', phase: 'warmup', title: 'Разминка', durationMin: 60)],
      );
      await phone.repo.put(Entities.sessions, s);
      await phone.sync.sync();
      await tablet.sync.sync();

      // Оба устройства правят план офлайн от одной версии.
      await phone.repo.put(Entities.sessions, s.copyWith(title: 'Передачи — телефон'));
      await tablet.repo.put(Entities.sessions, s.copyWith(title: 'Передачи — планшет'));
      await phone.sync.sync();
      await tablet.sync.sync();
      expect(tablet.sync.current.conflicts, 1);

      final onTablet = await tablet.repo.watchSessions().first;
      final titles = onTablet.map((e) => e.title).toSet();
      expect(titles, {'Передачи — телефон', 'Передачи — планшет (конфликт)'});
      final copy = onTablet.firstWhere((e) => e.conflictOf != null);
      expect(copy.conflictOf, s.id);

      // Копия синхронизировалась и видна на телефоне.
      await phone.sync.sync();
      expect((await phone.repo.watchSessions().first).length, 2);
      expect(await tablet.repo.watchPendingCount().first, 0);
    });

    test('посещаемость с двух устройств сходится в одну запись', () async {
      final team = Team(id: newId(), name: 'T', ageGroup: 'U10', level: 'beginner', defaultPlayers: 10);
      final p = Player(id: newId(), teamId: team.id, firstName: 'Миша');
      final s = TrainingSession(id: newId(), teamId: team.id, title: 'S', durationMin: 60);
      await phone.repo.put(Entities.teams, team);
      await phone.repo.put(Entities.players, p);
      await phone.repo.put(Entities.sessions, s);
      await phone.sync.sync();
      await tablet.sync.sync();

      final aid = attendanceId(s.id, p.id);
      await phone.repo.put(Entities.attendance, Attendance(id: aid, sessionId: s.id, playerId: p.id, status: 'present'));
      await tablet.repo.put(Entities.attendance, Attendance(id: aid, sessionId: s.id, playerId: p.id, status: 'late'));
      await phone.sync.sync();
      await tablet.sync.sync();
      await phone.sync.sync();

      final a1 = await phone.repo.watchAttendance(s.id).first;
      final a2 = await tablet.repo.watchAttendance(s.id).first;
      expect(a1.single.status, 'late');
      expect(a2.single.status, 'late');
    });

    test('сервер недоступен — данные остаются в очереди, ошибка понятная', () async {
      final offline = Device('http://127.0.0.1:9', MemoryTokenStore());
      await offline.repo.put(
          Entities.teams, Team(id: newId(), name: 'Off', ageGroup: 'U9', level: 'beginner', defaultPlayers: 8));
      await offline.sync.sync();
      expect(offline.sync.current.error, contains('Нет связи'));
      expect(await offline.repo.watchPendingCount().first, 1);
      expect((await offline.repo.watchTeams().first).single.name, 'Off');
      await offline.db.close();
    });

    test('избранное системного упражнения у двух пользователей не конфликтует', () async {
      final catalog = await phone.api.get('/catalog/drills') as Json;
      final drills = (catalog['drills'] as List).cast<Json>();
      if (drills.isEmpty) return; // каталог не загружен на тестовом сервере
      final drillId = drills.first['id'] as String;

      final other = Device(url!, MemoryTokenStore());
      final t = await other.api.postPublic('/auth/register', {
        'email': 'fav${Random().nextInt(1 << 32)}@test.ru',
        'password': 'secret123',
        'name': 'Другой',
        'consent_personal_data': true,
      });
      await other.api.saveTokens(t as Json);
      final me1 = await phone.api.get('/me') as Json;
      final me2 = await other.api.get('/me') as Json;
      await phone.db.setKv('user_id', me1['id'] as String);
      await other.db.setKv('user_id', me2['id'] as String);

      await phone.repo.setFavorite(drillId, true);
      await other.repo.setFavorite(drillId, true);
      await phone.sync.sync();
      await other.sync.sync();
      expect(await phone.repo.watchFailed().first, isEmpty);
      expect(await other.repo.watchFailed().first, isEmpty);
      expect(await other.repo.watchFavoriteDrillIds().first, {drillId});
      await other.db.close();
    });

    test('отклонённая сервером запись помечается как failed и не блокирует остальные', () async {
      await phone.repo.putJson(Entities.teams, newId(), {'name': '', 'age_group': 'U9', 'level': 'x', 'default_players': 0});
      await phone.repo.put(
          Entities.teams, Team(id: newId(), name: 'OK', ageGroup: 'U9', level: 'beginner', defaultPlayers: 8));
      await phone.sync.sync();
      final failed = await phone.repo.watchFailed().first;
      expect(failed.single.error, startsWith('validation:'));
      expect(await phone.repo.watchPendingCount().first, 0);
    });
  });
}
