import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'api_client.dart';

class SyncStatus {
  const SyncStatus({this.running = false, this.lastSyncAt, this.error, this.conflicts = 0});

  final bool running;
  final DateTime? lastSyncAt;
  final String? error;

  /// Сколько конфликтных копий создано за последнюю синхронизацию.
  final int conflicts;
}

/// Синхронизация локальной БД с сервером: сначала push (outbox), затем pull по курсору,
/// затем обновление системной библиотеки упражнений.
class SyncEngine {
  SyncEngine(this.db, this.api);

  final AppDb db;
  final ApiClient api;

  static const _cursorKey = 'sync_cursor';
  static const _catalogKey = 'catalog_version';
  static const _batch = 200;

  final _status = StreamController<SyncStatus>.broadcast();
  SyncStatus _current = const SyncStatus();
  Future<void>? _inFlight;
  bool _again = false;

  /// Вызывается после каждой синхронизации (аналитика, отправка событий).
  Future<void> Function(SyncStatus status)? afterSync;

  Stream<SyncStatus> get status => _status.stream;
  SyncStatus get current => _current;

  void _emit(SyncStatus s) {
    _current = s;
    _status.add(s);
  }

  /// Запустить синхронизацию. Параллельные вызовы объединяются в один повторный проход.
  Future<void> sync() {
    if (_inFlight != null) {
      _again = true;
      return _inFlight!;
    }
    _inFlight = _run().whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<void> _run() async {
    _emit(SyncStatus(running: true, lastSyncAt: _current.lastSyncAt));
    var conflicts = 0;
    try {
      do {
        _again = false;
        conflicts += await _push();
        await _pull();
      } while (_again);
      await _catalog();
      _emit(SyncStatus(lastSyncAt: DateTime.now(), conflicts: conflicts));
    } on ApiException catch (e) {
      _emit(SyncStatus(lastSyncAt: _current.lastSyncAt, error: e.message, conflicts: conflicts));
    }
    try {
      await afterSync?.call(_current);
    } catch (_) {
      // побочные действия не должны ломать синхронизацию
    }
  }

  // ------------------------------------------------------------------ push

  Future<int> _push() async {
    var conflicts = 0;
    for (var round = 0; round < 20; round++) {
      final entries = await (db.select(db.outbox)
            ..where((t) => t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.seq)])
            ..limit(_batch))
          .get();
      if (entries.isEmpty) return conflicts;

      final changes = <Json>[];
      final sent = <OutboxEntry>[];
      for (final e in entries) {
        final row = await _row(e.entity, e.recordId);
        if (row == null || (row.system && e.op == 'upsert')) {
          await _dropEntry(e.seq);
          continue;
        }
        changes.add({
          'entity': e.entity,
          'id': e.recordId,
          'op': e.op,
          'base_seq': row.serverSeq,
          if (e.op == 'upsert') 'data': jsonDecode(row.data),
        });
        sent.add(e);
      }
      if (changes.isEmpty) continue;

      final resp = await api.post('/sync/push', {'changes': changes}) as Json;
      final results = (resp['results'] as List).cast<Json>();
      await db.transaction(() async {
        for (var i = 0; i < results.length; i++) {
          final r = results[i];
          final e = sent[i];
          switch (r['status']) {
            case 'applied':
              await (db.update(db.records)
                    ..where((t) => t.entity.equals(e.entity) & t.id.equals(e.recordId)))
                  .write(RecordsCompanion(serverSeq: Value(r['server_seq'] as int?)));
              await _dropEntry(e.seq);
            case 'conflict':
              conflicts += await _resolveConflict(e, r['server_record'] as Json);
              await _dropEntry(e.seq);
            default:
              await (db.update(db.outbox)..where((t) => t.seq.equals(e.seq))).write(
                OutboxCompanion(status: const Value('failed'), error: Value(r['error'] as String?)),
              );
          }
        }
      });
    }
    return conflicts;
  }

  /// Сервер не принял правку, потому что запись изменили на другом устройстве (или удалили).
  /// Для плана, отчёта и своего упражнения сохраняем локальную правку копией,
  /// чтобы работа тренера не потерялась, и принимаем серверную версию.
  Future<int> _resolveConflict(OutboxEntry e, Json server) async {
    var copies = 0;
    final local = await _row(e.entity, e.recordId);
    if (local != null && e.op == 'upsert' && Entities.strict.contains(e.entity) && !local.deleted) {
      final data = jsonDecode(local.data) as Json;
      if (data['title'] is String) data['title'] = '${data['title']} (конфликт)';
      if (e.entity == Entities.sessions) data['conflict_of'] = e.recordId;
      final copyId = newId();
      final parentField = Entities.parentField[e.entity];
      await db.into(db.records).insert(RecordsCompanion.insert(
            entity: e.entity,
            id: copyId,
            data: jsonEncode(data),
            parentId: Value(parentField == null ? null : data[parentField] as String?),
            updatedAt: DateTime.now(),
          ));
      await db.into(db.outbox).insert(OutboxCompanion.insert(
            entity: e.entity,
            recordId: copyId,
            op: 'upsert',
            createdAt: DateTime.now(),
          ));
      copies = 1;
    }
    await _applyServerRecord(server);
    return copies;
  }

  // ------------------------------------------------------------------ pull

  Future<void> _pull() async {
    var cursor = int.tryParse(await db.getKv(_cursorKey) ?? '') ?? 0;
    while (true) {
      final page = await api.get('/sync/pull', query: {'since': '$cursor', 'limit': '500'}) as Json;
      final records = (page['records'] as List).cast<Json>();
      await db.transaction(() async {
        for (final rec in records) {
          final hasPending = await (db.select(db.outbox)
                ..where((t) =>
                    t.entity.equals(rec['entity'] as String) &
                    t.recordId.equals(rec['id'] as String) &
                    t.status.equals('pending')))
              .get();
          // Есть неотправленная локальная правка — не затираем её; push разрешит конфликт.
          if (hasPending.isNotEmpty) continue;
          await _applyServerRecord(rec);
        }
        cursor = page['cursor'] as int;
        await db.setKv(_cursorKey, '$cursor');
      });
      if (page['has_more'] != true) break;
    }
  }

  Future<void> _applyServerRecord(Json rec, {bool system = false}) async {
    final entity = rec['entity'] as String;
    final data = rec['data'] as Json;
    final parentField = Entities.parentField[entity];
    await db.into(db.records).insertOnConflictUpdate(RecordsCompanion(
          entity: Value(entity),
          id: Value(rec['id'] as String),
          data: Value(jsonEncode(data)),
          parentId: Value(parentField == null ? null : data[parentField] as String?),
          serverSeq: Value(system ? null : rec['server_seq'] as int?),
          deleted: Value(rec['deleted'] as bool? ?? false),
          system: Value(system),
          updatedAt: Value(DateTime.parse(rec['updated_at'] as String).toLocal()),
        ));
  }

  // ------------------------------------------------------------------ каталог

  Future<void> _catalog() async {
    final version = await db.getKv(_catalogKey) ?? '';
    final resp = await api.get('/catalog/drills', query: {'version': version}) as Json;
    if (resp['changed'] != true) return;
    await importCatalog((resp['drills'] as List).cast<Json>(), resp['version'] as String);
  }

  /// Импорт системной библиотеки (с сервера или из встроенного в приложение файла).
  Future<void> importCatalog(List<Json> drills, String version) => db.transaction(() async {
        await (db.delete(db.records)..where((t) => t.system.equals(true))).go();
        for (final d in drills) {
          await _applyServerRecord(d, system: true);
        }
        await db.setKv(_catalogKey, version);
      });

  /// Каталог, встроенный в приложение: библиотека доступна сразу после установки, без сети.
  Future<void> ensureBundledCatalog(Future<String> Function() loadAsset) async {
    if (await db.getKv(_catalogKey) != null) return;
    final bundle = jsonDecode(await loadAsset()) as Json;
    await importCatalog((bundle['drills'] as List).cast<Json>(), bundle['version'] as String);
  }

  Future<LocalRecord?> _row(String entity, String id) =>
      (db.select(db.records)..where((t) => t.entity.equals(entity) & t.id.equals(id))).getSingleOrNull();

  Future<void> _dropEntry(int seq) => (db.delete(db.outbox)..where((t) => t.seq.equals(seq))).go();

  Future<void> dispose() => _status.close();
}
