// Понедельная индивидуальная программа: из выбранных навыков, возраста и доступного времени.
// Прогноз — ориентир для тренера, а не обещание результата.

import 'dart:math' as math;

import '../data/models.dart';

/// Какие категории каталога развивают навык.
const skillCategories = {
  'technique': ['technique', 'dribbling'],
  'passing': ['passing', 'possession'],
  'dribbling': ['dribbling', 'technique'],
  'finishing': ['finishing'],
  'positioning': ['tactics', 'defending'],
  'decision': ['possession', 'tactics', 'transition'],
  'physical': ['physical'],
  'attitude': ['game', 'possession'],
};

/// Как проверить прогресс по навыку — измеримо и одинаково каждую неделю.
const _criteria = {
  'technique': 'Из 20 касаний под давлением — сколько без потери; записать результат недели',
  'passing': 'Точные передачи в упражнении: X из 20 (записать и сравнить с прошлой неделей)',
  'dribbling': 'Удачные обводки 1×1: X из 10 попыток',
  'finishing': 'Удары в створ: X из 10 с одной и той же позиции',
  'positioning': 'Оценка тренера 1–5 по игре в позиции на тренировке',
  'decision': 'Оценка тренера 1–5: выбор решения в игре в малых составах',
  'physical': 'Контрольный тест ОФП в конце этапа (бег 10/30 м или челнок)',
  'attitude': 'Оценка тренера 1–5: включённость и общение на тренировке',
};

/// Этапы программы: освоение → закрепление → применение в игре.
({String name, String load, String expected}) _stage(int week, int total, {required bool adult, required int minutes}) {
  final part = week / total;
  if (part <= 1 / 3) {
    return (
      name: 'Освоение',
      load: '$minutes мин за занятие, низкая интенсивность, много повторений без давления',
      expected: 'Ориентир: правильная техника выполнения в простых условиях',
    );
  }
  if (part <= 2 / 3) {
    return (
      name: 'Закрепление',
      load: '$minutes мин за занятие, средняя интенсивность, с пассивным соперником',
      expected: 'Ориентир: стабильное выполнение в темпе, результат лучше первой недели',
    );
  }
  return (
    name: 'Применение в игре',
    load: '$minutes мин за занятие, ${adult ? 'высокая' : 'средняя–высокая'} интенсивность, игровые упражнения с соперником',
    expected: 'Ориентир: навык появляется в игре; контрольный замер в последнюю неделю',
  );
}

/// Понедельный план на [weeks] недель по навыкам [focus].
/// [sessionsPerWeek] и [minutes] — сколько доп. занятий в неделю и по сколько минут готов игрок.
List<PlanWeek> buildPlanWeeks({
  required int weeks,
  required List<String> focus,
  required List<Drill> library,
  required int age,
  int sessionsPerWeek = 2,
  int minutes = 20,
}) {
  final skills = focus.isEmpty ? ['technique'] : focus;
  final adult = age >= 18;
  // Индивидуальная работа: упражнения для 1–4 человек, подходящие возрасту.
  final pool = [for (final d in library) if (d.playersMin <= 4 && age >= d.ageMin && age <= d.ageMax) d];
  final used = <String>{};
  return [
    for (var n = 1; n <= weeks; n++)
      () {
        final skill = skills[(n - 1) % skills.length];
        final stage = _stage(n, weeks, adult: adult, minutes: minutes);
        final cats = skillCategories[skill] ?? const ['technique'];
        // На этапе освоения — спокойные упражнения, на применении — интенсивные.
        final wantHigh = stage.name == 'Применение в игре';
        final options = [for (final d in pool) if (cats.contains(d.category)) d]
          ..sort((a, b) {
            final u = (used.contains(a.id) ? 1 : 0).compareTo(used.contains(b.id) ? 1 : 0);
            if (u != 0) return u;
            final ia = a.intensity == 'high' ? 2 : (a.intensity == 'medium' ? 1 : 0);
            final ib = b.intensity == 'high' ? 2 : (b.intensity == 'medium' ? 1 : 0);
            return (wantHigh ? ib.compareTo(ia) : ia.compareTo(ib));
          });
        final drills = options.take(2).toList();
        used.addAll(drills.map((d) => d.id));
        return PlanWeek(
          n: n,
          priority: '${stage.name}: ${(Skills.all[skill] ?? skill).toLowerCase()}',
          drills: [for (final d in drills) d.title],
          sessions: math.max(1, math.min(sessionsPerWeek, 5)),
          load: stage.load,
          expected: stage.expected,
          criteria: _criteria[skill] ?? 'Оценка тренера 1–5 в конце недели',
        );
      }(),
  ];
}
