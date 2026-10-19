import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/providers.dart';
import 'data/db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  final db = AppDb.open();
  runApp(ProviderScope(
    overrides: [dbProvider.overrideWithValue(db)],
    child: const CoachPilotApp(),
  ));
}
