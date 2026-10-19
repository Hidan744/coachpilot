import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/db.dart';
import '../sync/api_client.dart';

/// Продуктовая аналитика и ошибки клиента.
///
/// События копятся на телефоне (в т.ч. офлайн) и отправляются на свой сервер после
/// синхронизации. Персональные данные игроков в события не пишем.
class Analytics {
  Analytics(this.db, this.api);

  final AppDb db;
  final ApiClient api;

  static const _key = 'analytics_queue';
  static const _max = 500;
  static const appVersion = '0.1.0';

  Future<void> track(String name, [Map<String, Object?> props = const {}]) async {
    try {
      final raw = await db.getKv(_key);
      final queue = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      queue.add({'name': name, 'props': props, 'ts': DateTime.now().toUtc().toIso8601String()});
      if (queue.length > _max) queue.removeRange(0, queue.length - _max);
      await db.setKv(_key, jsonEncode(queue));
    } catch (_) {
      // аналитика никогда не должна ломать работу приложения
    }
  }

  Future<void> error(Object e, StackTrace? st, {String where = ''}) => track('app_error', {
        'message': e.toString().substring(0, e.toString().length.clamp(0, 300)),
        'where': where,
        if (st != null) 'stack': st.toString().split('\n').take(6).join('\n'),
      });

  /// Отправить накопленное. Ошибки сети молча игнорируем — попробуем в следующий раз.
  Future<void> flush() async {
    final raw = await db.getKv(_key);
    if (raw == null) return;
    final queue = jsonDecode(raw) as List;
    if (queue.isEmpty) return;
    final batch = queue.take(200).toList();
    try {
      await api.post('/events', {
        'events': batch,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'app_version': appVersion,
      });
      final rest = queue.skip(batch.length).toList();
      await db.setKv(_key, jsonEncode(rest));
    } on ApiException catch (e) {
      // 4xx — битая пачка, выбрасываем, чтобы не застрять навсегда
      if (!e.isNetwork && (e.status ?? 500) < 500 && e.status != 401) {
        await db.setKv(_key, jsonEncode(queue.skip(batch.length).toList()));
      }
    }
  }
}
