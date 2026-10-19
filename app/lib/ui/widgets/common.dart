import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../sync/api_client.dart';

/// Значок состояния синхронизации в заголовке экрана.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    final pending = ref.watch(pendingCountProvider).value ?? 0;
    final (IconData icon, String tip) = status?.running == true
        ? (Icons.sync, 'Синхронизация…')
        : status?.error != null
            ? (Icons.cloud_off, 'Нет связи. Ждут отправки: $pending. Всё сохранено на телефоне.')
            : pending > 0
                ? (Icons.cloud_upload_outlined, 'Ожидают отправки: $pending')
                : (Icons.cloud_done_outlined, 'Всё синхронизировано');
    return IconButton(
      tooltip: tip,
      icon: Icon(icon),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
        ref.read(syncEngineProvider).sync();
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.text, this.action});

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: t.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 8),
            Text(text!, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ]),
      );
}

void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : 'Что-то пошло не так. Попробуйте ещё раз.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

void showInfo(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirm(BuildContext context, String title, {String? text, String ok = 'Удалить'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: text == null ? null : Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Обёртка над AsyncValue с единообразными загрузкой и ошибкой.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Ошибка: $e'))),
      );
}

/// Назад, а если экран открыт по прямой ссылке и возвращаться некуда — на [fallback].
void popOr(BuildContext context, String fallback) {
  final router = GoRouter.of(context);
  router.canPop() ? router.pop() : router.go(fallback);
}
