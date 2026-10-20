// Разбор описаний упражнений из текста или таблицы — без AI (офлайн и в демо).
// С аккаунтом и сетью сначала пробуется AI-разбор на сервере (/ai/drills/parse).

import '../data/models.dart';
import '../data/repo.dart';

/// Категория по ключевым словам названия и цели.
String guessCategory(String text) {
  final t = text.toLowerCase();
  const rules = <(String, String)>[
    (r'разминк', 'warmup'),
    (r'заминк|растяжк', 'cooldown'),
    (r'вратар', 'goalkeeping'),
    (r'рондо|владен|квадрат', 'possession'),
    (r'удар|заверш|по воротам|добиван', 'finishing'),
    (r'передач|пас(?![а-яё])|пасы|стенк', 'passing'),
    (r'обводк|дриблинг|финт|1\s*[×xх]\s*1', 'dribbling'),
    (r'оборон|отбор|защит|прессинг', 'defending'),
    (r'переход|контратак', 'transition'),
    (r'тактик|позицион|схема игры|стандарт', 'tactics'),
    (r'выносл|скорост|рывк|ловкост|координац|физ', 'physical'),
    (r'игра(?![а-яё])|двусторон|турнир|матч', 'game'),
  ];
  for (final (p, c) in rules) {
    if (RegExp(p).hasMatch(t)) return c;
  }
  return 'technique';
}

const _equipmentWords = {
  'мяч': 'balls',
  'конус': 'cones',
  'фишк': 'cones',
  'маниш': 'bibs',
  'стойк': 'poles',
  'лестниц': 'ladder',
  'барьер': 'hurdles',
};

List<String> _equipment(String text) {
  final t = text.toLowerCase();
  final out = <String>{
    for (final e in _equipmentWords.entries)
      if (t.contains(e.key)) e.value,
    if (RegExp(r'мини[- ]?ворот').hasMatch(t)) 'mini_goals',
    if (RegExp(r'(?<!мини[- ]?)ворот').hasMatch(t)) 'goals',
  };
  return out.toList();
}

enum _Section { steps, goal, setup, rules, points, success, easier, harder, equipment }

const _headers = <(String, _Section)>[
  (r'^цел[ьи]', _Section.goal),
  (r'^(задач[аи])', _Section.goal),
  (r'^(организац|расстановк|подготовк|площадк)', _Section.setup),
  (r'^(инвентарь|оборудован)', _Section.equipment),
  (r'^(правил|условия|ограничен)', _Section.rules),
  (r'^(подсказк|ключевые|указани|методическ|акцент|тренер)', _Section.points),
  (r'^(критери|успех|результат)', _Section.success),
  (r'^(упрощ|облегч|проще)', _Section.easier),
  (r'^(усложн|сложнее|прогресси)', _Section.harder),
  (r'^(ход|выполнени|описание|как выполн|шаги|порядок)', _Section.steps),
];

final _bullet = RegExp(r'^\s*(?:\d{1,2}[.)]|[-–—•*·])\s*');

class _DrillDraft {
  _DrillDraft(this.title);

  String title;
  final goal = <String>[], setup = <String>[], steps = <String>[], rules = <String>[];
  final points = <String>[], success = <String>[], easier = <String>[], harder = <String>[], equipment = <String>[];
  int? duration, playersMin, playersMax, ageMin, ageMax;

  List<String> section(_Section s) => switch (s) {
        _Section.goal => goal,
        _Section.setup => setup,
        _Section.rules => rules,
        _Section.points => points,
        _Section.success => success,
        _Section.easier => easier,
        _Section.harder => harder,
        _Section.equipment => equipment,
        _Section.steps => steps,
      };

  bool get hasContent => steps.isNotEmpty || setup.isNotEmpty || goal.isNotEmpty || rules.isNotEmpty;

  Drill toDrill() {
    final all = [title, ...goal, ...setup, ...steps, ...equipment].join(' ');
    // Описание без нумерации — делим на шаги по предложениям.
    var stepList = steps;
    if (stepList.length == 1 && stepList.first.length > 80) {
      stepList = stepList.first.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().isNotEmpty).toList();
    }
    return Drill(
      id: newId(),
      source: 'user',
      title: title.length > 150 ? title.substring(0, 150) : title,
      category: guessCategory('$title ${goal.join(' ')}'),
      goal: goal.join(' '),
      setup: setup.join(' '),
      steps: stepList,
      rules: rules,
      coachingPoints: points,
      successCriteria: success,
      easier: easier,
      harder: harder,
      equipment: _equipment(equipment.isEmpty ? all : equipment.join(' ')),
      durationMin: (duration ?? 15).clamp(1, 120),
      playersMin: (playersMin ?? 2).clamp(1, 60),
      playersMax: (playersMax ?? 30).clamp(1, 60),
      ageMin: (ageMin ?? 6).clamp(4, 99),
      ageMax: (ageMax ?? 99).clamp(4, 99),
      tags: const ['импорт'],
    );
  }
}

bool _looksLikeTitle(String line, String? next) {
  final l = line.trim();
  if (l.isEmpty || l.length > 90 || _bullet.hasMatch(l)) return false;
  if (RegExp(r'^упражнени[ея]\s*(№\s*)?\d+', caseSensitive: false).hasMatch(l)) return true;
  if (l.endsWith('.') || l.endsWith(',') || l.contains(':')) return false;
  if (_headers.any((h) => RegExp(h.$1, caseSensitive: false).hasMatch(l.toLowerCase()))) return false;
  return next == null || next.trim().isEmpty || _bullet.hasMatch(next) || next.contains(':') || next.length > l.length;
}

void _meta(_DrillDraft d, String line) {
  final l = line.toLowerCase();
  final dur = RegExp(r'(\d{1,3})\s*(?:-|–)?\s*(?:\d{1,3}\s*)?мин').firstMatch(l);
  if (dur != null && (l.contains('время') || l.contains('длитель') || l.contains('продолж') || l.trim().startsWith(dur.group(0)!))) {
    d.duration ??= int.parse(dur.group(1)!);
  }
  final players = RegExp(r'(\d{1,2})\s*(?:-|–|до)\s*(\d{1,2})\s*игрок').firstMatch(l) ??
      RegExp(r'игрок[а-яё]*\s*:?\s*(\d{1,2})\s*(?:-|–|до)\s*(\d{1,2})').firstMatch(l);
  if (players != null) {
    d.playersMin ??= int.parse(players.group(1)!);
    d.playersMax ??= int.parse(players.group(2)!);
  }
  final age = RegExp(r'(\d{1,2})\s*(?:-|–)\s*(\d{1,2})\s*лет').firstMatch(l);
  if (age != null) {
    d.ageMin ??= int.parse(age.group(1)!);
    d.ageMax ??= int.parse(age.group(2)!);
  }
  final u = RegExp(r'\bu\s?(\d{1,2})\b').firstMatch(l);
  if (u != null && age == null) {
    d.ageMin ??= int.parse(u.group(1)!) - 1;
    d.ageMax ??= int.parse(u.group(1)!) + 1;
  }
}

/// Упражнения из свободного текста (Word, TXT).
List<Drill> parseDrillsFromText(String text) {
  final lines = text.split('\n').map((l) => l.replaceAll('\r', '').trimRight()).toList();
  final drafts = <_DrillDraft>[];
  _DrillDraft? cur;
  var section = _Section.steps;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final next = i + 1 < lines.length ? lines.sublist(i + 1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '') : null;
    if (_looksLikeTitle(line, next) && (cur == null || cur.hasContent)) {
      cur = _DrillDraft(line.replaceFirst(RegExp(r'^упражнени[ея]\s*(№\s*)?\d+[.:)]?\s*', caseSensitive: false), '').trim());
      if (cur.title.isEmpty) cur.title = line;
      drafts.add(cur);
      section = _Section.steps;
      continue;
    }
    cur ??= (drafts..add(_DrillDraft('Упражнение'))).last;
    _meta(cur, line);
    // «Цель: ...» — заголовок раздела с текстом в той же строке.
    final lower = line.toLowerCase();
    final header = _headers.where((h) => RegExp(h.$1).hasMatch(lower)).firstOrNull;
    var content = line;
    if (header != null) {
      section = header.$2;
      // «Цель: …», «Цель — …» или заголовок раздела отдельной строкой.
      final sep = RegExp(r'[:—–]|\s-\s').firstMatch(line);
      content = sep != null ? line.substring(sep.end).trim() : '';
      if (content.isEmpty) continue;
    } else if (line.length < 70 &&
        RegExp(r'\d').hasMatch(line) &&
        RegExp(r'^(время|длительн|продолж|игрок[а-яё]*\s*[:\d]|возраст|кол-во|количеств)', caseSensitive: false).hasMatch(lower)) {
      continue; // короткие строки метаданных («Время: 12 мин») уже разобраны
    } else if (RegExp(r'^\s*\d{1,2}[.)]\s').hasMatch(line) && (section == _Section.goal || section == _Section.setup)) {
      section = _Section.steps; // нумерованный список после цели или организации — это шаги
    } else if (section == _Section.goal && cur.goal.isNotEmpty) {
      section = _Section.steps; // после цели обычный абзац — описание выполнения
    }
    content = content.replaceFirst(_bullet, '').trim();
    if (content.isEmpty) continue;
    final list = cur.section(section);
    // В целях и организации абзацы склеиваем, в списках — отдельные пункты.
    if ((section == _Section.goal || section == _Section.setup) && list.isNotEmpty) {
      list[list.length - 1] = '${list.last} $content';
    } else {
      list.add(content);
    }
  }
  return drafts.where((d) => d.hasContent).map((d) => d.toDrill()).toList();
}

/// Упражнения из таблицы (Excel, CSV): строка — упражнение. Без заголовка — первая колонка название, вторая описание.
List<Drill> parseDrillsFromTable(List<List<String>> rows) {
  if (rows.isEmpty) return [];
  final head = rows.first.map((c) => c.toLowerCase()).toList();
  int col(List<String> keys) => head.indexWhere((h) => keys.any(h.contains));
  final title = col(['назван', 'упражнен']);
  if (title < 0) {
    return parseDrillsFromText(rows.map((r) => r.where((c) => c.isNotEmpty).join('\n')).join('\n\n'));
  }
  final idx = {
    'category': col(['категор', 'раздел', 'тип']),
    'goal': col(['цел', 'задач']),
    'setup': col(['организ', 'расстанов']),
    'steps': col(['описан', 'ход', 'выполн', 'шаг']),
    'rules': col(['правил']),
    'points': col(['подсказ', 'ключев', 'акцент']),
    'duration': col(['время', 'длитель', 'мин']),
    'players': col(['игрок', 'состав', 'кол']),
    'age': col(['возраст']),
    'equipment': col(['инвентар', 'оборудов']),
  };
  String cell(List<String> r, String key) {
    final i = idx[key]!;
    return i < 0 || i >= r.length ? '' : r[i].trim();
  }

  List<String> items(String s) => s
      .split(RegExp(r'\n|;|(?<=[.!?])\s+(?=\d+[.)]|[-•])'))
      .map((x) => x.replaceFirst(_bullet, '').trim())
      .where((x) => x.isNotEmpty)
      .toList();

  final out = <Drill>[];
  for (final r in rows.skip(1)) {
    final name = title < r.length ? r[title].trim() : '';
    if (name.isEmpty) continue;
    final d = _DrillDraft(name);
    d.goal.addAll(items(cell(r, 'goal')).take(1));
    d.setup.addAll(items(cell(r, 'setup')));
    d.steps.addAll(items(cell(r, 'steps')));
    d.rules.addAll(items(cell(r, 'rules')));
    d.points.addAll(items(cell(r, 'points')));
    d.equipment.addAll([cell(r, 'equipment')].where((x) => x.isNotEmpty));
    _meta(d, '${cell(r, 'duration')} мин время');
    final pl = RegExp(r'(\d{1,2})\D+(\d{1,2})').firstMatch(cell(r, 'players'));
    if (pl != null) {
      d.playersMin = int.parse(pl.group(1)!);
      d.playersMax = int.parse(pl.group(2)!);
    }
    _meta(d, cell(r, 'age').contains('лет') || cell(r, 'age').toLowerCase().contains('u') ? cell(r, 'age') : '${cell(r, 'age')} лет');
    var drill = d.toDrill();
    final cat = cell(r, 'category').toLowerCase();
    final known = DrillCategories.all.entries.where((e) => cat.isNotEmpty && e.value.toLowerCase().startsWith(cat.substring(0, cat.length.clamp(0, 5)))).firstOrNull;
    if (known != null) drill = Drill.fromJson(drill.id, {...drill.toJson(), 'category': known.key});
    out.add(drill);
  }
  return out;
}
