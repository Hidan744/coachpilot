import 'dart:convert';

import 'package:coachpilot/sync/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parallel 401s share one token refresh and keep the session', () async {
    var refreshCalls = 0;
    var access = 'old';
    var refresh = 'r1';
    final client = MockClient((req) async {
      if (req.url.path == '/auth/refresh') {
        refreshCalls++;
        final sent = (jsonDecode(req.body) as Map)['refresh_token'];
        // Как на сервере: refresh-токен одноразовый.
        if (sent != refresh) return http.Response('{"detail":"Сессия истекла"}', 401);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        access = 'new';
        refresh = 'r2';
        return http.Response(jsonEncode({'access_token': access, 'refresh_token': refresh}), 200);
      }
      if (req.headers['Authorization'] != 'Bearer $access') return http.Response('{"detail":"expired"}', 401);
      return http.Response(jsonEncode({'path': req.url.path}), 200);
    });
    final store = MemoryTokenStore();
    final api = ApiClient(baseUrl: 'https://api.test', tokens: store, client: client);
    await api.saveTokens({'access_token': 'old', 'refresh_token': 'r1'});
    access = 'rotated-on-server';
    var expired = false;
    api.onSessionExpired = () => expired = true;

    final results = await Future.wait([api.get('/a'), api.get('/b'), api.get('/c')]);

    expect(results.map((r) => (r as Map)['path']), ['/a', '/b', '/c']);
    expect(refreshCalls, 1);
    expect(expired, isFalse);
    expect(await store.read('access_token'), 'new');
    expect(await store.read('refresh_token'), 'r2');
  });
}
