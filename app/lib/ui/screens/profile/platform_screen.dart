import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

final _plansProvider = FutureProvider.autoDispose<Json>((ref) async => await ref.read(apiProvider).get('/billing/plans') as Json);
final _billingProvider = FutureProvider.autoDispose<Json>((ref) async => await ref.read(apiProvider).get('/billing/me') as Json);
final _integrationsProvider =
    FutureProvider.autoDispose<Json>((ref) async => await ref.read(apiProvider).get('/integrations/status') as Json);
final _telegramProvider =
    FutureProvider.autoDispose<Json>((ref) async => await ref.read(apiProvider).get('/notifications/telegram') as Json);
final _auditProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async => await ref.read(apiProvider).get('/account/audit') as List);

const _auditLabels = {
  'register': 'Регистрация и согласие на обработку данных',
  'login': 'Вход',
  'data_exported': 'Выгрузка всех данных',
  'share_created': 'Создана ссылка для родителей',
  'share_revoked': 'Ссылка для родителей отозвана',
  'plan_changed': 'Смена тарифа',
  'telegram_linked': 'Привязан Telegram',
  'telegram_unlinked': 'Telegram отвязан',
};

/// Тариф, интеграции, уведомления и журнал действий. Всё — с сервера; без сети честно показывает, что недоступно.
class PlatformScreen extends ConsumerWidget {
  const PlatformScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(authProvider).demo) {
      return Scaffold(
        appBar: AppBar(title: const Text('Тариф и интеграции')),
        body: const EmptyState(
          icon: Icons.cloud_off,
          title: 'В демо-режиме недоступно',
          text: 'Тарифы, Telegram и журнал действий работают с сервером после регистрации.',
        ),
      );
    }
    final t = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        );
    Widget async<T>(AsyncValue<T> v, Widget Function(T) ok) => v.when(
          data: ok,
          loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          error: (e, _) => ListTile(
            leading: const Icon(Icons.cloud_off, color: AppColors.warn),
            title: Text(e is ApiException && e.isNetwork ? 'Нет связи с сервером' : '$e'),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Тариф и интеграции')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_billingProvider);
          ref.invalidate(_integrationsProvider);
          ref.invalidate(_telegramProvider);
          ref.invalidate(_auditProvider);
        },
        child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          section('Ваш тариф'),
          async(ref.watch(_billingProvider), (b) {
            final plan = b['plan'] as Json;
            return ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text('${plan['title']}${b['status'] == 'test' ? ' (тестовый режим)' : ''}'),
              subtitle: Text('AI-генерации в этом месяце: ${b['ai_used']} из ${b['ai_limit']}'),
            );
          }),
          async(ref.watch(_plansProvider), (p) {
            final payments = p['payments'] as String;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final x in (p['plans'] as List).cast<Json>())
                Card(
                  margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(x['title'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        Text(x['price_rub_month'] == 0 ? 'Бесплатно' : '${NumberFormat.decimalPattern('ru').format(x['price_rub_month'])} ₽/мес',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                      Text('${x['audience']} · AI: ${x['ai_quota_month']} в месяц', style: t.textTheme.bodySmall),
                      for (final f in (x['features'] as List)) Text('• $f'),
                      if (x['code'] != 'free')
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _checkout(context, ref, x['code'] as String),
                            child: Text(payments == 'test' ? 'Подключить (тест)' : 'Подключить'),
                          ),
                        ),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  payments == 'off'
                      ? 'Оплата пока не подключена — тариф меняется через поддержку. Цены задаются на сервере.'
                      : payments == 'test'
                          ? 'Тестовый режим оплаты: деньги не списываются.'
                          : 'Оплата: $payments',
                  style: t.textTheme.bodySmall,
                ),
              ),
            ]);
          }),
          section('Интеграции'),
          async(ref.watch(_integrationsProvider), (s) {
            Widget row(String key, String title, IconData icon) {
              final x = s[key] as Json;
              final status = x['status'] as String;
              return ListTile(
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(x['detail'] as String),
                trailing: Chip(
                  label: Text(switch (status) { 'connected' => 'Подключено', 'test' => 'Тест', _ => 'Не подключено' }),
                  backgroundColor: status == 'connected' ? AppColors.good.withValues(alpha: 0.2) : null,
                ),
              );
            }

            return Column(children: [
              row('ai', 'AI-генерация', Icons.auto_awesome_outlined),
              row('telegram', 'Telegram', Icons.send_outlined),
              row('payments', 'Оплата', Icons.payments_outlined),
              row('email', 'Почта', Icons.mail_outline),
            ]);
          }),
          section('Уведомления в Telegram'),
          async(ref.watch(_telegramProvider), (tg) {
            if (tg['configured'] != true) {
              return const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Telegram не подключён на сервере'),
                subtitle: Text('Администратору нужно задать токен бота. До этого напоминания не отправляются.'),
              );
            }
            if (tg['linked'] == true) {
              return Column(children: [
                const ListTile(
                  leading: Icon(Icons.check_circle, color: AppColors.good),
                  title: Text('Telegram привязан'),
                  subtitle: Text('Напоминания о тренировках и матчах за сутки'),
                ),
                Row(children: [
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        await ref.read(apiProvider).post('/notifications/telegram/test');
                        if (context.mounted) showInfo(context, 'Тестовое сообщение отправлено');
                      } on ApiException catch (e) {
                        if (context.mounted) showInfo(context, e.message);
                      }
                    },
                    child: const Text('Проверить'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      await ref.read(apiProvider).delete('/notifications/telegram');
                      ref.invalidate(_telegramProvider);
                    },
                    child: const Text('Отвязать'),
                  ),
                ]),
              ]);
            }
            return ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Привязать Telegram'),
              subtitle: const Text('Получите ссылку, откройте её в Telegram и нажмите «Старт»'),
              onTap: () async {
                try {
                  final r = await ref.read(apiProvider).post('/notifications/telegram/link') as Json;
                  await Clipboard.setData(ClipboardData(text: r['url'] as String));
                  if (context.mounted) showInfo(context, 'Ссылка скопирована: откройте её в Telegram (действует 30 минут)');
                } on ApiException catch (e) {
                  if (context.mounted) showInfo(context, e.message);
                }
              },
            );
          }),
          section('Журнал действий'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Входы, выгрузки данных, ссылки родителям — последние 100 записей.', style: t.textTheme.bodySmall),
          ),
          async(ref.watch(_auditProvider), (list) => Column(children: [
                if (list.isEmpty) const ListTile(title: Text('Записей пока нет')),
                for (final a in list.cast<Json>())
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(_auditLabels[a['action']] ?? '${a['action']}'),
                    subtitle: Text(DateFormat('d MMM yyyy, HH:mm', 'ru').format(DateTime.parse(a['at'] as String).toLocal())),
                  ),
              ])),
        ]),
      ),
    );
  }

  Future<void> _checkout(BuildContext context, WidgetRef ref, String plan) async {
    try {
      await ref.read(apiProvider).post('/billing/checkout', {'plan': plan});
      ref.invalidate(_billingProvider);
      if (context.mounted) showInfo(context, 'Тариф подключён (тестовый режим)');
    } on ApiException catch (e) {
      if (context.mounted) showInfo(context, e.isNetwork ? 'Нет связи с сервером' : e.message);
    }
  }
}
