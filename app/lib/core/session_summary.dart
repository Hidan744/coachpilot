// Сводка по итогам занятия — только из фактических данных: план, факт по блокам, посещаемость, отчёт тренера.

import '../data/models.dart';

/// Пункт сводки: что сказано и на чём основано.
class SummaryItem {
  const SummaryItem(this.text, {this.basis = ''});

  final String text;

  /// Откуда вывод: «факт по таймеру», «отчёт тренера», «оценка RPE» и т. п.
  final String basis;
}

class SessionSummary {
  SessionSummary({required this.achieved, required this.notDone, required this.problems, required this.next, required this.missingData});

  final List<SummaryItem> achieved, notDone, problems, next;

  /// Каких данных не хватает для полной сводки.
  final List<String> missingData;
}

SessionSummary summarizeSession(TrainingSession s, SessionReport? r, List<Attendance> attendance) {
  final actual = (s.actual['blocks'] as Map?)?.cast<String, dynamic>() ?? const {};
  final skipped = ((s.actual['skipped'] as List?) ?? const []).map((e) => '$e').toSet();
  final done = [for (final b in s.blocks) if (actual.containsKey(b.id) && !skipped.contains(b.id)) b];
  final missed = [for (final b in s.blocks) if (skipped.contains(b.id)) b];
  final achieved = <SummaryItem>[], notDone = <SummaryItem>[], problems = <SummaryItem>[], next = <SummaryItem>[];
  final missing = <String>[];

  if (actual.isEmpty) {
    missing.add('Факт по блокам: проведите занятие в режиме «Провести» — тогда будет видно, что выполнено');
  } else {
    final minutes = (actual.values.fold<int>(0, (a, b) => a + (b as int)) / 60).round();
    achieved.add(SummaryItem('Проведено блоков: ${done.length} из ${s.blocks.length}, $minutes из ${s.durationMin} мин', basis: 'факт по таймеру'));
    if (s.goal.isNotEmpty && done.any((b) => b.phase == 'main')) {
      achieved.add(SummaryItem('Основная часть по цели «${s.goal}» проведена', basis: 'факт по таймеру'));
    }
    for (final b in missed) {
      notDone.add(SummaryItem('Пропущен блок «${b.title}» (${b.durationMin} мин)', basis: 'факт по таймеру'));
    }
    // Блоки, которые заняли заметно больше или меньше плана.
    for (final b in done) {
      final sec = actual[b.id] as int;
      final diff = (sec / 60 - b.durationMin).round();
      if (diff.abs() >= 5) {
        problems.add(SummaryItem('«${b.title}»: ${diff > 0 ? 'дольше' : 'короче'} плана на ${diff.abs()} мин', basis: 'факт по таймеру'));
      }
    }
  }

  final marked = [for (final a in attendance) if (a.status != 'excused') a];
  if (marked.isEmpty) {
    missing.add('Посещаемость: отметьте, кто был на занятии');
  } else {
    final present = marked.where((a) => a.status == 'present' || a.status == 'late').length;
    final injured = marked.where((a) => a.status == 'injured').length;
    achieved.add(SummaryItem('Было $present из ${marked.length} игроков', basis: 'посещаемость'));
    if (present * 100 / marked.length < 70) {
      problems.add(SummaryItem('Низкая посещаемость: ${(present * 100 / marked.length).round()}%', basis: 'посещаемость'));
      next.add(const SummaryItem('Уточните причины пропусков; групповые упражнения подбирайте под меньший состав', basis: 'посещаемость'));
    }
    if (injured > 0) problems.add(SummaryItem('Травмы: $injured', basis: 'посещаемость'));
  }

  if (r == null) {
    missing.add('Отчёт тренера: оценка, что получилось и что улучшить');
  } else {
    if (r.wentWell.isNotEmpty) achieved.add(SummaryItem(r.wentWell, basis: 'отчёт тренера'));
    if (r.toImprove.isNotEmpty) problems.add(SummaryItem(r.toImprove, basis: 'отчёт тренера'));
    if (r.nextTime.isNotEmpty) next.add(SummaryItem(r.nextTime, basis: 'решение тренера'));
    if (r.rpe != null && r.rpe! >= 8) {
      next.add(SummaryItem('Нагрузка была высокой (RPE ${r.rpe}): следующее занятие — средней интенсивности', basis: 'оценка нагрузки RPE'));
    } else if (r.rpe != null && r.rpe! <= 3) {
      next.add(SummaryItem('Нагрузка была низкой (RPE ${r.rpe}): можно добавить темп и игры в малых составах', basis: 'оценка нагрузки RPE'));
    }
    if (r.rating != null && r.rating! <= 2) {
      next.add(SummaryItem('Оценка занятия ${r.rating} из 5: упростите основное упражнение или уменьшите зону', basis: 'оценка тренера'));
    }
    if (r.rpe == null) missing.add('Оценка нагрузки RPE — нужна для графика нагрузки и рекомендаций по интенсивности');
  }
  if (missed.isNotEmpty) {
    next.add(SummaryItem('Перенести на следующее занятие: ${missed.map((b) => '«${b.title}»').join(', ')}', basis: 'факт по таймеру'));
  }
  return SessionSummary(achieved: achieved, notDone: notDone, problems: problems, next: next, missingData: missing);
}

/// Отчёт о занятии текстом — для штаба, мессенджера или печати.
String reportAsText(TrainingSession s, SessionReport? r, SessionSummary sum, Map<String, String> playerNames) {
  final out = StringBuffer()..writeln('Отчёт о занятии: ${s.title}');
  if (s.goal.isNotEmpty) out.writeln('Цель: ${s.goal}');
  if (r?.rating != null) out.writeln('Оценка тренера: ${r!.rating} из 5');
  if (r?.rpe != null) out.writeln('Нагрузка (RPE): ${r!.rpe} из 10');
  void list(String title, List<SummaryItem> items) {
    if (items.isEmpty) return;
    out
      ..writeln()
      ..writeln(title);
    for (final i in items) {
      out.writeln('• ${i.text}${i.basis.isEmpty ? '' : ' [${i.basis}]'}');
    }
  }

  list('Выполнено', sum.achieved);
  list('Не выполнено', sum.notDone);
  list('Проблемы', sum.problems);
  if (r != null && r.playerNotes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('По игрокам');
    for (final e in r.playerNotes.entries) {
      out.writeln('• ${playerNames[e.key] ?? 'Игрок'}: ${e.value}');
    }
  }
  list('На следующее занятие', sum.next);
  if (r != null && r.aiSuggestions.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Предложения AI (не наблюдения тренера)');
    for (final x in r.aiSuggestions) {
      out.writeln('• $x');
    }
  }
  if (sum.missingData.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Не хватает данных');
    for (final m in sum.missingData) {
      out.writeln('• $m');
    }
  }
  return out.toString().trimRight();
}
