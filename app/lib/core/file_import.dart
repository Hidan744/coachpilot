// Чтение таблиц и текста из файлов (Excel, Word, CSV, TXT) и разбор списков игроков.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

const supportedTableExtensions = ['xlsx', 'docx', 'csv', 'txt'];

String _ext(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';

/// Таблица из файла: строки → ячейки. Абзацы Word и строки текста — строки из одной ячейки.
List<List<String>> readTable(String fileName, Uint8List bytes) {
  switch (_ext(fileName)) {
    case 'xlsx':
      return _readXlsx(bytes);
    case 'docx':
      return _readDocx(bytes);
    case 'csv' || 'txt' || 'tsv':
      return _readText(_decodeText(bytes));
    case 'xls' || 'doc':
      throw ImportException('Старый формат .${_ext(fileName)} не поддерживается. Сохраните файл как .xlsx или .docx.');
    default:
      throw ImportException('Поддерживаются файлы Excel (.xlsx), Word (.docx), CSV и TXT.');
  }
}

/// Сплошной текст файла (для разбора описаний упражнений).
String readText(String fileName, Uint8List bytes) {
  switch (_ext(fileName)) {
    case 'docx':
      return _readDocx(bytes).map((r) => r.join(' | ')).join('\n');
    case 'xlsx':
      return _readXlsx(bytes).map((r) => r.join(' | ')).join('\n');
    case 'txt' || 'md' || 'csv':
      return _decodeText(bytes);
    default:
      throw ImportException('Поддерживаются файлы Word (.docx), Excel (.xlsx) и текст (.txt).');
  }
}

String _decodeText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Файлы из старого Excel/Блокнота бывают в Windows-1251.
    return _cp1251(bytes);
  }
}

String _cp1251(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b < 0x80) {
      sb.writeCharCode(b);
    } else if (b >= 0xC0) {
      sb.writeCharCode(0x0410 + b - 0xC0);
    } else if (b == 0xA8) {
      sb.write('Ё');
    } else if (b == 0xB8) {
      sb.write('ё');
    } else {
      sb.write(' ');
    }
  }
  return sb.toString();
}

List<List<String>> _readText(String text) {
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return [];
  // Разделитель — тот, что чаще встречается в первых строках.
  final sample = lines.take(5).join('\n');
  final delim = [';', '\t', ','].reduce((a, b) => a.allMatches(sample).length >= b.allMatches(sample).length ? a : b);
  final useDelim = delim.allMatches(sample).isNotEmpty;
  return [
    for (final l in lines)
      useDelim ? l.split(delim).map((c) => c.trim().replaceAll(RegExp(r'^"|"$'), '')).toList() : [l.trim()],
  ];
}

List<List<String>> _readXlsx(Uint8List bytes) {
  final Excel book;
  try {
    book = Excel.decodeBytes(bytes);
  } catch (_) {
    throw ImportException('Не удалось открыть файл Excel. Проверьте, что это .xlsx.');
  }
  for (final sheet in book.tables.values) {
    final rows = [
      for (final r in sheet.rows)
        [for (final c in r) _cellText(c?.value)],
    ].where((r) => r.any((c) => c.isNotEmpty)).toList();
    if (rows.isNotEmpty) return rows;
  }
  return [];
}

String _cellText(CellValue? v) => switch (v) {
      null => '',
      TextCellValue() => v.value.toString().trim(),
      IntCellValue() => '${v.value}',
      DoubleCellValue() => v.value == v.value.roundToDouble() ? '${v.value.round()}' : '${v.value}',
      DateCellValue() => '${v.day.toString().padLeft(2, '0')}.${v.month.toString().padLeft(2, '0')}.${v.year}',
      _ => v.toString().trim(),
    };

List<List<String>> _readDocx(Uint8List bytes) {
  final XmlDocument doc;
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.findFile('word/document.xml');
    if (file == null) throw ImportException('В файле Word нет текста.');
    doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
  } on ImportException {
    rethrow;
  } catch (_) {
    throw ImportException('Не удалось открыть файл Word. Проверьте, что это .docx.');
  }
  String text(XmlElement e) => e.descendants.whereType<XmlElement>().where((x) => x.name.local == 't').map((x) => x.innerText).join();
  final body = doc.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'body');
  final rows = <List<String>>[];
  for (final el in body.childElements) {
    if (el.name.local == 'tbl') {
      for (final tr in el.descendants.whereType<XmlElement>().where((e) => e.name.local == 'tr')) {
        rows.add([for (final tc in tr.childElements.where((e) => e.name.local == 'tc')) text(tc).trim()]);
      }
    } else if (el.name.local == 'p') {
      final t = text(el).trim();
      if (t.isNotEmpty) rows.add([t]);
    }
  }
  return rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
}

// ---------------------------------------------------------------- игроки

class ImportedPlayer {
  ImportedPlayer({required this.firstName, this.lastName = '', this.birthYear, this.position, this.number});

  final String firstName, lastName;
  final int? birthYear;
  final String? position;
  final int? number;

  String get fullName => lastName.isEmpty ? firstName : '$firstName $lastName';
}

const _positionAliases = {
  'GK': ['вр', 'gk', 'вратарь', 'голкипер'],
  'DF': ['защ', 'df', 'цз', 'кз', 'лз', 'защитник', 'защита'],
  'MF': ['пз', 'п/з', 'mf', 'цп', 'хав', 'опорный', 'полузащитник', 'полузащита'],
  'FW': ['нап', 'fw', 'форвард', 'нападающий', 'нападение'],
};
const _positionStems = {'вратар': 'GK', 'голкип': 'GK', 'полузащ': 'MF', 'защитн': 'DF', 'нападающ': 'FW'};

/// Позиция по слову: точное сокращение или начало полного названия (не путается с фамилиями).
String? _position(String s) {
  final w = s.toLowerCase().replaceAll('.', '').trim();
  if (w.isEmpty) return null;
  for (final e in _positionStems.entries) {
    if (w.startsWith(e.key)) return e.value;
  }
  for (final e in _positionAliases.entries) {
    if (e.value.contains(w)) return e.key;
  }
  return null;
}

final _surnameEnd = RegExp(r'(ов|ев|ёв|ин|ын|ский|цкий|ской|ова|ева|ёва|ина|ына|ская|цкая|енко|ук|юк|ых|их|ян|дзе|швили)$', caseSensitive: false);
final _patronymic = RegExp(r'(вич|вна|ична|ич)$', caseSensitive: false);

int? _year(String s) {
  final d = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b').firstMatch(s);
  if (d != null) return int.parse(d.group(3)!);
  final y = RegExp(r'\b(19[4-9]\d|20[0-3]\d)\b').firstMatch(s);
  return y == null ? null : int.parse(y.group(1)!);
}

/// Колонки по заголовку таблицы.
Map<String, int>? _headerMap(List<String> row) {
  final map = <String, int>{};
  for (var i = 0; i < row.length; i++) {
    final h = row[i].toLowerCase();
    if (h.contains('фамил')) {
      map['last'] = i;
    } else if (h.contains('фио') || h.contains('игрок') || h == 'ф.и.о.' || h.contains('name')) {
      map['full'] = i;
    } else if (h.contains('отчеств')) {
      map['patronymic'] = i;
    } else if (h.contains('имя')) {
      map['first'] = i;
    } else if (h.contains('год') || h.contains('рожд') || h.contains('г.р') || h.contains('дата')) {
      map['year'] = i;
    } else if (h.contains('позиц') || h.contains('амплуа') || h.contains('линия')) {
      map['position'] = i;
    } else if (h.contains('номер') || h == '№' || h.contains('number')) {
      map['number'] = i;
    }
  }
  return map.containsKey('last') || map.containsKey('first') || map.containsKey('full') ? map : null;
}

(String, String) _splitName(List<String> words) {
  final w = words.where((x) => !_patronymic.hasMatch(x) || words.length < 3).toList();
  if (w.isEmpty) return ('', '');
  if (w.length == 1) return (w[0], '');
  // «Иванов Пётр» или «Пётр Иванов»: фамилию узнаём по окончанию, по умолчанию — первая (как в списках).
  if (_surnameEnd.hasMatch(w[1]) && !_surnameEnd.hasMatch(w[0])) return (w[0], w[1]);
  return (w[1], w[0]);
}

ImportedPlayer? _fromLoose(String line) {
  var s = line.replaceFirst(RegExp(r'^\s*\d{1,3}[.)]\s+'), ''); // «1. Иванов…»
  final year = _year(s);
  s = s.replaceAll(RegExp(r'\b\d{1,2}[./-]\d{1,2}[./-]\d{4}\b'), ' ').replaceAll(RegExp(r'\b(19|20)\d\d\b'), ' ');
  int? number;
  final num = RegExp(r'(?:№\s*|#\s*|\b)(\d{1,2})\b').firstMatch(s);
  if (num != null) {
    number = int.parse(num.group(1)!);
    s = s.replaceFirst(num.group(0)!, ' ');
  }
  String? position;
  final words = <String>[];
  for (final raw in s.split(RegExp(r'[\s,;|]+'))) {
    final w = raw.replaceAll(RegExp(r'[()"«»]'), '').trim();
    if (w.isEmpty || const {'г', 'г.', 'г.р.', 'гр', 'г.р'}.contains(w.toLowerCase())) continue;
    final pos = _position(w);
    if (pos != null) {
      position ??= pos;
      continue;
    }
    if (RegExp(r'^[а-яёa-z][а-яёa-z\-]+$', caseSensitive: false).hasMatch(w)) {
      words.add(w[0].toUpperCase() + w.substring(1));
    }
  }
  final (first, last) = _splitName(words.take(3).toList());
  if (first.isEmpty) return null;
  return ImportedPlayer(firstName: first, lastName: last, birthYear: year, position: position, number: number);
}

/// Разбор списка игроков из таблицы или текста.
List<ImportedPlayer> parsePlayers(List<List<String>> rows) {
  if (rows.isEmpty) return [];
  final header = _headerMap(rows.first);
  final out = <ImportedPlayer>[];
  if (header != null) {
    String cell(List<String> r, String key) {
      final i = header[key];
      return i == null || i >= r.length ? '' : r[i].trim();
    }

    for (final r in rows.skip(1)) {
      var first = cell(r, 'first'), last = cell(r, 'last');
      if (header.containsKey('full') && first.isEmpty && last.isEmpty) {
        final p = _fromLoose(cell(r, 'full'));
        if (p == null) continue;
        first = p.firstName;
        last = p.lastName;
      }
      if (first.isEmpty && last.isEmpty) continue;
      if (first.isEmpty) (first, last) = (last, '');
      out.add(ImportedPlayer(
        firstName: first,
        lastName: last,
        birthYear: _year(cell(r, 'year')),
        position: _position(cell(r, 'position')),
        number: int.tryParse(cell(r, 'number').replaceAll(RegExp(r'\D'), '')),
      ));
    }
    return out;
  }
  for (final r in rows) {
    final p = _fromLoose(r.join(' '));
    if (p != null) out.add(p);
  }
  return out;
}
