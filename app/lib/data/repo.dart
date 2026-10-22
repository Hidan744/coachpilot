import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'models.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Детерминированный id отметки посещаемости: одна запись на игрока и занятие
/// независимо от устройства (на сервере uuid5(session_id, str(player_id))).
String attendanceId(String sessionId, String playerId) => _uuid.v5(sessionId, playerId);

/// Детерминированный id статистики игрока в матче: одна запись на игрока и матч.
String matchStatId(String matchId, String playerId) => _uuid.v5(matchId, 'stat:$playerId');

/// Локальный репозиторий: все записи сначала пишутся в SQLite и в outbox,
/// затем SyncEngine отправляет их на сервер.
class Repo {
  Repo(this.db);

  final AppDb db;

  /// Вызывается после каждой локальной правки, чтобы запустить синхронизацию.
  void Function()? onLocalChange;

  Future<void> put(String entity, Entity e) => putJson(entity, e.id, e.toJson());

  Future<void> putJson(String entity, String id, Json data) async {
    final parentField = Entities.parentField[entity];
    await db.transaction(() async {
      final existing = await _row(entity, id);
      await db.into(db.records).insertOnConflictUpdate(RecordsCompanion(
            entity: Value(entity),
            id: Value(id),
            data: Value(jsonEncode(data)),
            parentId: Value(parentField == null ? null : data[parentField] as String?),
            serverSeq: Value(existing?.serverSeq),
            deleted: const Value(false),
            system: Value(existing?.system ?? false),
            updatedAt: Value(DateTime.now()),
          ));
      await _enqueue(entity, id, 'upsert');
    });
    onLocalChange?.call();
  }

  Future<void> remove(String entity, String id) async {
    await db.transaction(() async {
      await (db.update(db.records)..where((t) => t.entity.equals(entity) & t.id.equals(id)))
          .write(RecordsCompanion(deleted: const Value(true), updatedAt: Value(DateTime.now())));
      await _enqueue(entity, id, 'delete');
    });
    onLocalChange?.call();
  }

  /// Резервная копия: все записи пользователя (без системного каталога) по сущностям.
  Future<Json> backup() async {
    final rows = await (db.select(db.records)..where((t) => t.deleted.equals(false) & t.system.equals(false))).get();
    final data = <String, List<Json>>{};
    for (final r in rows) {
      (data[r.entity] ??= []).add({'id': r.id, ...(jsonDecode(r.data) as Json)});
    }
    return {'app': 'CoachPilot', 'version': 1, 'created_at': DateTime.now().toIso8601String(), 'data': data};
  }

  /// Восстановление из резервной копии: записи добавляются или обновляются, ничего не удаляется.
  /// Возвращает число восстановленных записей.
  Future<int> restore(Json backup) async {
    if (backup['app'] != 'CoachPilot' || backup['data'] is! Map) {
      throw const FormatException('Это не резервная копия CoachPilot');
    }
    var n = 0;
    for (final e in (backup['data'] as Map).entries) {
      if (!Entities.all.contains(e.key) || e.value is! List) continue;
      for (final item in e.value as List) {
        if (item is! Map || item['id'] is! String) continue;
        final j = Map<String, dynamic>.from(item)..remove('id');
        await putJson(e.key as String, item['id'] as String, j);
        n++;
      }
    }
    return n;
  }

  Future<void> _enqueue(String entity, String id, String op) async {
    await (db.delete(db.outbox)..where((t) => t.entity.equals(entity) & t.recordId.equals(id))).go();
    await db.into(db.outbox).insert(
          OutboxCompanion.insert(entity: entity, recordId: id, op: op, createdAt: DateTime.now()),
        );
  }

  Future<LocalRecord?> _row(String entity, String id) =>
      (db.select(db.records)..where((t) => t.entity.equals(entity) & t.id.equals(id))).getSingleOrNull();

  SimpleSelectStatement<$RecordsTable, LocalRecord> _query(String entity, {String? parentId}) {
    final q = db.select(db.records)..where((t) => t.entity.equals(entity) & t.deleted.equals(false));
    if (parentId != null) q.where((t) => t.parentId.equals(parentId));
    return q..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]);
  }

  Stream<List<T>> watch<T>(String entity, T Function(String id, Json j) parse, {String? parentId}) =>
      _query(entity, parentId: parentId)
          .watch()
          .map((rows) => rows.map((r) => parse(r.id, jsonDecode(r.data) as Json)).toList());

  Future<List<T>> list<T>(String entity, T Function(String id, Json j) parse, {String? parentId}) async =>
      (await _query(entity, parentId: parentId).get())
          .map((r) => parse(r.id, jsonDecode(r.data) as Json))
          .toList();

  Stream<T?> watchOne<T>(String entity, String id, T Function(String id, Json j) parse) =>
      (db.select(db.records)
            ..where((t) => t.entity.equals(entity) & t.id.equals(id) & t.deleted.equals(false)))
          .watchSingleOrNull()
          .map((r) => r == null ? null : parse(r.id, jsonDecode(r.data) as Json));

  Future<T?> get<T>(String entity, String id, T Function(String id, Json j) parse) async {
    final r = await _row(entity, id);
    if (r == null || r.deleted) return null;
    return parse(r.id, jsonDecode(r.data) as Json);
  }

  // ------------------------------------------------------------- типизированные

  Stream<List<Team>> watchTeams() => watch(Entities.teams, Team.fromJson);
  Stream<List<Player>> watchPlayers(String teamId) =>
      watch(Entities.players, Player.fromJson, parentId: teamId);
  Stream<List<TrainingSession>> watchSessions() => watch(Entities.sessions, TrainingSession.fromJson);
  Stream<List<Drill>> watchDrills() => watch(Entities.drills, Drill.fromJson);
  Stream<List<Attendance>> watchAttendance(String sessionId) =>
      watch(Entities.attendance, Attendance.fromJson, parentId: sessionId);
  Stream<List<SessionNote>> watchNotes(String sessionId) =>
      watch(Entities.notes, SessionNote.fromJson, parentId: sessionId);
  Stream<List<SessionReport>> watchReports(String sessionId) =>
      watch(Entities.reports, SessionReport.fromJson, parentId: sessionId);
  Stream<List<PlayerAssessment>> watchAssessments(String playerId) =>
      watch(Entities.assessments, PlayerAssessment.fromJson, parentId: playerId);

  Stream<List<Match>> watchMatches() => watch(Entities.matches, Match.fromJson);
  Stream<List<ScheduleSlot>> watchSlots() => watch(Entities.slots, ScheduleSlot.fromJson);
  Stream<List<DevelopmentPlan>> watchDevPlans(String playerId) =>
      watch(Entities.devPlans, DevelopmentPlan.fromJson, parentId: playerId);
  Stream<List<ParentNote>> watchParentNotes(String playerId) =>
      watch(Entities.parentNotes, ParentNote.fromJson, parentId: playerId);
  Stream<List<TacticBoard>> watchBoards() => watch(Entities.boards, TacticBoard.fromJson);
  Stream<List<MatchStat>> watchMatchStats() => watch(Entities.matchStats, MatchStat.fromJson);
  Stream<List<PhysicalTest>> watchPhysicalTests() => watch(Entities.physicalTests, PhysicalTest.fromJson);
  Stream<List<StaffMember>> watchStaff() => watch(Entities.staff, StaffMember.fromJson);
  Stream<List<AdviceDecision>> watchAdviceDecisions(String teamId) =>
      watch(Entities.adviceDecisions, AdviceDecision.fromJson, parentId: teamId);

  Stream<Set<String>> watchFavoriteDrillIds() => watch(Entities.favorites, (id, j) => j['drill_id'] as String)
      .map((l) => l.toSet());

  /// Избранное: id детерминирован по пользователю и упражнению — повторное добавление
  /// с разных устройств сходится в одну запись, а у разных пользователей id не пересекаются.
  Future<void> setFavorite(String drillId, bool fav) async {
    final userId = await db.getKv('user_id') ?? 'local';
    final id = _uuid.v5(Namespace.url.value, 'favorite:$userId:$drillId');
    return fav ? putJson(Entities.favorites, id, {'drill_id': drillId}) : remove(Entities.favorites, id);
  }

  // ------------------------------------------------------------- статус синхронизации

  Stream<int> watchPendingCount() {
    final c = db.outbox.seq.count();
    return (db.selectOnly(db.outbox)
          ..addColumns([c])
          ..where(db.outbox.status.equals('pending')))
        .watchSingle()
        .map((r) => r.read(c) ?? 0);
  }

  Stream<List<OutboxEntry>> watchFailed() =>
      (db.select(db.outbox)..where((t) => t.status.equals('failed'))).watch();
}
