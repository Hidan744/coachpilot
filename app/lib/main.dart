import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db.dart';
import 'sync/sync_engine.dart';
import 'sync/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // В web адресная строка отражает текущий экран — перезагрузка возвращает туда же.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  await initializeDateFormatting('ru');
  final db = AppDb.open();
  await SyncEngine(db, ApiClient(baseUrl: apiUrl, tokens: MemoryTokenStore()))
      .ensureBundledCatalog(() => rootBundle.loadString('assets/catalog.json'));
  final container = ProviderContainer(overrides: [dbProvider.overrideWithValue(db)]);
  final analytics = container.read(analyticsProvider);
  // Необработанные ошибки — в журнал аналитики, чтобы видеть сбои на устройствах тренеров.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    analytics.error(details.exception, details.stack, where: 'flutter');
  };
  PlatformDispatcher.instance.onError = (e, st) {
    analytics.error(e, st, where: 'platform');
    return true;
  };
  runApp(UncontrolledProviderScope(container: container, child: const CoachPilotApp()));
}
