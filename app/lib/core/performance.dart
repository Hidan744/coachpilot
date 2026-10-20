// Расчёты для профиля игрока и дашбордов: статистика матчей, тесты ОФП, оценки по категориям.

import 'dart:math' as math;

import '../data/models.dart';

// ---------------------------------------------------------------- статистика матчей

class StatKey {
  const StatKey(this.key, this.label, this.short, {this.keeper = false, this.basic = false});

  final String key, label, short;

  /// Только для вратарей.
  final bool keeper;

  /// Показывать сразу (остальное — в «Ещё»).
  final bool basic;
}

/// Основные показатели, на которые смотрят в профессиональном футболе.
const statKeys = [
  StatKey('goals', 'Голы', 'Г', basic: true),
  StatKey('assists', 'Голевые передачи', 'П', basic: true),
  StatKey('shots', 'Удары', 'Уд', basic: true),
  StatKey('shots_on', 'Удары в створ', 'УдС', basic: true),
  StatKey('passes', 'Передачи', 'Пер'),
  StatKey('passes_ok', 'Точные передачи', 'ТП'),
  StatKey('key_passes', 'Ключевые передачи', 'КП'),
  StatKey('dribbles', 'Удачные обводки', 'Обв'),
  StatKey('tackles', 'Отборы', 'Отб', basic: true),
  StatKey('interceptions', 'Перехваты', 'Пхв'),
  StatKey('duels_won', 'Выигранные единоборства', 'Ед'),
  StatKey('fouls', 'Фолы', 'Ф'),
  StatKey('yellow', 'Жёлтые карточки', 'ЖК', basic: true),
  StatKey('red', 'Красные карточки', 'КК', basic: true),
  StatKey('saves', 'Сейвы', 'Сейв', keeper: true, basic: true),
  StatKey('conceded', 'Пропущено', 'Проп', keeper: true, basic: true),
];

final statLabels = {for (final s in statKeys) s.key: s.label};

/// Итоги игрока за период.
class SeasonStats {
  SeasonStats(this.playerId, Iterable<MatchStat> rows) {
    for (final r in rows) {
      if (r.minutes <= 0) continue;
      games++;
      if (r.started) starts++;
      minutes += r.minutes;
      if (r.rating != null) ratings.add(r.rating!);
      for (final e in r.stats.entries) {
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
      if (r['conceded'] == 0 && r.minutes >= 60 && (r.stats.containsKey('saves') || r.stats.isEmpty)) cleanSheets++;
    }
  }

  final String playerId;
  int games = 0, starts = 0, minutes = 0, cleanSheets = 0;
  final totals = <String, double>{};
  final ratings = <double>[];

  double operator [](String key) => totals[key] ?? 0;

  int get goalContributions => (this['goals'] + this['assists']).round();

  double? get avgRating => ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length;

  /// Точность передач, %.
  double? get passAccuracy => this['passes'] == 0 ? null : this['passes_ok'] * 100 / this['passes'];

  /// Удары в створ, %.
  double? get shotAccuracy => this['shots'] == 0 ? null : this['shots_on'] * 100 / this['shots'];

  /// Показатель за 90 минут.
  double per90(String key) => minutes == 0 ? 0 : this[key] * 90 / minutes;
}

/// Итоги всех игроков по строкам статистики.
Map<String, SeasonStats> seasonStats(Iterable<MatchStat> rows) {
  final by = <String, List<MatchStat>>{};
  for (final r in rows) {
    by.putIfAbsent(r.playerId, () => []).add(r);
  }
  return {for (final e in by.entries) e.key: SeasonStats(e.key, e.value)};
}

// ---------------------------------------------------------------- ОФП

class PhysicalMetric {
  const PhysicalMetric(this.key, this.label, this.axis, this.unit, this.norms, {this.lowerBetter = false, this.hint = ''});

  final String key, label, axis, unit, hint;
  final bool lowerBetter;

  /// Ориентировочные нормы по возрасту: (до возраста включительно, отлично, слабо).
  final List<(int, double, double)> norms;

  (double, double) normsFor(int age) {
    for (final n in norms) {
      if (age <= n.$1) return (n.$2, n.$3);
    }
    return (norms.last.$2, norms.last.$3);
  }

  /// Балл 0–100: «слабо» → 0, «отлично» → 100.
  int score(double value, int age) {
    final (best, worst) = normsFor(age);
    final f = (value - worst) / (best - worst);
    return (f.clamp(0.0, 1.0) * 100).round();
  }

  /// Улучшение от a к b, % (с учётом направления: для бега меньше — лучше).
  double change(double a, double b) => a == 0 ? 0 : (lowerBetter ? (a - b) / a : (b - a) / a) * 100;
}

/// Батарея тестов ОФП футболиста. Оси радара: ускорение, скорость, ловкость, мощность, выносливость, мобильность.
const physicalMetrics = [
  PhysicalMetric('sprint_10m', 'Бег 10 м', 'Ускорение', 'с',
      [(11, 1.95, 2.35), (13, 1.85, 2.25), (15, 1.75, 2.10), (17, 1.70, 2.00), (99, 1.65, 1.95)],
      lowerBetter: true, hint: 'С места, лучшая из 2 попыток'),
  PhysicalMetric('sprint_30m', 'Бег 30 м', 'Скорость', 'с',
      [(11, 5.0, 6.2), (13, 4.7, 5.8), (15, 4.4, 5.3), (17, 4.2, 5.0), (99, 4.0, 4.7)],
      lowerBetter: true, hint: 'С места, лучшая из 2 попыток'),
  PhysicalMetric('shuttle_3x10', 'Челночный бег 3×10 м', 'Ловкость', 'с',
      [(11, 8.3, 9.6), (13, 7.9, 9.2), (15, 7.5, 8.7), (17, 7.2, 8.3), (99, 7.0, 8.0)],
      lowerBetter: true),
  PhysicalMetric('long_jump', 'Прыжок в длину с места', 'Мощность', 'см',
      [(11, 190, 140), (13, 210, 160), (15, 235, 180), (17, 250, 195), (99, 260, 205)]),
  PhysicalMetric('yoyo', 'Yo-Yo IR1', 'Выносливость', 'м',
      [(11, 1200, 400), (13, 1500, 520), (15, 1900, 680), (17, 2300, 840), (99, 2600, 1000)],
      hint: 'Пройденная дистанция'),
  PhysicalMetric('flexibility', 'Наклон вперёд', 'Мобильность', 'см', [(99, 15, -5)],
      hint: 'Сидя, от уровня стоп: + дальше стоп'),
];

/// Антропометрия: без баллов, только для профиля.
const anthropometry = {'height': ('Рост', 'см'), 'weight': ('Вес', 'кг')};

int playerAge(Player p, [DateTime? now]) =>
    p.birthYear == null ? 16 : (now ?? DateTime.now()).year - p.birthYear!;

/// Баллы теста по осям (только сданные тесты).
Map<String, int> physicalScores(PhysicalTest t, int age) => {
      for (final m in physicalMetrics)
        if (t.results[m.key] != null) m.key: m.score(t.results[m.key]!, age),
    };

/// Общий балл ОФП — среднее по сданным тестам.
int? physicalOverall(PhysicalTest t, int age) {
  final s = physicalScores(t, age).values;
  return s.isEmpty ? null : (s.reduce((a, b) => a + b) / s.length).round();
}

// ---------------------------------------------------------------- оценки тренера

/// Категории профиля из оценок навыков (шкала 1–5 → 0–100).
const skillCategories = {
  'Техника': ['technique', 'passing', 'dribbling', 'finishing'],
  'Тактика': ['positioning', 'decision'],
  'Физика': ['physical'],
  'Ментальная': ['attitude'],
};

/// Последняя оценка каждого навыка на дату [at] (включительно).
Map<String, int> skillsAt(Iterable<PlayerAssessment> all, DateTime at) {
  final out = <String, PlayerAssessment>{};
  for (final a in all) {
    if (a.assessedAt.isAfter(at)) continue;
    final prev = out[a.skill];
    if (prev == null || a.assessedAt.isAfter(prev.assessedAt)) out[a.skill] = a;
  }
  return {for (final e in out.entries) e.key: e.value.score};
}

/// Балл категории 0–100 по последним оценкам; null — оценок нет.
Map<String, int?> categoryScores(Map<String, int> skills) => {
      for (final e in skillCategories.entries)
        e.key: () {
          final v = [for (final s in e.value) if (skills[s] != null) skills[s]!];
          return v.isEmpty ? null : (v.reduce((a, b) => a + b) * 20 / v.length).round();
        }(),
    };

/// Общий балл игрока: среднее категорий и ОФП (что есть).
int? overallScore(Map<String, int?> categories, int? physical) {
  final v = [...categories.values.whereType<int>(), ?physical];
  return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
}

/// Сильные стороны и зоны роста по последним оценкам: лучшие и худшие навыки.
(List<String>, List<String>) strengthsAndGaps(Map<String, int> skills, {int n = 3}) {
  final sorted = skills.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final strong = [for (final e in sorted.take(n)) if (e.value >= 4) e.key];
  final weak = [for (final e in sorted.reversed.take(n)) if (e.value <= 3 && !strong.contains(e.key)) e.key];
  return (strong, weak);
}

// ---------------------------------------------------------------- посещаемость и нагрузка

DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Посещаемость по неделям: [weeks] последних недель → доля (0..1) или null, если занятий не было.
List<(DateTime, double?)> attendanceByWeek(
  Iterable<Attendance> marks,
  Map<String, TrainingSession> sessions, {
  String? playerId,
  int weeks = 12,
  DateTime? now,
}) {
  final start = weekStart(now ?? DateTime.now()).subtract(Duration(days: 7 * (weeks - 1)));
  final present = List.filled(weeks, 0), total = List.filled(weeks, 0);
  for (final a in marks) {
    if (playerId != null && a.playerId != playerId) continue;
    final s = sessions[a.sessionId];
    final at = s?.startedAt ?? s?.scheduledAt;
    if (at == null) continue;
    final w = weekStart(at).difference(start).inDays ~/ 7;
    if (w < 0 || w >= weeks) continue;
    total[w]++;
    if (a.status == 'present' || a.status == 'late') present[w]++;
  }
  return [
    for (var i = 0; i < weeks; i++) (start.add(Duration(days: 7 * i)), total[i] == 0 ? null : present[i] / total[i]),
  ];
}

/// Нагрузка занятия в условных единицах (sRPE): RPE × минуты.
int? sessionLoad(TrainingSession s, SessionReport? r) {
  if (r?.rpe == null) return null;
  final secs = s.actual.entries.where((e) => e.key != 'skipped').fold<num>(0, (a, e) => a + ((e.value as num?) ?? 0));
  final minutes = secs > 0 ? (secs / 60).round() : s.durationMin;
  return r!.rpe! * minutes;
}

/// Структура нагрузки: минуты по направлениям из блоков проведённых занятий.
Map<String, int> loadStructure(Iterable<TrainingSession> sessions) {
  const groups = {
    'Техника': ['technique', 'passing', 'dribbling', 'finishing', 'goalkeeping'],
    'Тактика': ['tactics', 'possession', 'transition', 'defending'],
    'ОФП': ['physical'],
    'Игровая': ['game'],
    'Разминка и восстановление': ['warmup', 'cooldown'],
  };
  final out = {for (final g in groups.keys) g: 0};
  for (final s in sessions) {
    for (final b in s.blocks) {
      final cat = b.drill?['category'] as String? ?? switch (b.phase) {
        'warmup' || 'cooldown' => 'warmup',
        'game' => 'game',
        _ => 'technique',
      };
      final g = groups.entries.where((e) => e.value.contains(cat)).firstOrNull?.key ?? 'Техника';
      out[g] = out[g]! + b.durationMin;
    }
  }
  return out;
}

// ---------------------------------------------------------------- сводка по игроку

/// Всё, что нужно профилю и отчёту о прогрессе: «было» (начало периода) и «стало» (сейчас).
class PlayerSnapshot {
  PlayerSnapshot({
    required this.player,
    required Iterable<PlayerAssessment> assessments,
    required Iterable<PhysicalTest> tests,
    required Iterable<Attendance> attendance,
    required Map<String, TrainingSession> sessions,
    required Iterable<MatchStat> stats,
    DateTime? now,
    this.periodDays = 90,
  }) {
    final at = now ?? DateTime.now();
    from = at.subtract(Duration(days: periodDays));
    final mine = assessments.where((a) => a.playerId == player.id).toList();
    skillsNow = skillsAt(mine, at);
    skillsBefore = skillsAt(mine, from);
    // «Было» — первые оценки в периоде, если до периода оценок не было.
    if (skillsBefore.isEmpty && mine.isNotEmpty) {
      final first = mine.map((a) => a.assessedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      skillsBefore = skillsAt(mine, first);
    }
    age = playerAge(player, at);
    final myTests = tests.where((t) => t.playerId == player.id).toList()..sort((a, b) => a.testedOn.compareTo(b.testedOn));
    this.tests = myTests;
    lastTest = myTests.lastOrNull;
    prevTest = myTests.length >= 2 ? myTests[myTests.length - 2] : null;
    // «Было» — последний тест до периода, иначе самый первый (если тестов больше одного).
    baseTest = myTests.where((t) => t.testedOn.isBefore(from)).lastOrNull ?? (myTests.length >= 2 ? myTests.first : null);
    physicalNow = lastTest == null ? null : physicalOverall(lastTest!, age);
    physicalBefore = baseTest == null || identical(baseTest, lastTest) ? null : physicalOverall(baseTest!, age);
    categoriesNow = categoryScores(skillsNow);
    categoriesBefore = categoryScores(skillsBefore);
    if (physicalNow != null) categoriesNow['Физика'] = physicalNow;
    if (physicalBefore != null) categoriesBefore['Физика'] = physicalBefore;
    overallNow = overallScore(categoriesNow, null);
    overallBefore = overallScore(categoriesBefore, null);
    var p = 0, t = 0;
    for (final a in attendance) {
      if (a.playerId != player.id || a.status == 'excused') continue;
      t++;
      if (a.status == 'present' || a.status == 'late') p++;
    }
    present = p;
    total = t;
    weeks = attendanceByWeek(attendance, sessions, playerId: player.id, now: at);
    season = SeasonStats(player.id, stats.where((s) => s.playerId == player.id));
  }

  final Player player;
  final int periodDays;
  late final DateTime from;
  late final int age;
  late final Map<String, int> skillsNow;
  late Map<String, int> skillsBefore;
  late final List<PhysicalTest> tests;
  late final PhysicalTest? lastTest, prevTest, baseTest;
  late final int? physicalNow, physicalBefore;
  late final Map<String, int?> categoriesNow, categoriesBefore;
  late final int? overallNow, overallBefore;
  late final int present, total;
  late final List<(DateTime, double?)> weeks;
  late final SeasonStats season;

  int? get attendancePct => total == 0 ? null : (present * 100 / total).round();

  /// Изменение общего балла за период, в пунктах.
  int? get overallDelta => overallNow == null || overallBefore == null ? null : overallNow! - overallBefore!;
}

String signed(num v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');

double mean(Iterable<num> v) => v.isEmpty ? 0 : v.fold<double>(0, (a, b) => a + b) / v.length;

double roundTo(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).round() / p;
}
