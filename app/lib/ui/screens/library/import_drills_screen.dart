import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/drill_import.dart';
import '../../../core/file_import.dart';
import '../../../core/providers.dart';
import '../../../data/models.dart';
import '../../../data/repo.dart';
import '../../../sync/api_client.dart';
import '../../widgets/common.dart';
import 'library_screens.dart';

/// Импорт своих упражнений из файла (Word, Excel, TXT) или вставленного текста.
/// Описание раскладывается по полям карточки: с аккаунтом — AI на сервере, без сети — правила на телефоне.
class ImportDrillsScreen extends ConsumerStatefulWidget {
  const ImportDrillsScreen({super.key});

  @override
  ConsumerState<ImportDrillsScreen> createState() => _ImportDrillsScreenState();
}

class _ImportDrillsScreenState extends ConsumerState<ImportDrillsScreen> {
  final _text = TextEditingController();
  List<Drill> _drills = [];
  final _selected = <int>{};
  String? _source;
  bool _busy = false;

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx', 'xlsx', 'csv', 'txt']);
    if (f == null) return;
    try {
      final bytes = await f.readAsBytes();
      final ext = f.name.split('.').last.toLowerCase();
      // Таблица с колонкой «Название» разбирается по колонкам, остальное — как текст.
      if (ext == 'xlsx' || ext == 'csv') {
        final rows = readTable(f.name, bytes);
        final table = parseDrillsFromTable(rows);
        if (rows.isNotEmpty && rows.first.any((c) => c.toLowerCase().contains('назван'))) {
          _show(table, 'таблица');
          return;
        }
      }
      _text.text = readText(f.name, bytes);
      await _parse();
    } on ImportException catch (e) {
      if (mounted) showInfo(context, e.message);
    }
  }

  Future<void> _parse() async {
    final text = _text.text.trim();
    if (text.length < 10) {
      showInfo(context, 'Вставьте описание упражнения или выберите файл');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!ref.read(authProvider).demo) {
        try {
          final r = await ref.read(apiProvider).post('/ai/drills/parse', {'text': text}) as Json;
          final drills = (r['drills'] as List).cast<Json>().map((j) => Drill.fromJson(newId(), j)).toList();
          if (drills.isNotEmpty) {
            _show(drills, 'AI');
            return;
          }
        } on ApiException {
          // нет сети или ошибка сервера — разбираем на телефоне
        }
      }
      _show(parseDrillsFromText(text), 'правила');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(List<Drill> drills, String source) {
    setState(() {
      _drills = drills;
      _source = source;
      _selected
        ..clear()
        ..addAll(List.generate(drills.length, (i) => i));
    });
    if (drills.isEmpty) showInfo(context, 'Не удалось выделить упражнения. Начинайте каждое с названия на отдельной строке.');
  }

  Future<void> _import() async {
    final repo = ref.read(repoProvider);
    for (final i in _selected.toList()..sort()) {
      await repo.put(Entities.drills, _drills[i]);
    }
    ref.read(analyticsProvider).track('drills_imported', {'count': _selected.length, 'source': _source});
    ref.read(drillFilterProvider.notifier).update((f) => f.copyWith(tab: 'mine'));
    if (!mounted) return;
    showInfo(context, 'Добавлено в «Мои»: ${_selected.length}. Откройте упражнение, чтобы поправить текст или нарисовать схему.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт упражнений')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
          Text(
            'Загрузите свои упражнения файлом Word, Excel или TXT либо вставьте текст. '
            'Начинайте каждое упражнение с названия на отдельной строке; разделы вроде «Цель:», '
            '«Организация:», «Подсказки:», «Усложнение:» и нумерованные шаги распознаются автоматически.',
            style: t.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_file), label: const Text('Выбрать файл')),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'или вставьте текст',
              alignLabelWithHint: true,
              hintText: 'Квадрат 4 на 2\nЦель: удержание мяча\n1. Четверо по периметру держат мяч\n2. Двое отбирают',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _parse,
            icon: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'Разбираю…' : 'Разобрать текст'),
          ),
          if (_drills.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Найдено упражнений: ${_drills.length} · разбор: $_source', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Проверьте карточки. После добавления их можно изменить и нарисовать схему с анимацией.',
                style: t.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (var i = 0; i < _drills.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: Checkbox(
                    value: _selected.contains(i),
                    onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
                  ),
                  title: Text(_drills[i].title),
                  subtitle: Text('${DrillCategories.all[_drills[i].category]} · ${drillMeta(_drills[i])}'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [DrillDetails(_drills[i])],
                ),
              ),
          ],
        ]),
      ),
      bottomNavigationBar: _drills.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : _import,
                  child: Text('Добавить в «Мои»: ${_selected.length}'),
                ),
              ),
            ),
    );
  }
}
