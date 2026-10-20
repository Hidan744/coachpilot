import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/calendar.dart';
import '../../../core/file_import.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Календарь игр сезона из Excel, Word, CSV, TXT или вставленного текста.
class ImportMatchesScreen extends ConsumerStatefulWidget {
  const ImportMatchesScreen({super.key});

  @override
  ConsumerState<ImportMatchesScreen> createState() => _ImportMatchesScreenState();
}

class _ImportMatchesScreenState extends ConsumerState<ImportMatchesScreen> {
  String? _teamId;
  String? _source;
  List<ImportedMatch> _matches = [];
  final _selected = <int>{};
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _teamId = ref.read(currentTeamProvider)?.id;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _ownNames {
    final team = (ref.read(teamsProvider).value ?? const <Team>[]).where((t) => t.id == _teamId).firstOrNull;
    return [
      AppBrand.clubName.replaceFirst(RegExp(r'^(ФК|FC)\s+'), ''),
      if (team != null) ...team.name.split(RegExp(r'\s+')).where((w) => w.length > 3),
    ];
  }

  void _show(String source, List<List<String>> rows) {
    final matches = parseMatches(rows, now: DateTime.now(), ownNames: _ownNames);
    setState(() {
      _source = source;
      _matches = matches;
      _selected
        ..clear()
        ..addAll(List.generate(matches.length, (i) => i));
    });
    if (matches.isEmpty) showInfo(context, 'Не нашлось строк с датой и соперником.');
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: supportedTableExtensions);
    if (f == null) return;
    try {
      _show(f.name, readTable(f.name, await f.readAsBytes()));
    } on ImportException catch (e) {
      if (mounted) showInfo(context, e.message);
    }
  }

  Future<void> _import() async {
    final team = _teamId;
    if (team == null) return showInfo(context, 'Выберите команду');
    final repo = ref.read(repoProvider);
    for (final i in _selected.toList()..sort()) {
      final m = _matches[i];
      await repo.put(
        Entities.matches,
        Match(
          id: newId(),
          teamId: team,
          opponent: m.opponent,
          startsAt: m.startsAt,
          home: m.home,
          venue: m.venue,
          competition: m.competition,
        ),
      );
    }
    ref.read(analyticsProvider).track('matches_imported', {'count': _selected.length});
    if (!mounted) return;
    showInfo(context, 'Добавлено матчей: ${_selected.length}');
    popOr(context, '/calendar');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь игр')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        Text(
          'Загрузите календарь сезона из Excel, Word, CSV или вставьте текст. Подойдёт таблица с колонками '
          '«Дата», «Время», «Соперник», «Дома/в гостях», «Стадион», «Турнир» или строки вида '
          '«15.08 18:00 Зенит U16 (д)», «5 сентября, Амкар — Урал».',
          style: t.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (teams.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: teams.any((x) => x.id == _teamId) ? _teamId : null,
            decoration: const InputDecoration(labelText: 'Команда'),
            items: [for (final tm in teams) DropdownMenuItem(value: tm.id, child: Text(tm.name))],
            onChanged: (v) => setState(() => _teamId = v),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: const Text('Выбрать файл')),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Или вставьте список матчей'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _show('текст', [for (final l in _text.text.split('\n')) [l]]),
            child: const Text('Разобрать текст'),
          ),
        ),
        if (_source != null) ...[
          Text('Найдено матчей: ${_matches.length}', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Проверьте даты и снимите галочки с лишних строк. Изменить матч можно потом в календаре.',
              style: t.textTheme.bodySmall),
          for (var i = 0; i < _matches.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(i),
              onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
              title: Text(_matches[i].opponent),
              subtitle: Text([
                DateFormat('d MMM yyyy, EE HH:mm', 'ru').format(_matches[i].startsAt),
                _matches[i].home ? 'дома' : 'в гостях',
                if (_matches[i].venue.isNotEmpty) _matches[i].venue,
                if (_matches[i].competition.isNotEmpty) _matches[i].competition,
              ].join(' · ')),
            ),
        ],
      ]),
      bottomNavigationBar: _matches.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selected.isEmpty || _teamId == null ? null : _import,
                  child: Text('Добавить в календарь: ${_selected.length}'),
                ),
              ),
            ),
    );
  }
}
