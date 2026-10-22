import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/export/save_file.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

final _orgsProvider = FutureProvider.autoDispose<List<Json>>(
  (ref) async => (await ref.read(apiProvider).get('/orgs/mine') as List).cast<Json>(),
);
final _membersProvider = FutureProvider.autoDispose.family<List<Json>, String>(
  (ref, id) async => (await ref.read(apiProvider).get('/orgs/$id/members') as List).cast<Json>(),
);
final _overviewProvider = FutureProvider.autoDispose.family<Json, String>(
  (ref, id) async => await ref.read(apiProvider).get('/orgs/$id/overview') as Json,
);

const _roles = {'owner': 'Владелец', 'admin': 'Администратор', 'head_coach': 'Старший тренер', 'coach': 'Тренер'};

/// Футбольная школа: тренеры, роли, сводка по командам и передача команды. Данные детей остаются у тренера.
class SchoolScreen extends ConsumerWidget {
  const SchoolScreen({super.key});

  Future<String?> _ask(BuildContext context, String title, String label) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Готово')),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } on ApiException catch (e) {
      if (context.mounted) showInfo(context, e.isNetwork ? 'Нужен интернет' : e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).demo) {
      return Scaffold(
        appBar: AppBar(title: const Text('Футбольная школа')),
        body: const EmptyState(icon: Icons.cloud_off, title: 'В демо-режиме недоступно', text: 'Школа объединяет аккаунты тренеров на сервере.'),
      );
    }
    final orgs = ref.watch(_orgsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Футбольная школа')),
      body: orgs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(e is ApiException && e.isNetwork ? 'Нет связи с сервером' : '$e')),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          Text(
            'Школа объединяет тренеров: руководитель видит сводку по командам — занятия, отчёты, посещаемость — '
            'и может передать команду другому тренеру. Карточки детей остаются у их тренера.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Создать школу'),
                onPressed: () async {
                  final name = await _ask(context, 'Новая школа', 'Название');
                  if (name == null || name.isEmpty || !context.mounted) return;
                  await _call(context, () async {
                    await ref.read(apiProvider).post('/orgs', {'name': name});
                    ref.invalidate(_orgsProvider);
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Войти по коду'),
                onPressed: () async {
                  final code = await _ask(context, 'Код школы', 'Код от руководителя');
                  if (code == null || code.isEmpty || !context.mounted) return;
                  await _call(context, () async {
                    await ref.read(apiProvider).post('/orgs/join', {'code': code});
                    ref.invalidate(_orgsProvider);
                  });
                },
              ),
            ),
          ]),
          if (list.isEmpty) const Padding(padding: EdgeInsets.only(top: 24), child: Text('Вы пока не состоите в школе.')),
          for (final o in list) _OrgCard(org: o, call: (f) => _call(context, f)),
        ]),
      ),
    );
  }
}

class _OrgCard extends ConsumerWidget {
  const _OrgCard({required this.org, required this.call});

  final Json org;
  final Future<void> Function(Future<void> Function()) call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = org['id'] as String;
    final role = org['role'] as String;
    final manager = role == 'owner' || role == 'admin';
    final viewer = manager || role == 'head_coach';
    final members = ref.watch(_membersProvider(id)).value ?? const <Json>[];
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(org['name'] as String, style: t.textTheme.titleLarge),
          Text('Ваша роль: ${_roles[role]}', style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text('Тренеры (${members.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final mem in members)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(mem['name'] as String),
              subtitle: Text('${_roles[mem['role']]} · ${mem['email']}'),
              trailing: manager && mem['role'] != 'owner'
                  ? IconButton(
                      tooltip: 'Исключить',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => call(() async {
                        if (!await confirm(context, 'Исключить ${mem['name']} из школы?', ok: 'Исключить')) return;
                        await ref.read(apiProvider).delete('/orgs/$id/members/${mem['user_id']}');
                        ref.invalidate(_membersProvider(id));
                      }),
                    )
                  : null,
            ),
          if (manager)
            Wrap(spacing: 8, children: [
              for (final r in const ['coach', 'head_coach', 'admin'])
                OutlinedButton(
                  onPressed: () => call(() async {
                    final res = await ref.read(apiProvider).post('/orgs/$id/invites', {'role': r}) as Json;
                    await Clipboard.setData(ClipboardData(text: res['code'] as String));
                    if (context.mounted) showInfo(context, 'Код для «${_roles[r]}»: ${res['code']} — скопирован, действует 7 дней');
                  }),
                  child: Text('Код: ${_roles[r]}'),
                ),
            ]),
          if (viewer) _Overview(orgId: id, manager: manager, members: members, call: call),
        ]),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  const _Overview({required this.orgId, required this.manager, required this.members, required this.call});

  final String orgId;
  final bool manager;
  final List<Json> members;
  final Future<void> Function(Future<void> Function()) call;

  String _pct(Object? v) => v == null ? '—' : '$v%';

  Future<void> _export(BuildContext context, Json ov) async {
    // CSV с BOM — открывается в Excel с русскими буквами.
    final rows = [
      ['Команда', 'Возраст', 'Тренер', 'Игроков', 'Занятий за 28 дней', 'Отчёты заполнены, %', 'Посещаемость, %'],
      for (final x in (ov['teams'] as List).cast<Json>())
        [x['team'], x['age_group'], x['coach'], x['players'], x['sessions_28d'], x['reports_filled_pct'] ?? '', x['attendance_pct'] ?? ''],
    ];
    final csv = rows.map((r) => r.map((c) => '"${'$c'.replaceAll('"', '""')}"').join(';')).join('\r\n');
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    await saveFile(bytes, 'Школа ${DateFormat('dd.MM.yyyy').format(DateTime.now())}.csv', 'text/csv');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ov = ref.watch(_overviewProvider(orgId));
    return ov.when(
      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      error: (e, _) => Text('$e'),
      data: (d) {
        final teams = (d['teams'] as List).cast<Json>();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Команды школы за 28 дней', style: TextStyle(fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Выгрузить таблицу (Excel/CSV)', icon: const Icon(Icons.download_outlined), onPressed: () => _export(context, d)),
          ]),
          if (teams.isEmpty) const Text('Команд пока нет: тренеры создают их в своих аккаунтах.'),
          for (final x in teams)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${x['team']} · ${AgeGroups.label(x['age_group'] as String)}'),
              subtitle: Text('${x['coach']} · игроков ${x['players']} · занятий ${x['sessions_28d']}\n'
                  'Отчёты ${_pct(x['reports_filled_pct'])} · посещаемость ${_pct(x['attendance_pct'])}'),
              isThreeLine: true,
              trailing: (x['reports_filled_pct'] as int? ?? 100) < 70
                  ? const Tooltip(message: 'Меньше 70% отчётов заполнено', child: Icon(Icons.warning_amber, color: AppColors.warn))
                  : null,
              onTap: !manager
                  ? null
                  : () => call(() async {
                        final to = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (c) => ListView(shrinkWrap: true, children: [
                            ListTile(title: Text('Передать «${x['team']}» тренеру:')),
                            for (final mm in members)
                              if (mm['user_id'] != x['coach_id'])
                                ListTile(
                                  leading: const Icon(Icons.swap_horiz),
                                  title: Text(mm['name'] as String),
                                  subtitle: Text(_roles[mm['role']] ?? ''),
                                  onTap: () => Navigator.pop(c, mm['user_id'] as String),
                                ),
                          ]),
                        );
                        if (to == null || !context.mounted) return;
                        if (!await confirm(context, 'Передать команду со всеми данными?',
                            text: 'Игроки, тренировки, матчи и отчёты перейдут новому тренеру; у прежнего исчезнут после синхронизации.',
                            ok: 'Передать')) {
                          return;
                        }
                        final r = await ref.read(apiProvider).post('/orgs/$orgId/transfer', {'team_id': x['team_id'], 'to_user_id': to}) as Json;
                        ref.invalidate(_overviewProvider(orgId));
                        await ref.read(syncEngineProvider).sync();
                        if (context.mounted) showInfo(context, 'Передано записей: ${r['moved']}');
                      }),
            ),
        ]);
      },
    );
  }
}
