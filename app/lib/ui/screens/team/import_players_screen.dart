import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/file_import.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../widgets/common.dart';

/// Импорт списка игроков из Excel, Word, CSV или TXT с предпросмотром.
class ImportPlayersScreen extends ConsumerStatefulWidget {
  const ImportPlayersScreen({super.key, required this.teamId});

  final String teamId;

  @override
  ConsumerState<ImportPlayersScreen> createState() => _ImportPlayersScreenState();
}

class _ImportPlayersScreenState extends ConsumerState<ImportPlayersScreen> {
  List<ImportedPlayer> _players = [];
  final _selected = <int>{};
  String? _fileName;
  Set<String> _existing = {};

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: supportedTableExtensions);
    if (f == null) return;
    try {
      final players = parsePlayers(readTable(f.name, await f.readAsBytes()));
      final existing = await ref.read(repoProvider).list(Entities.players, Player.fromJson, parentId: widget.teamId);
      setState(() {
        _fileName = f.name;
        _players = players;
        _existing = existing.map((p) => p.fullName.toLowerCase()).toSet();
        _selected
          ..clear()
          // Строки без фамилии и года (заголовки вроде «Состав U12») не отмечаем — тренер решит сам.
          ..addAll([
            for (var i = 0; i < players.length; i++)
              if (!_existing.contains(players[i].fullName.toLowerCase()) &&
                  (players[i].lastName.isNotEmpty || players[i].birthYear != null))
                i,
          ]);
      });
      if (players.isEmpty && mounted) showInfo(context, 'В файле не нашлось имён игроков.');
    } on ImportException catch (e) {
      if (mounted) showInfo(context, e.message);
    }
  }

  Future<void> _import() async {
    final repo = ref.read(repoProvider);
    for (final i in _selected.toList()..sort()) {
      final p = _players[i];
      await repo.put(
        Entities.players,
        Player(
          id: newId(),
          teamId: widget.teamId,
          firstName: p.firstName,
          lastName: p.lastName,
          birthYear: p.birthYear,
          position: p.position,
          number: p.number,
        ),
      );
    }
    ref.read(analyticsProvider).track('players_imported', {'count': _selected.length, 'file': _fileName?.split('.').last});
    if (!mounted) return;
    showInfo(context, 'Добавлено игроков: ${_selected.length}');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт игроков')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        Text(
          'Загрузите список из Excel (.xlsx), Word (.docx), CSV или TXT. Подойдёт таблица с колонками '
          '«Фамилия», «Имя», «Год рождения», «Позиция», «Номер» или просто список строк вида '
          '«Иванов Пётр 2014 нападающий №9».',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.upload_file),
          label: Text(_fileName == null ? 'Выбрать файл' : 'Другой файл'),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 16),
          Text('$_fileName · найдено: ${_players.length}', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Снимите галочки с лишних строк. Уже добавленные игроки отмечены.', style: t.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < _players.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(i),
              onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
              title: Text(_players[i].fullName),
              subtitle: Text([
                if (_players[i].birthYear != null) '${_players[i].birthYear} г.р.',
                if (_players[i].position != null) Positions.all[_players[i].position]!,
                if (_players[i].number != null) '№${_players[i].number}',
                if (_existing.contains(_players[i].fullName.toLowerCase())) 'уже в команде',
              ].join(' · ')),
            ),
        ],
      ]),
      bottomNavigationBar: _players.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : _import,
                  child: Text('Добавить в команду: ${_selected.length}'),
                ),
              ),
            ),
    );
  }
}
