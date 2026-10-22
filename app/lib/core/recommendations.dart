// Рекомендации тренеру по данным: интенсивность тренировок команды и индивидуальное развитие игроков.
// Правила простые и объяснимые — каждая рекомендация говорит, из каких цифр она следует.

import '../data/models.dart';
import 'performance.dart';
import 'plan_rules.dart' show namedCategories;
import 'session_summary.dart';

/// Рекомендация: направление, заголовок, пояснение с цифрами.
class Advice {
  const Advice(
    this.kind,
    this.title,
    this.text, {
    this.area = '',
    this.playerId,
    this.basis = '',
    this.next = '',
    this.route,
    this.expected = '',
    this.confidence = 'medium',
    this.limits = '',
    this.key = '',
  });

  /// up — повысить, down — снизить, keep — держать, info — к сведению, work — над чем работать.
  final String kind;
  final String title, text;

  /// Направление развития игрока: ОФП, Техника, Тактика, Посещаемость.
  final String area;
  final String? playerId;

  /// На каких данных основан вывод (факты, а не предположения).
  final String basis;

  /// Следующий шаг тренера и куда для него перейти в приложении.
  final String next;
  final String? route;

  /// Какой результат ожидается, если тренер последует совету.
  final String expected;

  /// Насколько можно доверять выводу: high, medium, low — и почему (ограничения данных).
  final String confidence;
  final String limits;

  /// Постоянный ключ рекомендации — для решения тренера (принять, отклонить, изменить).
  final String key;

  Advice withKey(String k) => Advice(kind, title, text,
      area: area, playerId: playerId, basis: basis, next: next, route: route,
      expected: expected, confidence: confidence, limits: limits, key: k);
}

const confidenceLabels = {'high': 'Высокая', 'medium': 'Средняя', 'low': 'Низкая'};

/// Ключ рекомендации: тип и заголовок без чисел + неделя — решение действует, пока ситуация та же.
String adviceKey(Advice a, DateTime at) {
  final monday = DateTime(at.year, at.month, at.day).subtract(Duration(days: at.weekday - 1));
  final week = '${monday.year}-${monday.month}-${monday.day}';
  final title = a.title.replaceAll(RegExp(r'[\d%.,]+'), '#');
  final k = '${a.kind}|${a.playerId ?? ''}|$title|$week';
  return k.length <= 200 ? k : k.substring(0, 200);
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
          'Риск перегрузки и травм: следующую тренировку — средней интенсивности, меньше рывковых блоков.',
          basis: 'Нагрузка = RPE × минуты из отчётов: последние 7 дней против средней за 4 недели до них',
          next: 'Соберите следующую тренировку со средней интенсивностью',
          route: '/sessions/new?intensity=medium',
          expected: 'Нагрузка недели вернётся к уровню ±30% от средней за месяц',
          limits: 'RPE — субъективная оценка; вывод о нагрузке, а не о здоровье игроков'));
    } else if (ratio < 0.8) {
      out.add(Advice('up', 'Можно повысить интенсивность',
          'Нагрузка за неделю ${acute.round()} у.е. — на ${-pct}% ниже средней за месяц (${chronic.round()}). '
          'Добавьте блок высокой интенсивности: игры в малых составах или интервальный бег.',
          basis: 'Нагрузка = RPE × минуты из отчётов: последние 7 дней против средней за 4 недели до них',
          next: 'Соберите тренировку с высокой интенсивностью основной части',
          route: '/sessions/new?intensity=high',
          expected: 'Нагрузка недели вернётся к уровню средней за месяц',
          limits: 'Если были пропуски из-за погоды или каникул, снижение нагрузки ожидаемо'));
    } else {
      out.add(Advice('keep', 'Нагрузка в норме',
          'За неделю ${acute.round()} у.е., средняя за месяц ${chronic.round()} (${signed(pct)}%). Держите текущий уровень.',
          basis: 'Нагрузка = RPE × минуты из отчётов за 5 недель',
          next: 'Планируйте следующую неделю с тем же объёмом и после каждого занятия записывайте RPE',
          expected: 'Нагрузка остаётся в пределах ±30% от средней',
          confidence: 'high'));
    }
  }

  // Тяжесть последних трёх занятий по оценке игроков (RPE 1–10).
  final rpes = [for (final s in done.reversed.take(3)) ?reports[s.id]?.rpe];
  if (rpes.length >= 2) {
    final avg = mean(rpes);
    if (avg >= 8) {
      out.add(Advice('down', 'Игроки устали',
          'Средняя тяжесть последних занятий — ${avg.toStringAsFixed(1)} из 10. Нужен восстановительный день: '
          'низкая интенсивность, техника, растяжка.',
          basis: 'RPE в отчётах последних ${rpes.length} занятий',
          next: 'Соберите восстановительную тренировку низкой интенсивности',
          route: '/sessions/new?intensity=low',
          expected: 'RPE следующего занятия — 5–6 из 10',
          limits: 'RPE — ощущения команды, не медицинский показатель; при жалобах игрока — к врачу'));
    } else if (avg <= 4) {
      out.add(Advice('up', 'Тренировки даются легко',
          'Средняя тяжесть последних занятий — ${avg.toStringAsFixed(1)} из 10. Можно добавить темп и соревновательные задания.',
          basis: 'RPE в отчётах последних ${rpes.length} занятий',
          next: 'Соберите тренировку с высокой интенсивностью',
          route: '/sessions/new?intensity=high',
          expected: 'RPE следующих занятий — 6–7 из 10',
          limits: 'Оценка по ${rpes.length} занятиям — мало данных'));
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
          'стандарты и тактика на соперника.',
          basis: 'Календарь матчей',
          next: 'Соберите короткую тренировку: стандарты и тактика',
          route: '/sessions/new?intensity=low&goal=Стандарты и тактика на соперника',
          expected: 'Команда выходит на матч отдохнувшей',
          confidence: 'high'));
    }
  }

  if (!adult) {
    out.add(Advice('info', 'Возраст ${team.ageGroup}',
        'Не больше двух высокоинтенсивных тренировок в неделю, работа с отягощениями — только с весом своего тела; '
        'в период быстрого роста следите за коленями и спиной.',
        basis: 'Возрастная группа команды',
        next: 'При сборке тренировки выбирайте высокую интенсивность не чаще двух раз в неделю',
        expected: 'Нагрузка соответствует возрасту',
        limits: 'Общая методическая памятка, не вывод по данным вашей команды'));
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
          area: 'ОФП', playerId: s.player.id,
          basis: 'Тест ОФП «${m.label}» — измерение, сравнение с нормами возраста',
          next: 'Откройте ОФП игрока: упражнения и повторный тест через 4–6 недель',
          route: '/team/player/${s.player.id}?tab=1',
          expected: 'Рост показателя «${m.label}» на повторном тесте через 4–6 недель',
          confidence: 'high',
          limits: 'Один тест; результат зависит от условий (покрытие, погода, разминка)'));
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
          area: tactical ? 'Тактика' : 'Техника', playerId: s.player.id,
          basis: 'Статистика матчей за 90 минут против игроков своей команды (${s.season.minutes} мин в сезоне)',
          next: 'Составьте программу на 4 недели по этому направлению',
          route: '/team/player/${s.player.id}?tab=2',
          expected: 'Показатель «${axis.label}» ближе к среднему по команде через 4–6 недель',
          confidence: s.season.minutes >= 270 ? 'medium' : 'low',
          limits: 'Статистика зависит от роли в схеме и соперников; ${s.season.minutes} мин — ${s.season.minutes >= 270 ? 'достаточно' : 'мало'} для вывода'));
    }
  }

  // Навыки по оценкам тренера: самая низкая категория.
  final cats = [for (final e in s.categoriesNow.entries) if (e.value != null && e.value! < 50) (e.key, e.value!)]
    ..sort((a, b) => a.$2.compareTo(b.$2));
  if (cats.isNotEmpty && !out.any((a) => a.area == cats.first.$1)) {
    out.add(Advice('work', '${cats.first.$1}: оценка ${cats.first.$2}',
        'Поставьте это направление ключевой целью программы развития на 4–6 недель.',
        area: cats.first.$1, playerId: s.player.id,
        basis: 'Оценки тренера по навыкам (1–5), последние значения',
        next: 'Откройте развитие игрока и создайте программу',
        route: '/team/player/${s.player.id}?tab=2',
        expected: 'Оценка направления выше 50 при следующей оценке',
        limits: 'Оценка тренера — субъективная, не измерение'));
  }

  final pct = s.attendancePct;
  if (pct != null && pct < 75) {
    out.add(Advice('info', 'Посещаемость $pct%',
        adult ? 'Поговорите с игроком: пропуски тормозят прогресс.' : 'Свяжитесь с родителями: пропуски тормозят прогресс.',
        area: 'Посещаемость', playerId: s.player.id,
        basis: 'Отметки посещаемости за 90 дней (уважительные пропуски не считаются)',
        next: adult ? 'Обсудите с игроком график' : 'Напишите родителям',
        route: '/team/player/${s.player.id}',
        expected: 'Посещаемость выше 75% в следующем месяце',
        confidence: 'high',
        limits: 'Причины пропусков в данных не видны'));
  }
  return out;
}

/// План и факт: пропуски игроков, выход за план по времени, затянувшиеся темы, выполненные цели.
List<Advice> planFactAdvice({
  required Team team,
  required List<TrainingSession> sessions,
  required Map<String, SessionReport> reports,
  required List<Attendance> attendance,
  required List<Player> players,
  required List<DevelopmentPlan> plans,
  required List<Drill> library,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  DateTime when(TrainingSession s) => s.finishedAt ?? s.scheduledAt ?? DateTime(2000);
  final done = [for (final s in sessions) if (s.teamId == team.id && s.status == 'done') s]
    ..sort((a, b) => when(b).compareTo(when(a)));
  final out = <Advice>[];

  // 1. Игрок пропустил 2 из 3 последних отмеченных занятий.
  final marked = <String, List<(DateTime, String)>>{};
  final dates = {for (final s in done) s.id: when(s)};
  for (final a in attendance) {
    final d = dates[a.sessionId];
    if (d != null) (marked[a.playerId] ??= []).add((d, a.status));
  }
  for (final p in players.where((p) => p.active)) {
    final last3 = ((marked[p.id] ?? [])..sort((a, b) => b.$1.compareTo(a.$1))).take(3).toList();
    final missed = last3.where((m) => m.$2 == 'absent').length;
    if (last3.length >= 2 && missed >= 2) {
      out.add(Advice('down', '${p.fullName}: пропустил $missed из ${last3.length} занятий',
          'Перед следующим занятием уточните готовность и самочувствие; первое занятие после пропусков — со сниженным объёмом.',
          playerId: p.id,
          basis: 'Отметки посещаемости последних ${last3.length} занятий',
          next: 'Поговорите с игроком${team.ageGroup == 'adult' ? '' : ' или родителями'} и снизьте ему объём на ближайшем занятии',
          route: '/team/player/${p.id}',
          expected: 'Игрок возвращается в общий объём за 1–2 занятия',
          confidence: 'high',
          limits: 'Причина пропусков неизвестна; это не медицинский вывод'));
    }
  }

  // 2. Команда систематически не укладывается в план по времени.
  final withFact = [
    for (final s in done.take(5))
      if ((s.actual['blocks'] as Map?)?.isNotEmpty ?? false) s,
  ].take(3).toList();
  if (withFact.length >= 2) {
    int fact(TrainingSession s) =>
        ((s.actual['blocks'] as Map).values.fold<int>(0, (a, b) => a + (b as int)) / 60).round();
    final diffs = [for (final s in withFact) fact(s) - s.durationMin];
    final over = diffs.where((d) => d >= 8).length, under = diffs.where((d) => d <= -8).length;
    final avg = (diffs.reduce((a, b) => a + b) / diffs.length).round();
    if (over >= 2) {
      out.add(Advice('down', 'Занятия длиннее плана в среднем на $avg мин',
          'В $over из ${withFact.length} последних занятий факт превысил план на 8 мин и больше.',
          basis: 'Факт по таймеру режима «Провести» против плана: ${diffs.map(signed).join(', ')} мин',
          next: 'Планируйте основную часть на $avg мин короче или уберите один блок',
          route: '/sessions/new',
          expected: 'Факт совпадает с планом ±5 мин',
          confidence: over == withFact.length ? 'high' : 'medium',
          limits: 'Если таймер не останавливали на паузах, факт может быть завышен'));
    } else if (under >= 2) {
      out.add(Advice('up', 'Занятия короче плана в среднем на ${-avg} мин',
          'В $under из ${withFact.length} последних занятий блоки заканчивались раньше плана.',
          basis: 'Факт по таймеру режима «Провести» против плана: ${diffs.map(signed).join(', ')} мин',
          next: 'Добавьте в план игровой блок или увеличьте основную часть',
          expected: 'Факт совпадает с планом ±5 мин',
          confidence: under == withFact.length ? 'high' : 'medium',
          limits: 'Блоки могли закончить раньше из-за погоды или поля'));
    }
    final skipped = <String, int>{};
    for (final s in withFact) {
      for (final id in ((s.actual['skipped'] as List?) ?? const []).map((e) => '$e')) {
        final b = s.blocks.where((x) => x.id == id).firstOrNull;
        if (b != null) skipped[b.phase] = (skipped[b.phase] ?? 0) + 1;
      }
    }
    for (final e in skipped.entries.where((e) => e.value >= 2)) {
      out.add(Advice('info', 'Часто пропускается: ${(Phases.all[e.key] ?? e.key).toLowerCase()}',
          'Блок этой части пропущен в ${e.value} из ${withFact.length} последних занятий.',
          basis: 'Отметки «пропустить» в режиме «Провести»',
          next: 'Сократите эту часть в плане или перенесите её задачи в другой блок',
          expected: 'План выполняется полностью',
          confidence: 'medium',
          limits: 'Причина пропуска в данных не указана'));
    }
  }

  // 3. Одна и та же тема в «что улучшить» 3 раза за 4 недели.
  final recentReports = [
    for (final s in done)
      if (at.difference(when(s)).inDays <= 28 && reports[s.id] != null) reports[s.id]!,
  ];
  final themes = <String, int>{};
  for (final r in recentReports) {
    for (final c in namedCategories('${r.toImprove} ${r.nextTime}')) {
      themes[c] = (themes[c] ?? 0) + 1;
    }
  }
  final recentDrills = {for (final s in done.take(3)) for (final b in s.blocks) ?b.drillId};
  final age = team.ageGroup == 'adult' ? 18 : AgeGroups.age(team.ageGroup);
  for (final e in themes.entries.where((e) => e.value >= 3)) {
    final label = DrillCategories.all[e.key] ?? e.key;
    final drills = [
      for (final d in library)
        if (d.category == e.key && !recentDrills.contains(d.id) && age >= d.ageMin && age <= d.ageMax) d,
    ].take(2).toList();
    final control = drills.where((d) => d.successCriteria.isNotEmpty).firstOrNull;
    out.add(Advice('work', 'Тема «$label» не уходит ${e.value} раза за 4 недели',
        'В отчётах тренера тема повторяется в «что улучшить» или «что изменить».',
        basis: 'Тексты ${recentReports.length} отчётов за 28 дней',
        next: [
          if (drills.isNotEmpty) 'Новые упражнения: ${drills.map((d) => '«${d.title}»').join(', ')}',
          if (control != null) 'Контрольное задание: ${control.successCriteria.first}',
        ].join('. ').ifEmpty('Посвятите теме основную часть следующего занятия'),
        route: '/sessions/new?goal=${Uri.encodeComponent(label)}',
        expected: 'Через 2 недели тема перестаёт появляться в отчётах',
        confidence: 'medium',
        limits: 'Вывод по словам в отчётах тренера — это наблюдение, не измерение'));
  }

  // 4. Цель достигнута — следующий этап.
  for (final g in team.seasonGoals.where((g) => g.done)) {
    out.add(Advice('up', 'Цель «${g.text}» выполнена',
        'Поставьте следующий этап — более сложную задачу на ту же тему или новую цель сезона.',
        basis: 'Отметка выполнения цели сезона',
        next: 'Добавьте следующую цель в настройках команды',
        route: '/team/edit/${team.id}',
        expected: 'У команды всегда 2–3 актуальные цели',
        confidence: 'high'));
  }
  final ids = {for (final p in players) p.id};
  for (final p in plans.where((p) => ids.contains(p.playerId))) {
    final player = players.firstWhere((x) => x.id == p.playerId);
    final weeksDone = p.weeks.isNotEmpty && p.weeks.every((w) => w.done);
    final reached = p.targets.isNotEmpty && p.targets.every((t) => t.gap == 0);
    if (!weeksDone && !reached) continue;
    out.add(Advice('up', '${player.fullName}: программа «${p.title}» выполнена',
        weeksDone ? 'Все недели программы отмечены выполненными.' : 'Все цели программы достигнуты.',
        playerId: player.id,
        basis: weeksDone ? 'Отметки недель программы' : 'Цели программы: текущее значение ≥ целевого',
        next: 'Проведите контрольный тест и поставьте следующий этап на 4–8 недель',
        route: '/team/player/${player.id}?tab=2',
        expected: 'Новая программа с более высокой целью',
        confidence: reached ? 'high' : 'medium',
        limits: weeksDone && !reached ? 'Недели отмечены, но измеримые цели ещё не подтверждены' : ''));
  }
  return out;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Все рекомендации тренеру по группам — для отдельного раздела.
class CoachRecommendations {
  CoachRecommendations({
    required this.team,
    required this.nextSession,
    required this.players,
    required this.week,
    required this.missing,
    this.planFact = const [],
  });

  final List<Advice> team, nextSession, players, week;

  /// План против факта: пропуски, выход за время, затянувшиеся темы, выполненные цели.
  final List<Advice> planFact;

  /// Каких данных не хватает, чтобы рекомендации были полнее.
  final List<String> missing;

  bool get isEmpty => team.isEmpty && nextSession.isEmpty && players.isEmpty && week.isEmpty && planFact.isEmpty;

  List<Advice> get all => [...planFact, ...team, ...nextSession, ...week, ...players];
}

/// Какие категории каталога помогают по направлению рекомендации.
const _areaCategories = {
  'Техника': ['technique', 'dribbling', 'passing'],
  'Тактика': ['tactics', 'possession', 'defending'],
  'ОФП': ['physical'],
};

CoachRecommendations coachRecommendations({
  required Team team,
  required List<PlayerSnapshot> players,
  required List<TrainingSession> sessions,
  required Map<String, SessionReport> reports,
  required List<Attendance> attendance,
  required List<Match> matches,
  required List<DevelopmentPlan> plans,
  required List<Drill> library,
  required Map<String, SeasonStats> season,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final adult = team.ageGroup == 'adult';
  final age = adult ? 18 : AgeGroups.age(team.ageGroup);
  final mine = [for (final s in sessions) if (s.teamId == team.id) s];
  final done = [for (final s in mine) if (s.status == 'done') s]
    ..sort((a, b) => (b.finishedAt ?? b.scheduledAt ?? at).compareTo(a.finishedAt ?? a.scheduledAt ?? at));
  final missing = <String>[];

  // Следующая тренировка — по итогам последней проведённой.
  final nextSession = <Advice>[];
  final last = done.firstOrNull;
  if (last != null) {
    final att = [for (final a in attendance) if (a.sessionId == last.id) a];
    for (final i in summarizeSession(last, reports[last.id], att).next) {
      nextSession.add(Advice('info', 'По итогам «${last.title}»', i.text,
          basis: i.basis,
          next: 'Соберите следующую тренировку с учётом этого',
          route: '/sessions/new?goal=${Uri.encodeComponent(last.goal)}',
          expected: 'Следующее занятие учитывает итоги прошлого',
          confidence: i.basis.contains('таймер') || i.basis.contains('посещаем') ? 'high' : 'medium'));
    }
    if (reports[last.id] == null) missing.add('Отчёт по последнему занятию «${last.title}» не заполнен');
  }

  // Игроки: кому нужна дополнительная работа и какие упражнения подойдут.
  final playerTips = <Advice>[];
  for (final s in players) {
    for (final a in playerAdvice(s, adult: adult, team: season.values)) {
      final cats = _areaCategories[a.area];
      final drills = cats == null
          ? const <Drill>[]
          : [for (final d in library) if (cats.contains(d.category) && d.playersMin <= 4 && age >= d.ageMin && age <= d.ageMax) d].take(2).toList();
      playerTips.add(Advice(a.kind, '${s.player.fullName}: ${a.title}', a.text,
          area: a.area,
          playerId: a.playerId,
          basis: a.basis,
          next: drills.isEmpty ? a.next : '${a.next}. Упражнения из каталога: ${drills.map((d) => '«${d.title}»').join(', ')}',
          route: a.route,
          expected: a.expected,
          confidence: a.confidence,
          limits: a.limits));
    }
  }

  // Цели недели: невыполненные цели сезона и текущая неделя индивидуальных программ.
  final week = <Advice>[
    for (final g in team.seasonGoals)
      if (!g.done)
        Advice('info', 'Цель сезона: ${g.text}', 'Разбейте цель на задачу на эту неделю и проверьте её в конце недели.',
            basis: 'Цели команды на сезон',
            next: 'Отметьте выполнение в настройках команды',
            route: '/team/edit/${team.id}',
            expected: 'Понятная задача недели по цели сезона'),
  ];
  for (final p in plans) {
    if (p.weeks.isEmpty || p.startsOn == null) continue;
    final n = at.difference(p.startsOn!).inDays ~/ 7 + 1;
    final w = p.weeks.where((x) => x.n == n).firstOrNull;
    final player = players.where((s) => s.player.id == p.playerId).firstOrNull?.player;
    if (w == null || player == null || w.done) continue;
    week.add(Advice('work', '${player.fullName}: неделя $n «${p.title}»', w.priority,
        playerId: player.id,
        basis: 'Индивидуальная программа на ${p.weeks.length} недель',
        next: 'Как проверить: ${w.criteria}',
        route: '/team/player/${player.id}/plan/${p.id}',
        expected: w.expected,
        confidence: 'medium',
        limits: 'Прогноз программы — ориентир, не гарантия результата'));
  }

  // Каких данных не хватает.
  final recent = done.where((s) => at.difference(s.finishedAt ?? s.scheduledAt ?? at).inDays <= 28).toList();
  if (recent.isEmpty) missing.add('Нет проведённых занятий за 4 недели: проводите тренировки в режиме «Провести»');
  if (!recent.any((s) => reports[s.id]?.rpe != null)) missing.add('Нет оценок нагрузки RPE в отчётах — без них нет советов по интенсивности');
  if (!players.any((s) => s.lastTest != null)) missing.add('Нет тестов ОФП — проведите тестирование, чтобы видеть физические зоны роста');
  if (!players.any((s) => s.skillsNow.isNotEmpty)) missing.add('Нет оценок навыков 1–5 — оцените игроков в карточках');
  if (!attendance.any((a) => recent.any((s) => s.id == a.sessionId))) missing.add('Нет отметок посещаемости за 4 недели');

  List<Advice> keyed(List<Advice> l) => [for (final a in l) a.key.isEmpty ? a.withKey(adviceKey(a, at)) : a];
  return CoachRecommendations(
    team: keyed(teamAdvice(team: team, sessions: sessions, reports: reports, matches: matches, now: at)),
    nextSession: keyed(nextSession),
    players: keyed(playerTips),
    week: keyed(week),
    missing: missing,
    planFact: keyed(planFactAdvice(
      team: team,
      sessions: sessions,
      reports: reports,
      attendance: attendance,
      players: [for (final s in players) s.player],
      plans: plans,
      library: library,
      now: at,
    )),
  );
}
