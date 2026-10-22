import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../sync/api_client.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

final _childrenProvider = FutureProvider.autoDispose<List<Json>>(
  (ref) async => (await ref.read(apiProvider).get('/family/children') as List).cast<Json>(),
);
final _childProvider = FutureProvider.autoDispose.family<Json, String>(
  (ref, id) async => await ref.read(apiProvider).get('/family/children/$id') as Json,
);

String _err(Object e) => e is ApiException && e.isNetwork ? 'Нет связи с сервером. Кабинет работает при подключении к интернету.' : '$e';

/// Кабинет родителя или игрока: дети по коду от тренера, расписание, задания, сообщения.
class FamilyHomeScreen extends ConsumerWidget {
  const FamilyHomeScreen({super.key});

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Код от тренера'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Код', hintText: 'Например: 7F3A9C21'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Подключить')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await ref.read(apiProvider).post('/family/join', {'code': code});
      ref.invalidate(_childrenProvider);
      if (context.mounted) showInfo(context, 'Готово: карточка игрока подключена');
    } on ApiException catch (e) {
      if (context.mounted) showInfo(context, e.isNetwork ? 'Нет связи с сервером' : e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final kids = ref.watch(_childrenProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(auth.profile?['role'] == 'player' ? 'Мой кабинет' : 'Кабинет родителя'),
        actions: [IconButton(tooltip: 'Настройки', icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/family/settings'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _join(context, ref),
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Ввести код'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_childrenProvider),
        child: kids.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_err(e)))]),
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.family_restroom,
                    title: 'Пока нет подключённых игроков',
                    text: 'Попросите у тренера код и нажмите «Ввести код». Тренер решает, что будет видно: '
                        'расписание, план развития, сообщения.',
                  ),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  Text('Привет, ${auth.name}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final k in list)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(k['name'] as String),
                        subtitle: Text(k['team'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/family/${k['player_id']}'),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

class ChildScreen extends ConsumerWidget {
  const ChildScreen({super.key, required this.playerId});

  final String playerId;

  static const _labels = {'yes': 'Буду', 'no': 'Не смогу', 'maybe': 'Не знаю'};

  Future<void> _rsvp(BuildContext context, WidgetRef ref, Json e, String status) async {
    try {
      await ref.read(apiProvider).post('/family/children/$playerId/rsvp', {'kind': e['kind'], 'id': e['id'], 'status': status});
      ref.invalidate(_childProvider(playerId));
      if (context.mounted) showInfo(context, 'Тренер увидит: ${_labels[status]}');
    } on ApiException catch (x) {
      if (context.mounted) showInfo(context, x.isNetwork ? 'Нет связи с сервером' : x.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_childProvider(playerId));
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(data.value?['player']?['name'] as String? ?? 'Игрок')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(_err(e))),
        data: (d) {
          final upcoming = (d['upcoming'] as List).cast<Json>();
          final plans = (d['plans'] as List).cast<Json>();
          final notes = (d['notes'] as List).cast<Json>();
          final att = d['attendance'] as Json;
          Widget title(String s) => Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                child: Text(s, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              );
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_childProvider(playerId)),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
              Text('${d['team']}${(att['total'] as int) > 0 ? ' · посещаемость ${((att['present'] as int) * 100 / (att['total'] as int)).round()}%' : ''}',
                  style: t.textTheme.bodyMedium),
              title('Расписание'),
              if (upcoming.isEmpty) const Text('Ближайших тренировок и матчей нет', style: TextStyle(color: AppColors.textMuted)),
              for (final e in upcoming)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(e['kind'] == 'match' ? Icons.emoji_events_outlined : Icons.sports_soccer, color: AppColors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      Text(DateFormat('EEEE, d MMMM, HH:mm', 'ru').format(DateTime.parse(e['starts_at'] as String).toLocal())),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        for (final s in _labels.entries)
                          ChoiceChip(
                            label: Text(s.value),
                            selected: e['rsvp'] == s.key,
                            onSelected: (_) => _rsvp(context, ref, e, s.key),
                          ),
                      ]),
                    ]),
                  ),
                ),
              if (plans.isNotEmpty) title('План развития'),
              for (final p in plans)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if ((p['key_goal'] as String? ?? '').isNotEmpty) Text('Цель: ${p['key_goal']}'),
                      for (final i in (p['items'] as List).cast<Json>()) Text('${i['done'] == true ? '✓' : '•'} ${i['text']}'),
                      for (final w in (p['weeks'] as List).cast<Json>())
                        Text('${w['done'] == true ? '✓' : '•'} Неделя ${w['n']}: ${w['priority']}'),
                    ]),
                  ),
                ),
              if (notes.isNotEmpty) title('Сообщения тренера'),
              for (final n in notes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(n['text'] as String),
                  subtitle: Text('${ParentNoteCategories.all[n['category']] ?? ''} · '
                      '${DateFormat('d MMM', 'ru').format(DateTime.parse(n['written_at'] as String).toLocal())}'),
                ),
              const SizedBox(height: 16),
              Text('Здесь видно только то, что тренер открыл для семьи.', style: t.textTheme.bodySmall),
            ]),
          );
        },
      ),
    );
  }
}
