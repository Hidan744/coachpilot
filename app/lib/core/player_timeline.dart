// Единая история игрока: тренировки, матчи, тесты, оценки, цели и изменения профиля в одной ленте.
// У каждого события указан источник — измерение, оценка тренера или автоматический учёт; они не смешиваются.

import '../data/models.dart';
import 'performance.dart';

class TimelineEvent {
  const TimelineEvent(this.at, this.kind, this.title, {this.detail = '', required this.source, this.route});

  final DateTime at;

  /// training, match, test, assessment, goal, profile.
  final String kind;
  final String title, detail;

  /// Откуда данные: «посещаемость», «оценка тренера (субъективно)», «тест ОФП (измерение)»…
  final String source;
  final String? route;
}

const timelineKinds = {
  'training': 'Тренировки',
  'match': 'Матчи',
  'test': 'Тесты',
  'assessment': 'Оценки',
  'goal': 'Цели',
  'profile': 'Профиль',
};

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString().replaceAll('.', ',');

List<TimelineEvent> playerTimeline({
  required Player player,
  required List<TrainingSession> sessions,
  required List<Attendance> attendance,
  required Map<String, SessionReport> reports,
  required List<Match> matches,
  required List<MatchStat> stats,
  required List<PhysicalTest> tests,
  required List<PlayerAssessment> assessments,
  required List<DevelopmentPlan> plans,
}) {
  final out = <TimelineEvent>[];
  final byId = {for (final s in sessions) s.id: s};

  // Тренировки: отметка посещаемости и заметка тренера по игроку.
  for (final a in attendance.where((a) => a.playerId == player.id)) {
    final s = byId[a.sessionId];
    if (s == null) continue;
    final note = reports[s.id]?.playerNotes[player.id];
    out.add(TimelineEvent(
      s.finishedAt ?? s.scheduledAt ?? DateTime(2000),
      'training',
      '${AttendanceStatus.labels[a.status] ?? a.status}: ${s.title}',
      detail: note == null ? '' : 'Заметка тренера: $note',
      source: note == null ? 'посещаемость' : 'посещаемость и наблюдение тренера',
      route: '/sessions/${s.id}/summary',
    ));
  }

  // Матчи: минуты и показатели из статистики.
  final matchById = {for (final m in matches) m.id: m};
  for (final st in stats.where((s) => s.playerId == player.id)) {
    final m = matchById[st.matchId];
    if (m == null) continue;
    final shown = [
      for (final e in st.stats.entries)
        if (e.value != 0 && statLabels.containsKey(e.key)) '${statLabels[e.key]}: ${_n(e.value)}',
    ].take(4);
    out.add(TimelineEvent(
      m.startsAt,
      'match',
      'Матч с ${m.opponent}${m.scoreFor == null ? '' : ' ${m.scoreFor}:${m.scoreAgainst}'} — ${st.minutes} мин',
      detail: [if (st.started) 'в старте', ...shown, if (st.rating != null) 'оценка ${_n(st.rating!)}'].join(' · '),
      source: 'статистика матча',
      route: '/calendar/match/${m.id}/stats',
    ));
  }

  // Тесты ОФП — измерения.
  final metric = {for (final m in physicalMetrics) m.key: m};
  for (final t in tests.where((t) => t.playerId == player.id)) {
    out.add(TimelineEvent(
      t.testedOn,
      'test',
      'Тест ОФП',
      detail: [
        for (final e in t.results.entries) '${metric[e.key]?.label ?? e.key}: ${_n(e.value)} ${metric[e.key]?.unit ?? ''}'.trim(),
      ].join(' · '),
      source: 'тест ОФП (измерение)',
      route: '/team/player/${player.id}?tab=1',
    ));
  }

  // Оценки тренера — субъективные, группой за день.
  final byDay = <DateTime, List<PlayerAssessment>>{};
  for (final a in assessments.where((a) => a.playerId == player.id)) {
    final d = DateTime(a.assessedAt.year, a.assessedAt.month, a.assessedAt.day);
    (byDay[d] ??= []).add(a);
  }
  for (final e in byDay.entries) {
    out.add(TimelineEvent(
      e.key,
      'assessment',
      'Оценки навыков',
      detail: e.value.map((a) => '${Skills.all[a.skill] ?? a.skill} ${a.score}/5').join(' · '),
      source: 'оценка тренера (субъективно)',
      route: '/team/player/${player.id}?tab=2',
    ));
  }

  // Цели: начало программы и контрольные замеры.
  for (final p in plans.where((p) => p.playerId == player.id)) {
    if (p.startsOn != null) {
      out.add(TimelineEvent(
        p.startsOn!,
        'goal',
        'Программа «${p.title}»',
        detail: [
          if (p.weeks.isNotEmpty) '${p.weeks.length} недель, выполнено ${p.weeks.where((w) => w.done).length}',
          if (p.keyGoal.isNotEmpty) p.keyGoal,
        ].join(' · '),
        source: 'цель тренера',
        route: '/team/player/${player.id}/plan/${p.id}',
      ));
    }
    for (final t in p.targets) {
      for (final c in t.checkpoints) {
        out.add(TimelineEvent(
          c.on,
          'goal',
          'Замер «${t.name}»: ${_n(c.value)} ${t.unit}'.trim(),
          detail: [if (t.target != null) 'цель ${_n(t.target!)} ${t.unit}'.trim(), if (c.note.isNotEmpty) c.note].join(' · '),
          source: 'контрольный замер',
          route: '/team/player/${player.id}/plan/${p.id}',
        ));
      }
    }
  }

  // Изменения профиля.
  for (final c in player.changes) {
    out.add(TimelineEvent(c.at, 'profile', 'Профиль изменён', detail: c.text, source: 'история изменений'));
  }

  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}
