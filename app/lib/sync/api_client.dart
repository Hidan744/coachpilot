import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart' show Json;

class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;

  /// null — сетевая ошибка (нет интернета, сервер недоступен, таймаут).
  final int? status;

  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Хранилище токенов. На устройстве — защищённое хранилище ОС, в тестах — память.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  final _s = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryTokenStore implements TokenStore {
  final _m = <String, String>{};

  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client, this.timeout = const Duration(seconds: 25)})
      : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  final Duration timeout;

  /// Вызывается, когда refresh-токен больше не действует и нужен повторный вход.
  void Function()? onSessionExpired;

  static const _access = 'access_token';
  static const _refresh = 'refresh_token';

  Future<bool> get hasSession async => (await tokens.read(_refresh)) != null;

  Future<void> saveTokens(Json t) async {
    await tokens.write(_access, t['access_token'] as String);
    await tokens.write(_refresh, t['refresh_token'] as String);
  }

  Future<void> clearTokens() async {
    await tokens.delete(_access);
    await tokens.delete(_refresh);
  }

  Future<String?> get refreshToken => tokens.read(_refresh);

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  /// Запрос без авторизации (вход, регистрация).
  Future<dynamic> postPublic(String path, Object body) => _send('POST', path, body: body, auth: false);

  Future<dynamic> _send(String method, String path,
      {Object? body, Map<String, String>? query, bool auth = true, bool retried = false}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = {'Content-Type': 'application/json', 'Accept': 'application/json'};
    if (auth) {
      final token = await tokens.read(_access);
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    http.Response resp;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      resp = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ApiException('Сервер не отвечает. Проверьте интернет и попробуйте ещё раз.');
    } catch (_) {
      throw ApiException('Нет связи с сервером. Данные сохранены на телефоне и отправятся позже.');
    }

    if (resp.statusCode == 401 && auth && !retried && await _tryRefresh()) {
      return _send(method, path, body: body, query: query, auth: auth, retried: true);
    }
    if (resp.statusCode == 401 && auth) {
      onSessionExpired?.call();
    }
    final text = utf8.decode(resp.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (resp.statusCode >= 400) {
      throw ApiException(_errorMessage(resp.statusCode, decoded), status: resp.statusCode);
    }
    return decoded;
  }

  Future<bool> _tryRefresh() async {
    final refresh = await tokens.read(_refresh);
    if (refresh == null) return false;
    try {
      final resp = await _http
          .post(Uri.parse('$baseUrl/auth/refresh'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh_token': refresh}))
          .timeout(timeout);
      if (resp.statusCode != 200) {
        if (resp.statusCode == 401) await clearTokens();
        return false;
      }
      await saveTokens(jsonDecode(utf8.decode(resp.bodyBytes)) as Json);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _errorMessage(int status, dynamic body) {
    final detail = body is Map ? body['detail'] : null;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      final msg = first is Map ? (first['msg'] ?? '').toString() : first.toString();
      return msg.replaceFirst('Value error, ', '');
    }
    return switch (status) {
      401 => 'Требуется вход',
      403 => 'Нет доступа',
      404 => 'Не найдено',
      429 => 'Слишком много запросов, попробуйте позже',
      >= 500 => 'Ошибка сервера, попробуйте позже',
      _ => 'Ошибка запроса ($status)',
    };
  }
}
