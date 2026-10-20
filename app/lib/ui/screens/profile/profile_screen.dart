import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../sync/api_client.dart';
import '../../../core/demo_data.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'staff_section.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final status = ref.watch(syncStatusProvider).value;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final failed = ref.watch(_failedProvider).value ?? const [];
    final p = auth.profile ?? const {};
    final last = status?.lastSyncAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль'), actions: const [SyncBadge()]),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(auth.name),
          subtitle: Text([p['email'], p['city'], p['coaching_level']].whereType<String>().join(' · ')),
          trailing: auth.demo ? null : const Icon(Icons.edit_outlined),
          onTap: auth.demo ? null : () => _editProfile(context, ref, p),
        ),
        const StaffAndReportsSection(),
        if (auth.demo) ...[
          Card(
            margin: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Вы в демо-режиме. Всё работает, но данные хранятся только в этом браузере: '
                'нет синхронизации между устройствами и AI-генерации. '
                'Чтобы начать заново, нажмите «Начать демо заново».',
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_motion_outlined, color: AppColors.red),
            title: const Text('Заполнить примером'),
            subtitle: const Text('Команда из 16 игроков: тренировки, матчи, статистика, тесты ОФП, планы — чтобы увидеть дашборды и отчёты'),
            onTap: () => fillDemoExample(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Начать демо заново'),
            subtitle: const Text('С примером данных или с чистого листа'),
            onTap: () async {
              final choice = await showDialog<String>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Начать демо заново?'),
                  content: const Text('Все данные демо-режима в этом браузере будут удалены.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(c, 'empty'), child: const Text('С чистого листа')),
                    FilledButton(onPressed: () => Navigator.pop(c, 'sample'), child: const Text('С примером')),
                  ],
                ),
              );
              if (choice != null) await ref.read(authProvider.notifier).resetDemo(sample: choice == 'sample');
            },
          ),
        ] else ...[
        const SectionTitle('Данные и синхронизация'),
        ListTile(
          leading: Icon(status?.error != null ? Icons.cloud_off : Icons.cloud_done_outlined),
          title: Text(status?.running == true
              ? 'Синхронизация…'
              : status?.error != null
                  ? 'Нет связи с сервером'
                  : 'Синхронизировано'),
          subtitle: Text([
            if (last != null) 'Последняя: ${DateFormat('d MMM, HH:mm', 'ru').format(last)}',
            'Ожидают отправки: $pending',
            if (status?.error != null) 'Все данные сохранены на телефоне',
          ].join('\n')),
          trailing: FilledButton.tonal(
            onPressed: () => ref.read(syncEngineProvider).sync(),
            child: const Text('Сейчас'),
          ),
        ),
        if (failed.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.orange),
            title: Text('Не приняты сервером: ${failed.length}'),
            subtitle: const Text('Эти записи содержат некорректные данные. Откройте и исправьте их.'),
          ),
        const ListTile(
          leading: Icon(Icons.offline_pin_outlined),
          title: Text('Офлайн-доступ'),
          subtitle: Text('Команды, тренировки, библиотека и схемы хранятся на телефоне и доступны без интернета.'),
        ),
        Consumer(builder: (context, ref, _) {
          final q = ref.watch(_quotaProvider).value;
          return ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI-генерации в этом месяце'),
            subtitle: Text(q == null ? 'Доступно при подключении к интернету' : '${q['used']} из ${q['limit']}'),
          );
        }),
        const SectionTitle('Аккаунт'),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Экспорт моих данных'),
          subtitle: const Text('Все команды, тренировки и отчёты в формате JSON'),
          onTap: () => _export(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Выйти'),
          onTap: () async {
            final text = pending > 0
                ? 'Есть неотправленные изменения ($pending). Они будут потеряны. Сначала подключитесь к интернету.'
                : 'Данные останутся на сервере и загрузятся при следующем входе.';
            if (await confirm(context, 'Выйти из аккаунта?', text: text, ok: 'Выйти')) {
              await ref.read(authProvider.notifier).logout();
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: const Text('Удалить аккаунт и все данные'),
          onTap: () => _deleteAccount(context, ref),
        ),
        ],
        const SizedBox(height: 24),
        Center(child: Text('CoachPilot 0.1.0', style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, Map<String, dynamic> p) async {
    final name = TextEditingController(text: p['name']);
    final city = TextEditingController(text: p['city']);
    final level = TextEditingController(text: p['coaching_level']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Профиль тренера'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя')),
          const SizedBox(height: 12),
          TextField(controller: city, decoration: const InputDecoration(labelText: 'Город')),
          const SizedBox(height: 12),
          TextField(controller: level, decoration: const InputDecoration(labelText: 'Лицензия / категория', hintText: 'Например, UEFA C')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(authProvider.notifier).updateProfile({
        if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
        'city': city.text.trim(),
        'coaching_level': level.text.trim(),
      });
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Все команды, игроки, тренировки и отчёты будут удалены без возможности восстановления.'),
          const SizedBox(height: 12),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить навсегда')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(authProvider.notifier).deleteAccount(pw.text);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

final _failedProvider = StreamProvider((ref) => ref.watch(repoProvider).watchFailed());

final _quotaProvider = FutureProvider<Json?>((ref) async {
  try {
    return await ref.watch(apiProvider).get('/ai/quota') as Json;
  } on ApiException {
    return null;
  }
});

Future<void> _export(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(syncEngineProvider).sync();
    final data = await ref.read(apiProvider).get('/account/export') as Json;
    final count = (data['data'] as Json).values.fold<int>(0, (a, l) => a + (l as List).length);
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
    if (context.mounted) showInfo(context, 'Скопировано записей: $count. Вставьте в письмо или файл.');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}


/// Пример данных в демо: всё пишется одной транзакцией, затем открывается дашборд команды.
Future<void> fillDemoExample(BuildContext context, WidgetRef ref) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('Заполняем пример…'))]),
    ),
  );
  final repo = ref.read(repoProvider);
  final teamId = await repo.db.transaction(() => seedDemoData(repo));
  ref.read(currentTeamIdProvider.notifier).select(teamId);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  context.go('/team');
  showInfo(context, 'Пример заполнен: 16 игроков, тренировки, матчи и тесты');
}
