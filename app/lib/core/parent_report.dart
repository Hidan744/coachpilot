import 'package:intl/intl.dart';

import '../data/models.dart';

/// Текст для родителей (мессенджер): посещаемость, план развития и сообщения тренера.
/// В текст попадает только то, что тренер отметил «видно родителям».
String parentMessage({
  required Player player,
  Team? team,
  required int present,
  required int total,
  List<DevelopmentPlan> plans = const [],
  List<ParentNote> notes = const [],
  String coach = '',
}) {
  final b = StringBuffer()
    ..writeln('${player.fullName}${team == null ? '' : ' · ${team.name}'}')
    ..writeln(total == 0 ? 'Посещаемость: отметок пока нет' : 'Посещаемость: ${(present * 100 / total).round()}% ($present из $total)');
  final shownNotes = notes.where((n) => n.shared).toList()..sort((a, b) => b.writtenAt.compareTo(a.writtenAt));
  if (shownNotes.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Сообщения тренера:');
    for (final n in shownNotes.take(5)) {
      b.writeln('• ${ParentNoteCategories.all[n.category] ?? n.category} (${DateFormat('dd.MM').format(n.writtenAt)}): ${n.text}');
    }
  }
  for (final p in plans.where((p) => p.shared)) {
    b
      ..writeln()
      ..writeln('План развития — ${PlanPeriods.all[p.period]?.toLowerCase() ?? p.period}: ${p.title}');
    for (final i in p.items) {
      b.writeln('${i.done ? '✅' : '▫️'} ${i.kind == 'goal' ? 'Цель: ' : ''}${i.text}');
    }
    if (p.comment.isNotEmpty) b.writeln('Комментарий: ${p.comment}');
  }
  if (coach.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Тренер: $coach');
  }
  return b.toString().trim();
}

/// Даты периода плана, начиная с [from]: неделя — с понедельника по воскресенье, цикл 4–6 недель — с понедельника,
/// месяц — до конца месяца, сезон — до 31 мая (или до 31 мая следующего года, если сейчас лето-осень).
(DateTime, DateTime) periodRange(String period, DateTime from) {
  final d = DateTime(from.year, from.month, from.day);
  return switch (period) {
    'week' => (d.subtract(Duration(days: d.weekday - 1)), d.add(Duration(days: 7 - d.weekday))),
    'month' => (DateTime(d.year, d.month), DateTime(d.year, d.month + 1, 0)),
    'cycle4' => (d.subtract(Duration(days: d.weekday - 1)), d.subtract(Duration(days: d.weekday - 1)).add(const Duration(days: 27))),
    'cycle6' => (d.subtract(Duration(days: d.weekday - 1)), d.subtract(Duration(days: d.weekday - 1)).add(const Duration(days: 41))),
    'cycle8' => (d.subtract(Duration(days: d.weekday - 1)), d.subtract(Duration(days: d.weekday - 1)).add(const Duration(days: 55))),
    'cycle12' => (d.subtract(Duration(days: d.weekday - 1)), d.subtract(Duration(days: d.weekday - 1)).add(const Duration(days: 83))),
    _ => (d, DateTime(d.month > 5 ? d.year + 1 : d.year, 5, 31)),
  };
}
