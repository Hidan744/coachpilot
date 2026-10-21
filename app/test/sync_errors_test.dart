import 'dart:convert';

import 'package:coachpilot/data/db.dart';
import 'package:coachpilot/sync/api_client.dart';
import 'package:coachpilot/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('afterSync error is logged and does not break sync', () async {
    final client = MockClient((req) async => http.Response(
        jsonEncode(switch (req.url.path) {
          '/sync/pull' => {'records': [], 'cursor': 0, 'has_more': false},
          '/catalog/drills' => {'changed': false},
          _ => {'results': []},
        }),
        200));
    final db = AppDb(NativeDatabase.memory());
    final api = ApiClient(baseUrl: 'https://api.test', tokens: MemoryTokenStore(), client: client);
    final engine = SyncEngine(db, api)..afterSync = (_) async => throw StateError('analytics down');

    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
    try {
      await engine.sync();
    } finally {
      debugPrint = original;
      await db.close();
    }

    expect(logged.any((m) => m.contains('afterSync failed') && m.contains('analytics down')), isTrue);
  });
}
