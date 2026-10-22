import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../tactics/tactics_screens.dart' show createBoard;
import '../team/team_screens.dart' show playersProvider;

final _reviewMatchProvider = StreamProvider.family<Match?, String>(
  (ref, id) => ref.watch(repoProvider).watchOne(Entities.matches, id, Match.fromJson),
);

/// Разбор матча: итоги, выводы, задачи на тренировку, заметки по игрокам и ручная разметка видео.
class MatchReviewScreen extends ConsumerStatefulWidget {
  const MatchReviewScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchReviewScreen> createState() => _MatchReviewScreenState();
}

class _MatchReviewScreenState extends ConsumerState<MatchReviewScreen> {
  final _summary = TextEditingController();
  final _conclusions = TextEditingController();
  final _video = TextEditingController();
  bool _loaded = false;
  String? _playerFilter;

  Future<void> _save(Match m, MatchReview r) => ref.read(repoProvider).put(Entities.matches, m.copyWith(review: r));

  /// Текстовые поля сохраняются при уходе с поля, чтобы не писать на каждую букву.
  Future<void> _saveTexts(Match m) => _save(
        m,
        m.review.copyWith(summary: _summary.text.trim(), conclusions: _conclusions.text.trim(), videoUrl: _validUrl(_video.text)),
      );

  String _validUrl(String s) => RegExp(r'^https?://\S+$').hasMatch(s.trim()) ? s.trim() : '';

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(_reviewMatchProvider(widget.matchId)).value;
    if (m == null) return Scaffold(appBar: AppBar(title: const Text('Разбор матча')), body: const Center(child: CircularProgressIndicator()));
    if (!_loaded) {
      _summary.text = m.review.summary;
      _conclusions.text = m.review.conclusions;
      _video.text = m.review.videoUrl;
      _loaded = true;
    }
    final r = m.review;
    final players = [for (final p in ref.watch(playersProvider(m.teamId)).value ?? const <Player>[]) if (p.active) p];
    final names = {for (final p in players) p.id: p.fullName};
    final t = Theme.of(context);
    final episodes = [...r.episodes]..sort((a, b) => a.t.compareTo(b.t));
    final shown = [for (final e in episodes) if (_playerFilter == null || e.players.contains(_playerFilter)) e];

    Widget title(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Row(children: [
            Expanded(child: Text(text, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ?trailing,
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('Разбор: ${m.opponent}${m.hasScore ? ' ${m.score}' : ''}'),
        actions: [
          IconButton(
            tooltip: 'Скопировать разбор текстом',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: matchReviewText(m, names)));
              if (context.mounted) showInfo(context, 'Разбор скопирован');
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        title('Итоги матча'),
        Focus(
          onFocusChange: (f) => f ? null : _saveTexts(m),
          child: TextField(controller: _summary, minLines: 2, maxLines: 6, decoration: const InputDecoration(hintText: 'Как прошёл матч: ход игры, ключевые моменты')),
        ),
        title('Выводы тренера'),
        Focus(
          onFocusChange: (f) => f ? null : _saveTexts(m),
          child: TextField(controller: _conclusions, minLines: 2, maxLines: 6, decoration: const InputDecoration(hintText: 'Что получилось, что не получилось и почему')),
        ),
        title('Задачи на тренировку', trailing: IconButton(
          tooltip: 'Добавить задачу',
          icon: const Icon(Icons.add),
          onPressed: () async {
            final text = await _ask(context, 'Задача на тренировку', 'Например: выход из-под прессинга через опорника');
            if (text != null && text.isNotEmpty) await _save(m, r.copyWith(tasks: [...r.tasks, text]));
          },
        )),
        if (r.tasks.isEmpty) const Text('Задачи появятся в конструкторе тренировки как приоритеты команды.', style: TextStyle(color: AppColors.textMuted)),
        for (var i = 0; i < r.tasks.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(r.tasks[i]),
            trailing: Wrap(children: [
              IconButton(
                tooltip: 'Собрать тренировку',
                icon: const Icon(Icons.auto_awesome, color: AppColors.red),
                onPressed: () => context.push('/sessions/new?goal=${Uri.encodeComponent(r.tasks[i])}'),
              ),
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.close),
                onPressed: () => _save(m, r.copyWith(tasks: [...r.tasks]..removeAt(i))),
              ),
            ]),
          ),
        title('Заметки по игрокам'),
        if (players.isEmpty) const Text('В команде нет игроков.', style: TextStyle(color: AppColors.textMuted)),
        for (final p in players)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(p.fullName),
            subtitle: Text(r.playerNotes[p.id] ?? 'Нажмите, чтобы оставить заметку',
                style: TextStyle(color: r.playerNotes[p.id] == null ? AppColors.textMuted : null)),
            onTap: () async {
              final text = await _ask(context, p.fullName, 'Что получилось, над чем работать', initial: r.playerNotes[p.id]);
              if (text == null) return;
              await _save(m, r.copyWith(playerNotes: {...r.playerNotes, p.id: text}..removeWhere((_, v) => v.isEmpty)));
            },
          ),
        title('Видеоразбор'),
        Text(
          'Видео не загружается в приложение: укажите ссылку на файл или видеохостинг и размечайте эпизоды по таймкодам. '
          'Автоматическое распознавание действий пока не используется.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Focus(
          onFocusChange: (f) => f ? null : _saveTexts(m),
          child: TextField(
            controller: _video,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Ссылка на видео',
              hintText: 'https://…',
              errorText: _video.text.trim().isEmpty || _validUrl(_video.text).isNotEmpty ? null : 'Нужна ссылка http:// или https://',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Эпизоды: ${episodes.length}', style: const TextStyle(fontWeight: FontWeight.w600))),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('Эпизод'),
            onPressed: () async {
              final e = await _editEpisode(context, players, null);
              if (e != null) await _save(m, r.copyWith(episodes: [...r.episodes, e]));
            },
          ),
        ]),
        if (episodes.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              ChoiceChip(label: const Text('Все'), selected: _playerFilter == null, onSelected: (_) => setState(() => _playerFilter = null)),
              for (final p in players.where((p) => episodes.any((e) => e.players.contains(p.id))))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(label: Text(p.lastName.isEmpty ? p.firstName : p.lastName), selected: _playerFilter == p.id,
                      onSelected: (_) => setState(() => _playerFilter = p.id)),
                ),
            ]),
          ),
        if (_playerFilter != null && shown.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text('Обратная связь для ${names[_playerFilter] ?? 'игрока'} — скопировать'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: playerFeedbackText(m, _playerFilter!, names)));
                if (context.mounted) showInfo(context, 'Список эпизодов скопирован — отправьте игроку');
              },
            ),
          ),
        for (final e in shown)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text(e.time, style: const TextStyle(fontSize: 12))),
              title: Text('${VideoEpisode.tags[e.tag]}${e.comment.isEmpty ? '' : ': ${e.comment}'}'),
              subtitle: Text([
                if (e.end != null) 'до ${e.end! ~/ 60}:${(e.end! % 60).toString().padLeft(2, '0')}',
                if (e.players.isNotEmpty) e.players.map((id) => names[id] ?? 'игрок').join(', '),
                if (e.boardId != null) 'есть схема',
              ].join(' · ')),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      final x = await _editEpisode(context, players, e);
                      if (x != null) await _save(m, r.copyWith(episodes: [for (final y in r.episodes) y.id == e.id ? x : y]));
                    case 'board':
                      final id = e.boardId ??
                          await createBoard(ref, teamId: m.teamId, matchId: m.id, title: '${m.opponent} ${e.time}: ${VideoEpisode.tags[e.tag]}');
                      if (e.boardId == null) {
                        await _save(m, r.copyWith(episodes: [
                          for (final y in r.episodes)
                            y.id == e.id
                                ? VideoEpisode(id: y.id, t: y.t, end: y.end, tag: y.tag, comment: y.comment, players: y.players, boardId: id)
                                : y,
                        ]));
                      }
                      if (context.mounted) context.push('/tactics/$id');
                    case 'delete':
                      await _save(m, r.copyWith(episodes: [for (final y in r.episodes) if (y.id != e.id) y]));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                  PopupMenuItem(value: 'board', child: Text(e.boardId == null ? 'Нарисовать схему' : 'Открыть схему')),
                  const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Future<String?> _ask(BuildContext context, String title, String hint, {String? initial}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLines: 4, minLines: 1, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
  }

  Future<VideoEpisode?> _editEpisode(BuildContext context, List<Player> players, VideoEpisode? e) async {
    final time = TextEditingController(text: e?.time ?? '');
    final end = TextEditingController(text: e?.end == null ? '' : '${e!.end! ~/ 60}:${(e.end! % 60).toString().padLeft(2, '0')}');
    final comment = TextEditingController(text: e?.comment);
    var tag = e?.tag ?? 'attack';
    final selected = {...?e?.players};
    String? error;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e == null ? 'Новый эпизод' : 'Эпизод', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: time,
                    autofocus: e == null,
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(labelText: 'Начало, мм:сс', errorText: error),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: end, keyboardType: TextInputType.datetime, decoration: const InputDecoration(labelText: 'Конец (необяз.)'))),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in VideoEpisode.tags.entries)
                  ChoiceChip(label: Text(x.value), selected: tag == x.key, onSelected: (_) => set(() => tag = x.key)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: comment, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Комментарий тренера')),
              const SizedBox(height: 12),
              const Text('Игроки в эпизоде'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in players)
                  FilterChip(
                    label: Text('${p.number == null ? '' : '${p.number} '}${p.lastName.isEmpty ? p.firstName : p.lastName}'),
                    selected: selected.contains(p.id),
                    onSelected: (v) => set(() => v ? selected.add(p.id) : selected.remove(p.id)),
                  ),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (parseTimecode(time.text) == null) {
                    set(() => error = 'Например 12:35');
                    return;
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Сохранить'),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return null;
    final start = parseTimecode(time.text)!;
    final stop = parseTimecode(end.text);
    return VideoEpisode(
      id: e?.id ?? newId(),
      t: start,
      end: stop != null && stop > start ? stop : null,
      tag: tag,
      comment: comment.text.trim(),
      players: selected.toList(),
      boardId: e?.boardId,
    );
  }
}

/// «12:35», «1:02:10» или секунды → секунды; null, если не разобрать.
int? parseTimecode(String s) {
  final parts = s.trim().split(RegExp(r'[:.]'));
  if (parts.isEmpty || parts.length > 3 || parts.any((p) => int.tryParse(p) == null)) return null;
  final n = [for (final p in parts) int.parse(p)];
  if (n.skip(1).any((x) => x >= 60)) return null;
  final sec = n.fold<int>(0, (a, x) => a * 60 + x);
  return sec <= 6 * 3600 ? sec : null;
}

/// Разбор матча текстом — для штаба или мессенджера.
String matchReviewText(Match m, Map<String, String> names) {
  final r = m.review;
  final out = StringBuffer('Разбор матча: ${m.opponent}${m.hasScore ? ' ${m.score}' : ''}\n');
  if (r.summary.isNotEmpty) out.write('\nИтоги:\n${r.summary}\n');
  if (r.conclusions.isNotEmpty) out.write('\nВыводы:\n${r.conclusions}\n');
  if (r.tasks.isNotEmpty) out.write('\nЗадачи на тренировку:\n${r.tasks.map((x) => '• $x').join('\n')}\n');
  if (r.playerNotes.isNotEmpty) {
    out.write('\nПо игрокам:\n${r.playerNotes.entries.map((e) => '• ${names[e.key] ?? 'Игрок'}: ${e.value}').join('\n')}\n');
  }
  if (r.episodes.isNotEmpty) {
    out.write('\nЭпизоды${r.videoUrl.isEmpty ? '' : ' (${r.videoUrl})'}:\n');
    for (final e in [...r.episodes]..sort((a, b) => a.t.compareTo(b.t))) {
      out.write('• ${e.time} ${VideoEpisode.tags[e.tag]}${e.comment.isEmpty ? '' : ': ${e.comment}'}\n');
    }
  }
  return out.toString().trimRight();
}

/// Эпизоды одного игрока — для индивидуальной обратной связи.
String playerFeedbackText(Match m, String playerId, Map<String, String> names) {
  final r = m.review;
  final eps = [for (final e in r.episodes) if (e.players.contains(playerId)) e]..sort((a, b) => a.t.compareTo(b.t));
  final out = StringBuffer('${names[playerId] ?? 'Игрок'}, разбор матча с ${m.opponent}\n');
  final note = r.playerNotes[playerId];
  if (note != null) out.write('\n$note\n');
  if (r.videoUrl.isNotEmpty) out.write('\nВидео: ${r.videoUrl}\n');
  out.write('\nЭпизоды:\n');
  for (final e in eps) {
    out.write('• ${e.time} — ${VideoEpisode.tags[e.tag]}${e.comment.isEmpty ? '' : ': ${e.comment}'}\n');
  }
  return out.toString().trimRight();
}
