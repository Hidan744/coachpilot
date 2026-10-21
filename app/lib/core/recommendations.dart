// Рекомендации тренеру по данным: интенсивность тренировок команды и индивидуальное развитие игроков.
// Правила простые и объяснимые — каждая рекомендация говорит, из каких цифр она следует.

import '../data/models.dart';
import 'performance.dart';

/// Рекомендация: направление, заголовок, пояснение с цифрами.
class Advice {
  const Advice(this.kind, this.title, this.text, {this.area = '', this.playerId});

  /// up — повысить, down — снизить, keep — держать, info — к сведению, work — над чем работать.
  final String kind;
  final String title, text;

  /// Направление развития игрока: ОФП, Техника, Тактика, Посещаемость.
  final String area;
  final String? playerId;
}

/// Интенсивность команды: нагрузка последней недели против средней за 4 недели до неё (acute:chronic),
/// оценка тяжести последних занятий (RPE) и ближайший матч.
List<Advice> teamAdvice({
  required Team team,
  required List<TrainingSession> sessions,
  required Map<String, SessionReport> reports,
  required List<Match> matches,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final adult = team.ageGroup == 'adult';
  final done = [
    for (final s in sessions)
      if (s.teamId == team.id && s.status == 'done' && (s.startedAt ?? s.scheduledAt) != null) s,
  ]..sort((a, b) => (a.startedAt ?? a.scheduledAt)!.compareTo((b.startedAt ?? b.scheduledAt)!));
  int loadBetween(DateTime from, DateTime to) => done
      .where((s) => !(s.startedAt ?? s.scheduledAt)!.isBefore(from) && (s.startedAt ?? s.scheduledAt)!.isBefore(to))
      .fold(0, (a, s) => a + (sessionLoad(s, reports[s.id]) ?? 0));
  final weekAgo = at.subtract(const Duration(days: 7));
  final acute = loadBetween(weekAgo, at);
  final chronic = loadBetween(weekAgo.subtract(const Duration(days: 28)), weekAgo) / 4;
  final out = <Advice>[];

  if (chronic > 0 && acute > 0) {
    final ratio = acute / chronic;
    final pct = ((ratio - 1) * 100).round();
    if (ratio > 1.3) {
      out.add(Advice('down', 'Снизить интенсивность',
          'Нагрузка за неделю ${acute.round()} у.е. — на $pct% выше средней за месяц (${chronic.round()}). '
          'Риск перегрузки и травм: следующую тренировку — средней интенсивности, меньше рывковых блоков.'));
    } else if (ratio < 0.8) {
      out.add(Advice('up', 'Можно повысить интенсивность',
          'Нагрузка за неделю ${acute.round()} у.е. — на ${-pct}% ниже средней за месяц (${chronic.round()}). '
          'Добавьте блок высокой интенсивности: игры в малых составах или интервальный бег.'));
    } else {
      out.add(Advice('keep', 'Нагрузка в норме',
          'За неделю ${acute.round()} у.е., средняя за месяц ${chronic.round()} (${signed(pct)}%). Держите текущий уровень.'));
    }
  }

  // Тяжесть последних трёх занятий по оценке игроков (RPE 1–10).
  final rpes = [for (final s in done.reversed.take(3)) ?reports[s.id]?.rpe];
  if (rpes.length >= 2) {
    final avg = mean(rpes);
    if (avg >= 8) {
      out.add(Advice('down', 'Игроки устали',
          'Средняя тяжесть последних занятий — ${avg.toStringAsFixed(1)} из 10. Нужен восстановительный день: '
          'низкая интенсивность, техника, растяжка.'));
    } else if (avg <= 4) {
      out.add(Advice('up', 'Тренировки даются легко',
          'Средняя тяжесть последних занятий — ${avg.toStringAsFixed(1)} из 10. Можно добавить темп и соревновательные задания.'));
    }
  }

  // Ближайший матч: подводка.
  final next = matches.where((m) => m.teamId == team.id && m.startsAt.isAfter(at)).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  if (next.isNotEmpty) {
    final days = next.first.startsAt.difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days <= 2) {
      out.add(Advice('down', 'Подводка к матчу',
          'Матч с ${next.first.opponent} через ${days <= 1 ? 'день' : '$days дня'}: короткая тренировка низкой интенсивности, '
          'стандарты и тактика на соперника.'));
    }
  }

  if (!adult) {
    out.add(Advice('info', 'Возраст ${team.ageGroup}',
        'Не больше двух высокоинтенсивных тренировок в неделю, работа с отягощениями — только с весом своего тела; '
        'в период быстрого роста следите за коленями и спиной.'));
  }
  return out;
}

/// Что развивать в ОФП по слабому тесту: упражнения для взрослых и для детей.
const _physicalWork = {
  'sprint_10m': ('Старты 5–10 м из разных положений, 2 раза в неделю по 6–8 повторов', 'Эстафеты и игры с рывками, старты по сигналу'),
  'sprint_30m': ('Ускорения 20–30 м, 6 повторов с полным отдыхом, 2 раза в неделю', 'Догонялки и ускорения 20 м в игровой форме'),
  'shuttle_3x10': ('Челночный бег и смены направления, координационная лестница', 'Координационная лестница, игры со сменой направления'),
  'long_jump': ('Прыжки, плиометрика и силовые упражнения на ноги 2 раза в неделю', 'Прыжковые игры, прыжки через низкие барьеры, без отягощений'),
  'yoyo': ('Интервальный бег 4×4 мин или игры 4×4 на большой площади', 'Игры в малых составах подольше, без монотонного бега'),
  'flexibility': ('Растяжка 10 мин после каждой тренировки', 'Растяжка и упражнения на гибкость в конце занятия'),
};

/// Индивидуальные рекомендации игроку: ОФП, техника и тактика, посещаемость.
List<Advice> playerAdvice(PlayerSnapshot s, {required bool adult, Iterable<SeasonStats> team = const []}) {
  final out = <Advice>[];

  // ОФП: самый слабый тест последнего тестирования.
  final test = s.lastTest;
  if (test != null) {
    final scored = [
      for (final m in physicalMetrics)
        if (test.results[m.key] != null) (m, m.score(test.results[m.key]!, s.age)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (scored.isNotEmpty && scored.first.$2 < 60) {
      final (m, score) = scored.first;
      final work = _physicalWork[m.key];
      out.add(Advice('work', 'ОФП: ${m.axis.toLowerCase()}',
          '${m.label} — $score из 100 по нормам возраста. ${work == null ? '' : (adult ? work.$1 : work.$2)}.',
          area: 'ОФП', playerId: s.player.id));
    }
  }

  // Игра: самое слабое направление игрового профиля относительно команды.
  if (s.season.minutes >= 90 && s.player.position != 'GK') {
    final profile = gameProfile(s.season, team);
    final weak = [for (final a in gameAxes) if ((profile[a.label] ?? 100) <= 35) (a, profile[a.label]!)]
      ..sort((a, b) => a.$2.compareTo(b.$2));
    if (weak.isNotEmpty) {
      final (axis, v) = weak.first;
      final tactical = const {'Оборона', 'Созидание', 'Надёжность'}.contains(axis.label);
      out.add(Advice('work', '${tactical ? 'Тактика' : 'Техника'}: ${axis.label.toLowerCase()}',
          '${axis.weak}. В команде — $v из 100. '
          '${tactical ? 'Разбор эпизодов по видео и игры с ограничениями на 2–3 касания.' : 'Индивидуальные упражнения 15 мин до или после тренировки.'}',
          area: tactical ? 'Тактика' : 'Техника', playerId: s.player.id));
    }
  }

  // Навыки по оценкам тренера: самая низкая категория.
  final cats = [for (final e in s.categoriesNow.entries) if (e.value != null && e.value! < 50) (e.key, e.value!)]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  if (cats.isNotEmpty && !out.any((a) => a.area == cats.first.$1)) {
    out.add(Advice('work', '${cats.first.$1}: оценка ${cats.first.$2}',
        'Поставьте это направление ключевой целью программы развития на 4–6 недель.',
        area: cats.first.$1, playerId: s.player.id));
  }

  final pct = s.attendancePct;
  if (pct != null && pct < 75) {
    out.add(Advice('info', 'Посещаемость $pct%',
        adult ? 'Поговорите с игроком: пропуски тормозят прогресс.' : 'Свяжитесь с родителями: пропуски тормозят прогресс.',
        area: 'Посещаемость', playerId: s.player.id));
  }
  return out;
}
