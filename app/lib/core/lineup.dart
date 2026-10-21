// Подбор состава под схему и стиль игры и подсказки замен по ходу матча.
// Правила простые и объяснимые: каждая рекомендация говорит, из каких цифр она следует.
// Решение всегда за тренером — приложение только раскладывает данные.

import 'dart:math' as math;

import '../data/models.dart';
import 'performance.dart';
import 'tactics.dart';

/// Стиль игры: название и чем он отличается.
const playStyles = {
  'press': ('Прессинг', 'Высокий отбор мяча: бег, спринты, отборы и подборы'),
  'possession': ('Владение', 'Контроль мяча: точные передачи, мало потерь'),
  'counter': ('Контратаки', 'Быстрые атаки: скорость, обводка, удары'),
};

/// Показатель игрока для сравнения внутри команды.
class _Metric {
  const _Metric(this.label, this.value, this.format, {this.lowerBetter = false});

  final String label;
  final double? Function(SeasonStats s) value;
  final String Function(double v) format;
  final bool lowerBetter;
}

String _f1(double v) => v.toStringAsFixed(1);
String _pct(double v) => '${v.round()}%';
double? _p90(SeasonStats s, String k) => s.minutes == 0 ? null : s.per90(k);
double? _phys(SeasonStats s, String k) => s[k] == 0 ? null : s.per90(k);

/// Играл вратарём: есть сейвы или пропущенные. Вратарей и полевых сравниваем отдельно.
bool _keeperStats(SeasonStats s) => s['saves'] > 0 || s['conceded'] > 0;
double? _gk(SeasonStats s, String k) => _keeperStats(s) ? _p90(s, k) : null;

final _metrics = <String, _Metric>{
  'tackles': _Metric('отбора за матч', (s) => _p90(s, 'tackles'), _f1),
  'interceptions': _Metric('перехвата за матч', (s) => _p90(s, 'interceptions'), _f1),
  'recoveries': _Metric('подбора за матч', (s) => _p90(s, 'recoveries'), _f1),
  'duel': _Metric('единоборств выиграно', (s) => s.duelRate, _pct),
  'pass': _Metric('точность передач', (s) => s.passAccuracy, _pct),
  'passes': _Metric('передач за матч', (s) => _p90(s, 'passes'), (v) => v.round().toString()),
  'key': _Metric('ключевых передач за матч', (s) => _p90(s, 'key_passes'), _f1),
  'assists': _Metric('голевых за матч', (s) => _p90(s, 'assists'), (v) => v.toStringAsFixed(2)),
  'dribbles': _Metric('обводки за матч', (s) => _p90(s, 'dribbles'), _f1),
  'crosses': _Metric('навеса за матч', (s) => _p90(s, 'crosses'), _f1),
  'goals': _Metric('гола за матч', (s) => _p90(s, 'goals'), (v) => v.toStringAsFixed(2)),
  'shots': _Metric('удара в створ за матч', (s) => _p90(s, 'shots_on'), _f1),
  'sprints': _Metric('спринтов за матч', (s) => _phys(s, 'sprints'), (v) => v.round().toString()),
  'distance': _Metric('км за матч', (s) => _phys(s, 'distance'), _f1),
  'speed': _Metric('км/ч макс. скорость', (s) => _phys(s, 'top_speed'), _f1),
  'losses': _Metric('потери за матч', (s) => _p90(s, 'losses'), _f1, lowerBetter: true),
  'rating': _Metric('средняя оценка', (s) => s.avgRating, _f1),
  'saves': _Metric('сейва за матч', (s) => _gk(s, 'saves'), _f1),
  'conceded': _Metric('пропущено за матч', (s) => _gk(s, 'conceded'), (v) => v.toStringAsFixed(2), lowerBetter: true),
};

/// Роль на позиции в схеме: какие показатели для неё главные.
class Role {
  const Role(this.key, this.label, this.line, this.weights);

  final String key, label;

  /// Линия: GK, DF, MF, FW.
  final String line;
  final Map<String, double> weights;
}

const roles = {
  'gk': Role('gk', 'Вратарь', 'GK', {'saves': 2, 'conceded': 2, 'rating': 1, 'pass': 0.5}),
  'cb': Role('cb', 'Центральный защитник', 'DF',
      {'interceptions': 1.5, 'duel': 1.5, 'tackles': 1, 'recoveries': 1, 'pass': 0.5, 'rating': 0.5}),
  'fb': Role('fb', 'Крайний защитник', 'DF',
      {'tackles': 1, 'crosses': 1, 'sprints': 1, 'interceptions': 0.7, 'distance': 0.7, 'pass': 0.5}),
  'dm': Role('dm', 'Опорный полузащитник', 'MF',
      {'interceptions': 1.5, 'recoveries': 1.5, 'tackles': 1, 'pass': 1, 'losses': 1}),
  'cm': Role('cm', 'Центральный полузащитник', 'MF',
      {'passes': 1, 'pass': 1, 'key': 1, 'distance': 1, 'recoveries': 0.7, 'assists': 0.5}),
  'am': Role('am', 'Атакующий полузащитник', 'MF', {'key': 1.5, 'assists': 1.5, 'dribbles': 1, 'shots': 1, 'goals': 1}),
  'wm': Role('wm', 'Крайний полузащитник', 'MF', {'crosses': 1.2, 'dribbles': 1, 'key': 1, 'sprints': 1, 'assists': 0.8}),
  'wf': Role('wf', 'Крайний нападающий', 'FW', {'dribbles': 1.3, 'goals': 1, 'sprints': 1, 'key': 0.8, 'speed': 0.8, 'shots': 0.7}),
  'st': Role('st', 'Центральный нападающий', 'FW', {'goals': 2, 'shots': 1.2, 'duel': 0.8, 'assists': 0.5}),
};

/// Что добавляет стиль игры к требованиям полевых ролей.
const _styleWeights = {
  'press': {'tackles': 0.8, 'recoveries': 0.8, 'sprints': 0.8, 'distance': 0.8, 'interceptions': 0.4},
  'possession': {'pass': 1.0, 'passes': 0.8, 'losses': 0.8, 'key': 0.5},
  'counter': {'sprints': 0.8, 'speed': 0.8, 'dribbles': 0.6, 'interceptions': 0.4, 'goals': 0.4},
};

/// Роли мест в схеме в порядке фишек на доске: вратарь, затем линии от обороны к атаке, слева направо.
List<Role> slotRoles(String formation) {
  final lines = formationLines(formation);
  final total = lines.fold(1, (a, b) => a + b);
  final out = <Role>[roles['gk']!];
  final mids = lines.length - 2; // линий между обороной и атакой
  for (var li = 0; li < lines.length; li++) {
    final n = lines[li];
    final keys = List.filled(n, 'cm');
    final edge = [0, n - 1];
    if (li == 0) {
      for (var i = 0; i < n; i++) {
        keys[i] = n >= 4 && edge.contains(i) ? 'fb' : 'cb';
      }
    } else if (li == lines.length - 1) {
      for (var i = 0; i < n; i++) {
        keys[i] = n >= 3 && edge.contains(i) ? 'wf' : 'st';
      }
    } else {
      final first = li == 1, last = li == lines.length - 2;
      for (var i = 0; i < n; i++) {
        final center = n.isOdd && i == n ~/ 2;
        keys[i] = switch (n) {
          >= 4 => edge.contains(i) ? 'wm' : (n == 5 && center ? 'dm' : 'cm'),
          3 when mids > 1 && last => center ? 'am' : 'wm',
          3 when total < 10 => center ? 'cm' : 'wm',
          3 => center ? 'dm' : 'cm',
          2 => mids > 1 && first ? 'dm' : 'cm',
          _ => mids > 1 ? (first ? 'dm' : 'am') : 'cm',
        };
      }
    }
    out.addAll(keys.map((k) => roles[k]!));
  }
  return out;
}

/// Готовность игрока к матчу: доступен ли, штраф к оценке и пояснения.
class Readiness {
  Readiness({this.unavailable, this.adjust = 0, this.notes = const []});

  /// Почему не может играть (травма, дисквалификация); null — доступен.
  final String? unavailable;

  /// Поправка к оценке: минус за усталость и пропуски, плюс за форму.
  final double adjust;
  final List<String> notes;

  bool get tired => notes.any((n) => n.contains('мин за'));
}

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// Готовность по последним матчам и тренировкам.
/// [matches] — сыгранные матчи игрока с датой, [attendance] — отметки с датой занятия.
Readiness readiness(
  Player p, {
  required List<(DateTime, MatchStat)> matches,
  required List<(DateTime, String)> attendance,
  required DateTime now,
}) {
  final notes = <String>[];
  var adjust = 0.0;

  final marks = [for (final a in attendance) if (a.$1.isBefore(now)) a]..sort((a, b) => b.$1.compareTo(a.$1));
  final injury = marks.where((a) => now.difference(a.$1).inDays <= 14).firstOrNull;
  if (injury != null && injury.$2 == 'injured') {
    return Readiness(unavailable: 'Травма (отмечено ${_dm(injury.$1)})');
  }

  final played = [for (final m in matches) if (m.$1.isBefore(now) && m.$2.minutes > 0) m]..sort((a, b) => b.$1.compareTo(a.$1));
  final last = played.firstOrNull;
  if (last != null && last.$2['red'] > 0 && now.difference(last.$1).inDays <= 10) {
    return Readiness(unavailable: 'Дисквалификация: красная карточка ${_dm(last.$1)}');
  }

  final days3 = played.where((m) => now.difference(m.$1).inHours < 72).fold(0, (a, m) => a + m.$2.minutes);
  final days7 = played.where((m) => now.difference(m.$1).inDays < 7).fold(0, (a, m) => a + m.$2.minutes);
  if (days3 >= 80) {
    adjust -= 8;
    notes.add('Играл $days3 мин за последние 3 дня — нужно восстановление');
  } else if (days7 >= 170) {
    adjust -= 6;
    notes.add('$days7 мин за неделю — высокая нагрузка');
  }

  final recent = [for (final a in marks) if (now.difference(a.$1).inDays <= 14 && a.$2 != 'excused') a];
  if (recent.length >= 2) {
    final missed = recent.where((a) => a.$2 == 'absent' || a.$2 == 'injured').length;
    if (missed * 2 > recent.length) {
      adjust -= 8;
      notes.add('Пропустил $missed из ${recent.length} последних тренировок');
    }
  }

  final ratings = [for (final m in played) ?m.$2.rating];
  if (ratings.length >= 4) {
    final form = mean(ratings.take(3)), season = mean(ratings);
    if (form - season >= 0.4) {
      adjust += 5;
      notes.add('В форме: ${form.toStringAsFixed(1)} в последних матчах');
    } else if (season - form >= 0.4) {
      adjust -= 5;
      notes.add('Спад: ${form.toStringAsFixed(1)} в последних матчах (за сезон ${season.toStringAsFixed(1)})');
    }
  }
  return Readiness(adjust: adjust, notes: notes);
}

/// Оценка игрока на роль: 0–100 и чем она объясняется.
class RoleFit {
  RoleFit(this.score, this.reasons, this.warnings);

  final int score;
  final List<String> reasons, warnings;
}

const _lineOrder = ['GK', 'DF', 'MF', 'FW'];

/// Перцентиль значения среди значений команды, 0–100.
double _percentile(double v, List<double> all, {bool lowerBetter = false}) {
  if (all.length < 2) return 50;
  final below = all.where((x) => lowerBetter ? x > v : x < v).length, equal = all.where((x) => x == v).length;
  return (below + equal / 2) * 100 / all.length;
}

/// Сравнение игроков команды по ролям.
class RoleScorer {
  RoleScorer(this.season, {this.style = 'press'}) {
    for (final e in _metrics.entries) {
      for (final keepers in [true, false]) {
        (keepers ? _keeperPeers : _fieldPeers)[e.key] = [
          for (final s in season.values)
            if (s.minutes >= 90 && _keeperStats(s) == keepers) ?e.value.value(s),
        ];
      }
    }
  }

  final Map<String, SeasonStats> season;
  final String style;

  /// С кем сравниваем: вратарей — с вратарями, полевых — с полевыми.
  final _keeperPeers = <String, List<double>>{}, _fieldPeers = <String, List<double>>{};

  Map<String, double> weights(Role role) {
    if (role.key == 'gk') return {...role.weights, if (style == 'possession') 'pass': 1.2};
    final w = {...role.weights};
    for (final e in (_styleWeights[style] ?? const <String, double>{}).entries) {
      w[e.key] = (w[e.key] ?? 0) + e.value;
    }
    return w;
  }

  RoleFit fit(Player p, Role role, [Readiness? ready]) {
    final s = season[p.id];
    final keeperSlot = role.line == 'GK', keeper = p.position == 'GK';
    final warnings = <String>[...?ready?.notes];
    final reasons = <String>[];
    double base;
    if (s == null || s.minutes < 90) {
      base = 40;
      reasons.add('Мало игрового времени — оценка по позиции');
    } else {
      final contrib = <(String, double, double, double)>[]; // показатель, вес, место в команде, значение
      for (final e in weights(role).entries) {
        final m = _metrics[e.key]!;
        final v = m.value(s);
        if (v == null) continue;
        contrib.add((e.key, e.value, _percentile(v, (keeperSlot ? _keeperPeers : _fieldPeers)[e.key] ?? const [], lowerBetter: m.lowerBetter), v));
      }
      final wsum = contrib.fold(0.0, (a, c) => a + c.$2);
      base = wsum == 0 ? 45 : contrib.fold(0.0, (a, c) => a + c.$2 * c.$3) / wsum;
      contrib.sort((a, b) => (b.$2 * b.$3).compareTo(a.$2 * a.$3));
      for (final c in contrib.where((c) => c.$3 >= 60).take(2)) {
        final m = _metrics[c.$1]!;
        reasons.add('${m.format(c.$4)} ${m.label}${c.$3 >= 85 ? ' — лучший в команде' : ''}');
      }
      if (reasons.isEmpty && contrib.isNotEmpty) {
        final m = _metrics[contrib.first.$1]!;
        reasons.add('${m.format(contrib.first.$4)} ${m.label}');
      }
    }
    // Позиция: своя линия — без штрафа, соседняя — минус, вратарь только в воротах.
    var pos = 0.0;
    if (keeperSlot != keeper) {
      pos = -60;
      warnings.add(keeperSlot ? 'Не вратарь' : 'Вратарь в поле');
    } else if (!keeperSlot && p.position != null && _lineOrder.contains(p.position) && p.position != role.line) {
      final gap = (_lineOrder.indexOf(p.position!) - _lineOrder.indexOf(role.line)).abs();
      pos = gap == 1 ? -12 : -25;
      warnings.add('Обычно играет: ${Positions.all[p.position]!.toLowerCase()}');
    }
    final score = (base + pos + (ready?.adjust ?? 0)).clamp(0, 100).round();
    return RoleFit(score, reasons, warnings);
  }
}

/// Место в составе: роль, выбранный игрок и запасные варианты со скамейки.
class LineupPick {
  LineupPick(this.role, this.player, this.fit, this.alternatives);

  final Role role;
  final Player? player;
  final RoleFit? fit;
  final List<(Player, RoleFit)> alternatives;
}

class Lineup {
  Lineup(this.formation, this.style, this.picks, this.bench, this.unavailable);

  final String formation, style;
  final List<LineupPick> picks;

  /// Скамейка: игрок, лучшая роль и оценка на неё.
  final List<(Player, Role, RoleFit)> bench;
  final List<(Player, String)> unavailable;

  List<Player?> get players => [for (final p in picks) p.player];

  /// Средняя оценка состава.
  int get strength {
    final s = [for (final p in picks) if (p.fit != null) p.fit!.score];
    return s.isEmpty ? 0 : mean(s).round();
  }
}

/// Подобрать состав: каждому месту — лучший доступный игрок с учётом роли, стиля и готовности.
/// Жадно: сначала самые уверенные пары «место — игрок», вратарь — только из вратарей, если они есть.
Lineup suggestLineup({
  required String formation,
  required String style,
  required List<Player> players,
  required Map<String, SeasonStats> season,
  required Map<String, Readiness> ready,
  Map<int, String> locked = const {},
}) {
  final slots = slotRoles(formation);
  final scorer = RoleScorer(season, style: style);
  final available = [for (final p in players) if (p.active && ready[p.id]?.unavailable == null) p];
  final unavailable = [
    for (final p in players)
      if (p.active && ready[p.id]?.unavailable != null) (p, ready[p.id]!.unavailable!),
  ];
  final fits = {
    for (var i = 0; i < slots.length; i++) i: {for (final p in available) p.id: scorer.fit(p, slots[i], ready[p.id])},
  };
  final chosen = <int, Player>{};
  final used = <String>{};
  for (final e in locked.entries) {
    final p = available.where((x) => x.id == e.value).firstOrNull;
    if (p != null && e.key < slots.length) {
      chosen[e.key] = p;
      used.add(p.id);
    }
  }
  final pairs = [
    for (var i = 0; i < slots.length; i++)
      if (!chosen.containsKey(i))
        for (final p in available)
          if (!used.contains(p.id)) (i, p, fits[i]![p.id]!.score),
  ]..sort((a, b) => b.$3.compareTo(a.$3));
  for (final (i, p, _) in pairs) {
    if (chosen.containsKey(i) || used.contains(p.id)) continue;
    chosen[i] = p;
    used.add(p.id);
  }
  final benchPlayers = [for (final p in available) if (!used.contains(p.id)) p];
  final picks = [
    for (var i = 0; i < slots.length; i++)
      LineupPick(
        slots[i],
        chosen[i],
        chosen[i] == null ? null : fits[i]![chosen[i]!.id],
        ([for (final b in benchPlayers) (b, fits[i]![b.id]!)]..sort((a, b) => b.$2.score.compareTo(a.$2.score)))
            .where((a) => !a.$2.warnings.any((w) => w == 'Не вратарь' || w == 'Вратарь в поле'))
            .take(2)
            .toList(),
      ),
  ];
  final bench = [
    for (final b in benchPlayers)
      () {
        var best = (slots.first, fits[0]![b.id]!);
        for (var i = 1; i < slots.length; i++) {
          if (fits[i]![b.id]!.score > best.$2.score) best = (slots[i], fits[i]![b.id]!);
        }
        return (b, best.$1, best.$2);
      }(),
  ]..sort((a, b) => b.$3.score.compareTo(a.$3.score));
  return Lineup(formation, style, picks, bench, unavailable);
}

// ---------------------------------------------------------------- замены по ходу матча

/// Подсказка замены: кто уходит, кто выходит и почему.
class SubAdvice {
  SubAdvice(this.out, this.into, this.why, this.plan);

  final Player out;
  final Player? into;

  /// Почему менять этого игрока.
  final List<String> why;

  /// Почему выходит этот игрок (и что меняет в игре).
  final String plan;
}

/// Роль по умолчанию для игрока своей позиции.
Role _naturalRole(Player p) => switch (p.position) {
      'GK' => roles['gk']!,
      'DF' => roles['cb']!,
      'FW' => roles['st']!,
      _ => roles['cm']!,
    };

/// Подсказки замен: по действиям в этом матче, карточкам, нагрузке и счёту.
/// [live] — статистика игроков в текущем матче.
List<SubAdvice> substitutionAdvice({
  required List<Player> onField,
  required List<Player> bench,
  required Map<String, MatchStat> live,
  required int minute,
  required int ourGoals,
  required int theirGoals,
  required Map<String, SeasonStats> season,
  required Map<String, Readiness> ready,
  String style = 'press',
  int limit = 3,
}) {
  final scorer = RoleScorer(season, style: style);
  final diff = ourGoals - theirGoals;
  final mode = diff < 0 && minute >= 55
      ? 'attack'
      : diff > 0 && minute >= 65
          ? 'defend'
          : 'same';
  final freeBench = [for (final b in bench) if (ready[b.id]?.unavailable == null) b];
  final candidates = <(Player, double, List<String>)>[];

  for (final p in onField) {
    if (p.position == 'GK') continue;
    final s = live[p.id];
    double weight = 0;
    final why = <String>[];
    if (s != null) {
      if (s['yellow'] > 0 && (s['fouls'] >= 2 || minute >= 55)) {
        weight += 3;
        why.add('Жёлтая карточка${s['fouls'] >= 2 ? ' и ${s['fouls'].round()} фола' : ''} — риск удаления');
      }
      final duels = s['duels'], won = s['duels_won'];
      if (duels >= 4 && won / duels < 0.4) {
        weight += 2;
        why.add('Проиграл ${(duels - won).round()} из ${duels.round()} единоборств');
      }
      if (s['losses'] >= 4) {
        weight += 2;
        why.add('${s['losses'].round()} потерь мяча');
      }
      final useful = ['goals', 'assists', 'key_passes', 'shots_on', 'tackles', 'interceptions', 'recoveries', 'dribbles']
          .fold(0.0, (a, k) => a + s[k]);
      if (minute >= 60 && useful == 0 && live.values.any((x) => x.stats.isNotEmpty)) {
        weight += 1;
        why.add('Нет заметных действий за $minute мин');
      }
    }
    if (minute >= 60 && (ready[p.id]?.tired ?? false)) {
      weight += 1.5;
      why.add(ready[p.id]!.notes.firstWhere((n) => n.contains('мин за')));
    }
    // Тактическая замена: проигрываем — убираем защитника/опорного, ведём — нападающего.
    if (mode == 'attack' && (p.position == 'DF' || p.position == 'MF') && why.isEmpty) {
      weight += p.position == 'DF' ? 0.6 : 0.4;
      why.add('Проигрываем $ourGoals:$theirGoals — нужен ещё один игрок атаки');
    } else if (mode == 'defend' && p.position == 'FW' && why.isEmpty) {
      weight += 0.5;
      why.add('Ведём $ourGoals:$theirGoals — усиливаем оборону');
    }
    if (weight > 0) candidates.add((p, weight, why));
  }
  candidates.sort((a, b) => b.$2.compareTo(a.$2));

  final out = <SubAdvice>[];
  final taken = <String>{};
  var tacticalUsed = false;
  for (final (p, _, why) in candidates) {
    if (out.length >= limit) break;
    final tactical = why.length == 1 && why.first.startsWith(mode == 'attack' ? 'Проигрываем' : 'Ведём');
    if (tactical && tacticalUsed) continue;
    final target = switch (mode) {
      'attack' => roles['st']!,
      'defend' => roles[p.position == 'FW' ? 'dm' : 'cb']!,
      _ => _naturalRole(p),
    };
    final options = [
      for (final b in freeBench)
        if (!taken.contains(b.id) && b.position != 'GK') (b, scorer.fit(b, target, ready[b.id])),
    ]..sort((a, b) => b.$2.score.compareTo(a.$2.score));
    final best = options.firstOrNull;
    if (best == null) continue;
    taken.add(best.$1.id);
    if (tactical) tacticalUsed = true;
    final change = switch (mode) {
      'attack' => 'Проигрываем — больше атаки: ${target.label.toLowerCase()}',
      'defend' => 'Ведём — закрываем игру: ${target.label.toLowerCase()}',
      _ => 'Та же позиция: ${target.label.toLowerCase()}',
    };
    final because = best.$2.reasons.isEmpty ? '' : '. ${best.$2.reasons.first}';
    out.add(SubAdvice(p, best.$1, why, '$change$because'));
  }
  return out;
}

/// Кто сейчас на поле по статистике матча: есть минуты, не удалён и не заменён.
/// Заменённый — вышел в старте и сыграл меньше всего матча; вышедший на замену — не в старте.
bool onFieldNow(MatchStat? s, int duration) =>
    s != null && s.minutes > 0 && s['red'] == 0 && !(s.started && s.minutes < duration);

/// Минута для расчёта (от 1 до длительности матча).
int clampMinute(int minute, int duration) => math.max(1, math.min(minute, duration));

/// Готовность всех игроков команды по матчам и отметкам посещаемости.
Map<String, Readiness> teamReadiness({
  required List<Player> players,
  required List<Match> matches,
  required List<MatchStat> stats,
  required List<Attendance> attendance,
  required Map<String, TrainingSession> sessions,
  required DateTime now,
}) {
  final matchAt = {for (final m in matches) m.id: m.startsAt};
  return {
    for (final p in players)
      p.id: readiness(
        p,
        matches: [
          for (final s in stats)
            if (s.playerId == p.id && matchAt[s.matchId] != null) (matchAt[s.matchId]!, s),
        ],
        attendance: [
          for (final a in attendance)
            if (a.playerId == p.id && sessions[a.sessionId] != null)
              if ((sessions[a.sessionId]!.startedAt ?? sessions[a.sessionId]!.scheduledAt) case final at?) (at, a.status),
        ],
        now: now,
      ),
  };
}

/// Расстановка для числа игроков команды: первая подходящая схема формата.
List<String> formationsFor(int players) => formations.entries
    .firstWhere((e) => playersInFormation(e.value.first) == players, orElse: () => formations.entries.first)
    .value;
