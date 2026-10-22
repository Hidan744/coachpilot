// Контекст плана: история команды, площадка, готовность плана к проведению и пересборка по новым условиям.
// Всё считается только из данных команды; у каждого вывода есть основание.

import 'dart:math' as math;

import '../data/models.dart';
import '../ui/screens/library/library_screens.dart' show drillFitsTeam;

// ---------------------------------------------------------------- площадка

const fieldLabels = {'full': 'Всё поле', 'half': 'Половина поля', 'third': 'Треть поля', 'box': 'Мини-поле / зал'};

/// Сколько места нужно упражнению: 0 — мини-площадка или зал, 1 — треть поля или штрафная, 2 — половина поля и больше.
int areaNeed(Drill d) {
  final s = d.fieldSize.toLowerCase();
  if (RegExp('половин|две трети|всё поле|все поле|полное поле').hasMatch(s)) return 2;
  if (RegExp('штрафн|треть').hasMatch(s)) return 1;
  final rect = RegExp(r'(\d+)\s*[×xх]\s*(\d+)').firstMatch(s);
  if (rect != null) {
    final area = int.parse(rect.group(1)!) * int.parse(rect.group(2)!);
    return area <= 700 ? 0 : (area <= 1300 ? 1 : 2);
  }
  final corridor = RegExp(r'коридор\s*(\d+)').firstMatch(s);
  if (corridor != null) return int.parse(corridor.group(1)!) <= 20 ? 0 : 1;
  if (s.contains('ворота')) return 1;
  return 0;
}

/// Какая площадка доступна: [field] из конструктора (full, half, third, box).
int areaAvailable(String? field) => switch (field) {
      'box' => 0,
      'third' => 1,
      _ => 2,
    };

bool drillFitsArea(Drill d, String? field) => areaNeed(d) <= areaAvailable(field);

// ---------------------------------------------------------------- история команды

/// Что из истории команды учтено при подборе, и на чём это основано.
class HistoryNote {
  const HistoryNote(this.text, this.basis);

  final String text, basis;
}

/// Приоритет команды: что тренировать и откуда это взялось.
class TeamPriority {
  const TeamPriority(this.text, this.source);

  final String text, source;
}

class TeamHistory {
  TeamHistory({
    required this.recentDrillIds,
    required this.suggestedIntensity,
    required this.intensityReason,
    required this.priorities,
    required this.absentLately,
    required this.injured,
    required this.notes,
    required this.doneSessions,
  });

  /// Упражнения последних занятий — по возможности не повторять.
  final Set<String> recentDrillIds;

  /// Предложенная интенсивность (low, medium, high) или null, если данных мало.
  final String? suggestedIntensity;
  final String intensityReason;
  final List<TeamPriority> priorities;

  /// Игроки, пропустившие 2 из 3 последних отмеченных занятий.
  final List<Player> absentLately;

  /// Отмечены травмированными на последнем занятии.
  final Set<String> injured;
  final List<HistoryNote> notes;
  final int doneSessions;

  bool get isEmpty => doneSessions == 0 && priorities.isEmpty;
}

TeamHistory teamHistory({
  required Team team,
  required List<TrainingSession> sessions,
  required Map<String, SessionReport> reports,
  required List<Attendance> attendance,
  required List<Player> players,
  List<DevelopmentPlan> plans = const [],
  List<Match> matches = const [],
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  DateTime when(TrainingSession s) => s.finishedAt ?? s.scheduledAt ?? DateTime(2000);
  final done = [for (final s in sessions) if (s.teamId == team.id && s.status == 'done') s]
    ..sort((a, b) => when(b).compareTo(when(a)));
  final notes = <HistoryNote>[];

  // Не повторять упражнения двух последних занятий и всей прошлой недели.
  final recent = <String>{
    for (var i = 0; i < done.length; i++)
      if (i < 2 || at.difference(when(done[i])).inDays <= 7)
        for (final b in done[i].blocks) ?b.drillId,
  };
  if (recent.isNotEmpty) {
    notes.add(HistoryNote('Упражнения последних занятий (${recent.length}) по возможности не повторяются',
        'проведённые тренировки за 7 дней'));
  }

  // Интенсивность — по оценкам RPE последних занятий и ближайшему матчу.
  final rpes = [for (final s in done.take(3)) ?reports[s.id]?.rpe];
  String? intensity;
  var reason = '';
  final nextMatch = ([
    for (final m in matches)
      if (m.teamId == team.id && m.startsAt.isAfter(at) && m.status != 'cancelled') m
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
      .firstOrNull;
  final daysToMatch = nextMatch == null ? null : nextMatch.startsAt.difference(at).inHours / 24;
  if (daysToMatch != null && daysToMatch <= 1.5) {
    intensity = 'low';
    reason = 'Матч с «${nextMatch!.opponent}» ${daysToMatch < 1 ? 'сегодня или завтра' : 'через день'}: подводка — короткая и лёгкая';
  } else if (rpes.length >= 2) {
    final avg = rpes.take(2).reduce((a, b) => a + b) / 2;
    if (rpes.first >= 8 || avg >= 7.5) {
      intensity = 'low';
      reason = 'Последние занятия тяжёлые: RPE ${rpes.take(2).join(' и ')} — снизьте интенсивность';
    } else if (avg <= 3.5) {
      intensity = 'high';
      reason = 'Последние занятия лёгкие: RPE ${rpes.take(2).join(' и ')} — можно добавить темп';
    } else {
      intensity = 'medium';
      reason = 'Нагрузка последних занятий в норме: RPE ${rpes.take(2).join(' и ')}';
    }
  } else if (done.isNotEmpty) {
    reason = 'Мало оценок RPE: заполняйте нагрузку в отчёте — тогда интенсивность будет подсказана';
  }
  if (intensity != null) notes.add(HistoryNote(reason, daysToMatch != null && daysToMatch <= 1.5 ? 'календарь матчей' : 'оценки RPE из отчётов'));

  // Приоритеты: решение тренера в последнем отчёте, повторяющиеся проблемы, цели сезона, недели программ игроков.
  final priorities = <TeamPriority>[];
  final last = done.firstOrNull;
  final lastReport = last == null ? null : reports[last.id];
  if (lastReport != null && lastReport.nextTime.isNotEmpty) {
    priorities.add(TeamPriority(lastReport.nextTime, 'отчёт «${last!.title}»: что изменить'));
  }
  if (lastReport != null && lastReport.toImprove.isNotEmpty) {
    priorities.add(TeamPriority(lastReport.toImprove, 'отчёт «${last!.title}»: что улучшить'));
  }
  for (final g in team.seasonGoals.where((g) => !g.done).take(2)) {
    priorities.add(TeamPriority(g.text, 'цель сезона'));
  }
  final ids = {for (final p in players) p.id};
  final weekly = <String, int>{};
  for (final p in plans) {
    if (!ids.contains(p.playerId) || p.weeks.isEmpty || p.startsOn == null) continue;
    final n = at.difference(p.startsOn!).inDays ~/ 7 + 1;
    final w = p.weeks.where((w) => w.n == n).firstOrNull;
    if (w != null && w.priority.isNotEmpty) weekly[w.priority] = (weekly[w.priority] ?? 0) + 1;
  }
  for (final e in (weekly.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(2)) {
    priorities.add(TeamPriority(e.key, 'программы развития: у ${e.value} игр. на этой неделе'));
  }

  // Посещаемость: кто пропускает и кто травмирован.
  final byPlayer = <String, List<(DateTime, String)>>{};
  final sessionDate = {for (final s in done) s.id: when(s)};
  for (final a in attendance) {
    final d = sessionDate[a.sessionId];
    if (d != null) (byPlayer[a.playerId] ??= []).add((d, a.status));
  }
  final absent = <Player>[];
  final injured = <String>{};
  for (final p in players.where((p) => p.active)) {
    final marks = (byPlayer[p.id] ?? [])..sort((a, b) => b.$1.compareTo(a.$1));
    final last3 = marks.take(3).toList();
    if (last3.length >= 2 && last3.where((m) => m.$2 == 'absent').length >= 2) absent.add(p);
    if (last3.isNotEmpty && last3.first.$2 == 'injured') injured.add(p.id);
  }
  if (injured.isNotEmpty) {
    notes.add(HistoryNote('Травмированные на прошлом занятии не включены в состав: ${injured.length}', 'посещаемость'));
  }
  return TeamHistory(
    recentDrillIds: recent,
    suggestedIntensity: intensity,
    intensityReason: reason,
    priorities: priorities,
    absentLately: absent,
    injured: injured,
    notes: notes,
    doneSessions: done.length,
  );
}

// ---------------------------------------------------------------- план, готовый к проведению

Drill? _drill(TrainingBlock b) => b.drillSnapshot;

/// Что подготовить к следующему блоку, пока игроки отдыхают.
String transitionNote(TrainingBlock from, TrainingBlock next) {
  final d = _drill(next);
  final prep = <String>[
    if (d != null && d.fieldSize.isNotEmpty) 'площадка ${d.fieldSize}',
    if (d != null && d.equipment.any((e) => e != 'balls'))
      d.equipment.where((e) => e != 'balls').map((e) => (Equipment.all[e] ?? e).toLowerCase()).join(', '),
  ];
  final rest = from.phase == 'main' || from.phase == 'game' ? 'Вода 1–2 мин. ' : '';
  return '$restДальше «${next.title}»${prep.isEmpty ? '' : ': подготовьте ${prep.join('; ')}'}.';
}

/// Замена, если на упражнение не хватает игроков: та же категория, нужно меньше людей.
Drill? fewerPlayersAlternative(TrainingBlock b, List<Drill> library, Team team, {Set<String> inPlan = const {}}) {
  final d = _drill(b);
  if (d == null || d.playersMin <= 4) return null;
  final pool = library
      .where((x) =>
          x.category == d.category &&
          x.id != d.id &&
          !inPlan.contains(x.id) &&
          x.playersMin < d.playersMin &&
          drillFitsTeam(x, team, players: x.playersMin))
      .toList()
    ..sort((a, b) => b.playersMin.compareTo(a.playersMin));
  return pool.firstOrNull;
}

/// Подсказка «если игроков меньше» для блока.
String fewerPlayersNote(TrainingBlock b, List<Drill> library, Team team, {Set<String> inPlan = const {}}) {
  final d = _drill(b);
  if (d == null) return '';
  if (d.playersMin <= 4) return 'Подходит и малой группе — от ${d.playersMin} игр.';
  final alt = fewerPlayersAlternative(b, library, team, inPlan: inPlan);
  if (alt != null) return 'Если придёт меньше ${d.playersMin}: замените на «${alt.title}» (от ${alt.playersMin} игр.)';
  if (d.easier.isNotEmpty) return 'Если игроков меньше ${d.playersMin}: ${d.easier.first}';
  return 'Нужно от ${d.playersMin} игроков — при нехватке уменьшите площадку и играйте без нейтральных';
}

/// План Б (плохая погода, мини-площадка, нет ворот): замены для блоков, которым нужно много места или большие ворота.
Map<String, Drill> planB(List<TrainingBlock> blocks, List<Drill> library, Team team, int players) {
  final inPlan = {for (final b in blocks) ?b.drillId};
  final used = <String>{};
  final out = <String, Drill>{};
  for (final b in blocks) {
    final d = _drill(b);
    if (d == null || (areaNeed(d) == 0 && !d.equipment.contains('goals'))) continue;
    final pool = library
        .where((x) =>
            !inPlan.contains(x.id) &&
            !used.contains(x.id) &&
            areaNeed(x) == 0 &&
            !x.equipment.contains('goals') &&
            _samePhase(x.category, d.category) &&
            drillFitsTeam(x, team, players: players))
        .toList()
      ..sort((a, c) => (a.category == d.category ? 0 : 1).compareTo(c.category == d.category ? 0 : 1));
    if (pool.isEmpty) continue;
    used.add(pool.first.id);
    out[b.id] = pool.first;
  }
  return out;
}

bool _samePhase(String a, String b) {
  String group(String c) => switch (c) {
        'warmup' => 'warmup',
        'cooldown' => 'cooldown',
        'game' || 'possession' => 'game',
        _ => 'main',
      };
  return group(a) == group(b) || (group(b) == 'main' && group(a) == 'game');
}

// ---------------------------------------------------------------- пересборка затронутых блоков

/// Новые условия занятия: число игроков, длительность, инвентарь, площадка.
class PlanConditions {
  const PlanConditions({required this.players, required this.durationMin, required this.equipment, this.field});

  final int players, durationMin;
  final List<String> equipment;
  final String? field;
}

/// Результат пересборки: новые блоки и что изменилось.
class AdaptResult {
  const AdaptResult(this.blocks, this.changes, this.warnings);

  final List<TrainingBlock> blocks;
  final List<String> changes, warnings;
}

String? _misfit(Drill d, Team team, PlanConditions c) {
  final age = AgeGroups.age(team.ageGroup);
  if (age < d.ageMin || age > d.ageMax) return 'не подходит возрасту';
  if (c.players < d.playersMin) return 'нужно от ${d.playersMin} игроков';
  final missing = d.equipment.where((e) => e != 'balls' && e != 'cones' && !c.equipment.contains(e)).toList();
  if (missing.isNotEmpty) return 'нет инвентаря: ${missing.map((e) => (Equipment.all[e] ?? e).toLowerCase()).join(', ')}';
  if (!drillFitsArea(d, c.field)) return 'не хватает площадки (${d.fieldSize})';
  return null;
}

/// Длительности блоков под новую длительность занятия: пропорционально, сумма ровно [total].
List<int> rescale(List<int> minutes, int total) {
  final sum = minutes.fold<int>(0, (a, b) => a + b);
  if (sum == 0 || minutes.isEmpty) return minutes;
  final out = [for (final m in minutes) math.max(3, (m * total / sum).round())];
  var diff = total - out.fold<int>(0, (a, b) => a + b);
  // Остаток — в самые длинные блоки.
  final order = List.generate(out.length, (i) => i)..sort((a, b) => out[b].compareTo(out[a]));
  var k = 0;
  while (diff != 0 && k < 1000) {
    final i = order[k % order.length];
    if (diff > 0) {
      out[i]++;
      diff--;
    } else if (out[i] > 3) {
      out[i]--;
      diff++;
    }
    k++;
  }
  return out;
}

/// Пересобрать только то, что затронули новые условия; остальные блоки и правки тренера остаются.
AdaptResult adaptPlan({
  required List<TrainingBlock> blocks,
  required List<Drill> library,
  required Team team,
  required PlanConditions conditions,
  required int oldDurationMin,
  String intensity = 'medium',
  String Function(int minutes, String phase, String intensity)? dosage,
}) {
  final changes = <String>[], warnings = <String>[];
  final inPlan = {for (final b in blocks) ?b.drillId};
  final next = <TrainingBlock>[];
  for (final b in blocks) {
    final d = _drill(b);
    final why = d == null ? null : _misfit(d, team, conditions);
    if (why == null) {
      next.add(b);
      continue;
    }
    final pool = library
        .where((x) => !inPlan.contains(x.id) && _samePhase(x.category, d!.category) && _misfit(x, team, conditions) == null)
        .toList()
      ..sort((a, c) => (a.category == d!.category ? 0 : 1).compareTo(c.category == d.category ? 0 : 1));
    final alt = pool.firstOrNull;
    if (alt == null) {
      warnings.add('«${b.title}»: $why — подходящей замены в каталоге нет, оставлено как есть');
      next.add(b);
      continue;
    }
    inPlan.add(alt.id);
    changes.add('«${b.title}» → «${alt.title}»: $why');
    next.add(b.copyWith(
      title: alt.title,
      drillId: alt.id,
      drill: alt.toJson(),
      variant: 'base',
      why: 'Замена по новым условиям: у «${b.title}» $why. ${b.why}',
    ));
  }
  var out = next;
  if (conditions.durationMin != oldDurationMin) {
    final mins = rescale([for (final b in next) b.durationMin], conditions.durationMin);
    out = [
      for (var i = 0; i < next.length; i++)
        next[i].durationMin == mins[i]
            ? next[i]
            : next[i].copyWith(
                durationMin: mins[i],
                dosage: dosage?.call(mins[i], next[i].phase, next[i].phase == 'main' || next[i].phase == 'game' ? intensity : 'low'),
              ),
    ];
    changes.add('Длительность $oldDurationMin → ${conditions.durationMin} мин: блоки пересчитаны пропорционально');
  }
  return AdaptResult(out, changes, warnings);
}
