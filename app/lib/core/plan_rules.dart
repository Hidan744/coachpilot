// План по правилам из локальной библиотеки — работает без сети и без AI.
// Логика повторяет backend/app/ai/rules.py.

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

/// Собрать блоки плана из подходящих упражнений библиотеки.
List<TrainingBlock> planByRules({
  required List<Drill> library,
  required Team team,
  required int players,
  required int durationMin,
  required String goal,
  List<String> equipment = const [],
  List<String> focus = const [],
  Set<String> recentDrillIds = const {},
}) {
  final t = Team(
    id: team.id,
    name: team.name,
    ageGroup: team.ageGroup,
    level: team.level,
    defaultPlayers: players,
    equipment: equipment.isEmpty ? team.equipment : equipment,
  );
  final fitting = library.where((d) => drillFitsTeam(d, t, players: players)).toList();
  final cats = mainCategories(goal, focus);
  final used = <String>{};

  Drill? pick(List<String> allowed) {
    final pool = fitting.where((d) => allowed.contains(d.category) && !used.contains(d.id)).toList()
      ..sort((a, b) {
        final r = (recentDrillIds.contains(a.id) ? 1 : 0).compareTo(recentDrillIds.contains(b.id) ? 1 : 0);
        if (r != 0) return r;
        final c = allowed.indexOf(a.category).compareTo(allowed.indexOf(b.category));
        if (c != 0) return c;
        return '$goal${a.id}'.hashCode.compareTo('$goal${b.id}'.hashCode);
      });
    if (pool.isEmpty) return null;
    used.add(pool.first.id);
    return pool.first;
  }

  final durations = splitDurations(durationMin);
  final phaseCats = {
    'warmup': ['warmup'],
    'main': cats,
    'game': ['game', 'possession'],
    'cooldown': ['cooldown'],
  };
  final blocks = <TrainingBlock>[];
  var n = 0;
  for (final phase in ['warmup', 'main', 'game', 'cooldown']) {
    for (final minutes in durations[phase]!) {
      final d = pick(phaseCats[phase]!) ?? (phase == 'main' ? pick(_defaultMain) : null);
      if (d == null) continue;
      blocks.add(TrainingBlock(
        id: 'b${++n}',
        phase: phase,
        title: d.title,
        durationMin: minutes,
        drillId: d.id,
        drill: drillSnapshot(d),
      ));
    }
  }
  final diff = durationMin - blocks.fold<int>(0, (a, b) => a + b.durationMin);
  if (blocks.isNotEmpty && diff != 0) {
    final i = blocks.indexWhere((b) => b.phase == 'main');
    final idx = i < 0 ? blocks.length - 1 : i;
    blocks[idx] = blocks[idx].copyWith(durationMin: blocks[idx].durationMin + diff);
  }
  return blocks;
}
