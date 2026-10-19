import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'db.g.dart';

/// Все синхронизируемые сущности хранятся в одной таблице как JSON-документы.
/// Это совпадает с моделью синхронизации сервера (entity + id + data) и
/// позволяет приложению целиком работать офлайн.
@DataClassName('LocalRecord')
class Records extends Table {
  TextColumn get entity => text()();
  TextColumn get id => text()();
  TextColumn get data => text()();

  /// Родитель для быстрых выборок: команда игрока, занятие заметки и т.п.
  TextColumn get parentId => text().nullable()();

  /// Версия с сервера, от которой сделана локальная правка (base_seq при push).
  IntColumn get serverSeq => integer().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Запись системной библиотеки (только чтение, не синхронизируется через outbox).
  BoolColumn get system => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entity, id};
}

/// Очередь локальных изменений для отправки на сервер.
/// На одну запись — одна ожидающая строка: данные берутся из Records в момент отправки.
@DataClassName('OutboxEntry')
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get recordId => text()();
  TextColumn get op => text()(); // upsert | delete
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending | failed
  TextColumn get error => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('KvEntry')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Records, Outbox, Kv])
class AppDb extends _$AppDb {
  AppDb(super.e);

  factory AppDb.open() => AppDb(
        driftDatabase(
          name: 'coachpilot',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX idx_records_entity_parent ON records (entity, parent_id)');
          await customStatement('CREATE INDEX idx_outbox_record ON outbox (entity, record_id)');
        },
      );

  Future<String?> getKv(String key) async =>
      (await (select(kv)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setKv(String key, String value) =>
      into(kv).insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));

  Future<void> deleteKv(String key) => (delete(kv)..where((t) => t.key.equals(key))).go();

  /// Полная очистка при выходе из аккаунта.
  Future<void> wipe() => transaction(() async {
        await delete(records).go();
        await delete(outbox).go();
        await delete(kv).go();
      });
}
