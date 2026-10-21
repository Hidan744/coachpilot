// План по правилам из локальной библиотеки — работает без сети и без AI.
// Логика повторяет backend/app/ai/rules.py.

import 'dart:math' as math;

import '../data/models.dart';
import '../ui/screens/library/library_screens.dart' show drillFitsTeam;

const _goalKeywords = <(String, List<String>)>[
  (r'пас|передач|перевод', ['passing', 'possession']),
  (r'удар|заверш|забив|голев', ['finishing']),
  (r'владен|контрол[ья] мяч|рондо', ['possession', 'passing']),
  (r'обводк|дриблинг|финт|1\s*[×xх]\s*1|один в один', ['dribbling']),
  (r'оборон|отбор|защит', ['defending']),
  (r'переход|контратак|контрпрессинг', ['transition', 'tactics']),
  (r'прессинг|тактик|позицион|выход из обороны|стандарт', ['tactics']),
  (r'техник|приём|прием|первое касание|ведени', ['technique', 'dribbling']),
  (r'физ|выносл|скорост|ловкост|координац', ['physical']),
  (r'вратар', ['goalkeeping']),
];

const _focusCategories = {
  'technique': ['technique', 'passing', 'dribbling'],
  'tactics': ['tactics', 'possession', 'transition'],
  'physical': ['physical'],
  'game': ['game'],
};

const _defaultMain = ['passing', 'possession', 'technique', 'dribbling', 'finishing'];

List<String> mainCategories(String goal, [List<String> focus = const []]) {
  final g = goal.toLowerCase();
  final cats = <String>[];
  for (final (pattern, cs) in _goalKeywords) {
    if (RegExp(pattern).hasMatch(g)) cats.addAll(cs.where((c) => !cats.contains(c)));
  }
  for (final f in focus) {
    cats.addAll((_focusCategories[f] ?? []).where((c) => !cats.contains(c)));
  }
  return cats.isEmpty ? _defaultMain : cats;
}

/// Длительности по фазам, сумма ровно [total].
Map<String, List<int>> splitDurations(int total) {
  final warm = (total * 0.18).round().clamp(8, 20);
  final cool = total >= 45 ? (total * 0.08).round().clamp(5, 10) : 0;
  final game = total >= 40 ? (total * 0.27).round().clamp(8, 999) : 0;
  final main = total - warm - cool - game;
  return {
    'warmup': [warm],
    'main': main < 30 ? [main] : [main ~/ 2 + main % 2, main ~/ 2],
    'game': [if (game > 0) game],
    'cooldown': [if (cool > 0) cool],
  };
}

Json drillSnapshot(Drill d) => d.toJson();

const intensityLabels = {'low': 'Низкая', 'medium': 'Средняя', 'high': 'Высокая'};
const formatLabels = {'team': 'Командная', 'group': 'Групповая', 'individual': 'Индивидуальная'};
const _intensityRank = {'low': 0, 'medium': 1, 'high': 2};

/// Что тренировать для позиции: защитникам — оборону, нападающим — удары и обводку.
const positionCategories = {
  'GK': ['goalkeeping'],
  'DF': ['defending'],
  'MF': ['passing', 'possession'],
  'FW': ['finishing', 'dribbling'],
};
const _positionLabels = {'GK': 'вратари', 'DF': 'защитники', 'MF': 'полузащитники', 'FW': 'нападающие'};

/// Индивидуальная работа: техника, обводка, удары, ОФП — без игровой части.
const _individualCategories = ['technique', 'dribbling', 'finishing', 'physical', 'passing'];

String _mmss(int seconds) {
  final m = seconds ~/ 60, s = seconds % 60;
  return s == 0 ? '$m мин' : (m == 0 ? '$s с' : '$m мин $s с');
}

/// Дозировка блока: серии работы и отдыха, в сумме ровно [minutes].
String dosageFor(int minutes, String phase, String intensity) {
  if (phase == 'warmup' || phase == 'cooldown' || minutes < 6 || intensity == 'low') {
    return 'Непрерывно $minutes мин${phase == 'main' && intensity == 'low' ? ', паузы на объяснение по ходу' : ''}';
  }
  final series = intensity == 'high' ? (minutes ~/ 4).clamp(2, 6) : (minutes >= 12 ? 2 : 1);
  if (series == 1) return 'Одна серия $minutes мин';
  final rest = 60;
  final work = (minutes * 60 - (series - 1) * rest) ~/ series;
  final extra = minutes * 60 - (series - 1) * rest - work * series; // остаток — к последней серии
  return '$series серии × ${_mmss(work)}, отдых ${_mmss(rest)} между сериями'
      '${extra > 0 ? ' (последняя +${_mmss(extra)})' : ''}';
}

/// Почему упражнение попало в план: цель, возраст, состав, инвентарь, интенсивность.
String whyFor(Drill d, String phase, {required String goal, required String intensity, String? position, bool fresh = false}) {
  final cat = DrillCategories.all[d.category] ?? d.category;
  final fit = 'возраст ${d.ageMin}–${d.ageMax} лет, от ${d.playersMin} игроков'
      '${d.equipment.isEmpty ? ', без инвентаря' : ', инвентарь есть'}';
  final ints = 'интенсивность ${(intensityLabels[d.intensity] ?? d.intensity).toLowerCase()}';
  return switch (phase) {
    'warmup' => 'Разминка ($ints): подготовить мышцы и внимание к основной части. Подходит: $fit.',
    'cooldown' => 'Заминка: снизить пульс и нагрузку после игры. Подходит: $fit.',
    'game' => 'Игровая часть: закрепить «$goal» в игровой ситуации. Категория «$cat», $ints; $fit.',
    _ => 'Цель «$goal» → категория «$cat»${position == null ? '' : ' (для: ${_positionLabels[position]})'}. '
        'Подходит: $fit; $ints.${fresh ? ' Не повторяет последние занятия.' : ''}',
  };
}

/// Собрать блоки плана из подходящих упражнений библиотеки.
/// [format]: team | group | individual; [intensity]: low | medium | high;
/// [positions]: GK, DF, MF, FW — акцент на работу линии; [level]: beginner → упрощённые варианты.
List<TrainingBlock> planByRules({
  required List<Drill> library,
  required Team team,
  required int players,
  required int durationMin,
  required String goal,
  List<String> equipment = const [],
  List<String> focus = const [],
  Set<String> recentDrillIds = const {},
  String format = 'team',
  String intensity = 'medium',
  List<String> positions = const [],
  String? level,
}) {
  final t = Team(
    id: team.id,
    name: team.name,
    ageGroup: team.ageGroup,
    level: team.level,
    defaultPlayers: players,
    equipment: equipment.isEmpty ? team.equipment : equipment,
  );
  final individual = format == 'individual';
  // Индивидуально: подходит упражнение для пары с тренером или помощником (до 4 человек).
  bool fits(Drill d) => individual
      ? drillFitsTeam(d, t, players: math.max(players, d.playersMin)) && d.playersMin <= 4
      : drillFitsTeam(d, t, players: players);
  final fitting = library.where(fits).toList();
  final cats = [
    ...{
      for (final p in positions) ...?positionCategories[p],
      ...mainCategories(goal, focus).where((c) => !individual || _individualCategories.contains(c)),
      if (individual) ..._individualCategories,
    },
  ];
  final used = <String>{};
  final want = _intensityRank[intensity] ?? 1;

  Drill? pick(List<String> allowed, {int target = 1}) {
    final pool = fitting.where((d) => allowed.contains(d.category) && !used.contains(d.id)).toList()
      ..sort((a, b) {
        final r = (recentDrillIds.contains(a.id) ? 1 : 0).compareTo(recentDrillIds.contains(b.id) ? 1 : 0);
        if (r != 0) return r;
        final c = allowed.indexOf(a.category).compareTo(allowed.indexOf(b.category));
        if (c != 0) return c;
        final i = ((_intensityRank[a.intensity] ?? 1) - target).abs().compareTo(((_intensityRank[b.intensity] ?? 1) - target).abs());
        if (i != 0) return i;
        return '$goal${a.id}'.hashCode.compareTo('$goal${b.id}'.hashCode);
      });
    if (pool.isEmpty) return null;
    used.add(pool.first.id);
    return pool.first;
  }

  final durations = splitDurations(durationMin);
  if (individual && durations['game']!.isNotEmpty) {
    // Без игровой части: её время — в основную.
    final g = durations['game']!.first;
    durations['game'] = [];
    final main = durations['main']!;
    durations['main'] = main.length == 1 && main.first + g >= 30
        ? [(main.first + g) ~/ 2 + (main.first + g) % 2, (main.first + g) ~/ 2]
        : [...main.take(main.length - 1), main.last + g];
  }
  final phaseCats = {
    'warmup': ['warmup'],
    'main': cats,
    'game': ['game', 'possession'],
    'cooldown': ['cooldown'],
  };
  final phaseTarget = {'warmup': 0, 'main': want, 'game': math.max(want, 1), 'cooldown': 0};
  final blocks = <TrainingBlock>[];
  var n = 0;
  final easier = level == 'beginner';
  for (final phase in ['warmup', 'main', 'game', 'cooldown']) {
    for (final minutes in durations[phase]!) {
      final d = pick(phaseCats[phase]!, target: phaseTarget[phase]!) ??
          (phase == 'main' ? pick(individual ? _individualCategories : _defaultMain, target: want) : null);
      if (d == null) continue;
      final position = phase == 'main'
          ? positions.where((p) => (positionCategories[p] ?? const []).contains(d.category)).firstOrNull
          : null;
      final variant = easier && phase == 'main' && d.easier.isNotEmpty ? 'easier' : 'base';
      blocks.add(TrainingBlock(
        id: 'b${++n}',
        phase: phase,
        title: d.title,
        durationMin: minutes,
        drillId: d.id,
        drill: drillSnapshot(d),
        why: whyFor(d, phase, goal: goal, intensity: intensity, position: position, fresh: recentDrillIds.isNotEmpty && !recentDrillIds.contains(d.id)) +
            (variant == 'easier' ? ' Уровень «Начальный» — упрощённый вариант.' : ''),
        variant: variant,
      ));
    }
  }
  final diff = durationMin - blocks.fold<int>(0, (a, b) => a + b.durationMin);
  if (blocks.isNotEmpty && diff != 0) {
    final i = blocks.indexWhere((b) => b.phase == 'main');
    final idx = i < 0 ? blocks.length - 1 : i;
    blocks[idx] = blocks[idx].copyWith(durationMin: blocks[idx].durationMin + diff);
  }
  return [
    for (final b in blocks)
      b.copyWith(dosage: dosageFor(b.durationMin, b.phase, b.phase == 'main' || b.phase == 'game' ? intensity : 'low')),
  ];
}

/// Похожее упражнение для замены блока: та же категория, подходит команде, ещё нет в плане.
Drill? similarDrill({
  required List<Drill> library,
  required TrainingBlock block,
  required Team team,
  required int players,
  required Set<String> inPlan,
  int skip = 0,
}) {
  final cat = block.drillSnapshot?.category;
  final pool = library
      .where((d) => d.category == cat && d.id != block.drillId && !inPlan.contains(d.id) && drillFitsTeam(d, team, players: players))
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));
  if (pool.isEmpty) return null;
  return pool[skip % pool.length];
}

/// Фаза плана по категории упражнения.
String phaseForCategory(String category) => switch (category) {
      'warmup' => 'warmup',
      'cooldown' => 'cooldown',
      'game' => 'game',
      _ => 'main',
    };

/// Блок плана из упражнения каталога, добавленного тренером вручную.
TrainingBlock blockFromDrill(Drill d, {required String id, String intensity = 'medium', String why = 'Добавлено тренером из каталога.'}) {
  final phase = phaseForCategory(d.category);
  return TrainingBlock(
    id: id,
    phase: phase,
    title: d.title,
    durationMin: d.durationMin,
    drillId: d.id,
    drill: drillSnapshot(d),
    why: why,
    dosage: dosageFor(d.durationMin, phase, phase == 'main' || phase == 'game' ? intensity : 'low'),
  );
}
