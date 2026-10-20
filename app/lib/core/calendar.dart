import '../data/models.dart';

enum CalendarKind { match, training, slot }

/// Событие дня в календаре: матч, тренировка с планом или регулярная тренировка из расписания.
class CalendarEvent {
  CalendarEvent._(this.kind, this.start, this.end, {this.match, this.session, this.slot});

  final CalendarKind kind;
  final DateTime start, end;
  final Match? match;
  final TrainingSession? session;
  final ScheduleSlot? slot;

  String? get teamId => match?.teamId ?? session?.teamId ?? slot?.teamId;

  String get title => switch (kind) {
        CalendarKind.match => match!.opponent,
        CalendarKind.training => session!.title,
        CalendarKind.slot => slot!.title,
      };
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Все события дня, по времени начала.
///
/// Регулярная тренировка заменяется занятием, если на этот день и время у команды уже есть план
/// (тренер открыл тренировку из расписания и составил план). Отменённые занятия не показываются.
List<CalendarEvent> eventsForDay(
  DateTime day, {
  required List<Match> matches,
  required List<ScheduleSlot> slots,
  required List<TrainingSession> sessions,
  Set<String>? teamIds,
}) {
  bool teamOk(String? id) => teamIds == null || (id != null && teamIds.contains(id));
  final out = <CalendarEvent>[];
  for (final m in matches) {
    if (sameDay(m.startsAt, day) && teamOk(m.teamId)) {
      out.add(CalendarEvent._(CalendarKind.match, m.startsAt, m.startsAt.add(Duration(minutes: m.durationMin)), match: m));
    }
  }
  final daySessions = <TrainingSession>[];
  for (final s in sessions) {
    // Проведённое занятие — в день, когда его провели; запланированное — на дату плана.
    final at = s.status == 'done' || s.status == 'in_progress' ? s.startedAt ?? s.scheduledAt : s.scheduledAt ?? s.startedAt;
    if (at == null || s.status == 'cancelled' || !sameDay(at, day) || !teamOk(s.teamId)) continue;
    daySessions.add(s);
    out.add(CalendarEvent._(CalendarKind.training, at, at.add(Duration(minutes: s.durationMin)), session: s));
  }
  for (final sl in slots) {
    if (!sl.occursOn(day) || !teamOk(sl.teamId)) continue;
    final start = dayOf(day).add(Duration(minutes: sl.startMinutes));
    final covered = daySessions.any((s) => s.teamId == sl.teamId && (s.scheduledAt ?? s.startedAt)!.difference(start).inMinutes.abs() < 60);
    if (covered) continue;
    out.add(CalendarEvent._(CalendarKind.slot, start, start.add(Duration(minutes: sl.durationMin)), slot: sl));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// Дни месяца для сетки: с понедельника недели первого дня до воскресенья недели последнего.
List<DateTime> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final start = first.subtract(Duration(days: first.weekday - 1));
  final end = last.add(Duration(days: 7 - last.weekday));
  return [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d];
}

// ---------------------------------------------------------------- импорт расписания матчей

class ImportedMatch {
  ImportedMatch({required this.startsAt, required this.opponent, this.home = true, this.venue = '', this.competition = ''});

  final DateTime startsAt;
  final String opponent;
  final bool home;
  final String venue, competition;
}

const _months = {
  'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4, 'мая': 5, 'май': 5, 'июн': 6,
  'июл': 7, 'авг': 8, 'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12,
};

final _numDate = RegExp(r'(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?');
final _isoDate = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
final _wordDate = RegExp(r'(\d{1,2})\s+(янв|фев|мар|апр|мая|май|июн|июл|авг|сен|окт|ноя|дек)[а-яё]*\.?(?:\s+(\d{4}))?', caseSensitive: false);
final _time = RegExp(r'(?<![\d.])([01]?\d|2[0-3])[:.]([0-5]\d)(?![\d.])');

/// Дата и время из строки. Год не указан — ближайшая такая дата не раньше чем [now] минус 30 дней.
DateTime? parseDateTime(String s, DateTime now) {
  int? y, mo, d;
  final iso = _isoDate.firstMatch(s);
  final word = _wordDate.firstMatch(s);
  final num = _numDate.firstMatch(s);
  var rest = s;
  if (iso != null) {
    y = int.parse(iso[1]!);
    mo = int.parse(iso[2]!);
    d = int.parse(iso[3]!);
    rest = s.replaceFirst(iso[0]!, ' ');
  } else if (word != null) {
    d = int.parse(word[1]!);
    mo = _months[word[2]!.toLowerCase()];
    y = word[3] == null ? null : int.parse(word[3]!);
    rest = s.replaceFirst(word[0]!, ' ');
  } else if (num != null) {
    d = int.parse(num[1]!);
    mo = int.parse(num[2]!);
    if (num[3] != null) y = int.parse(num[3]!) + (num[3]!.length == 2 ? 2000 : 0);
    rest = s.replaceFirst(num[0]!, ' ');
  }
  if (d == null || mo == null || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final t = _time.firstMatch(rest);
  final h = t == null ? 12 : int.parse(t[1]!);
  final mi = t == null ? 0 : int.parse(t[2]!);
  if (y == null) {
    y = now.year;
    if (DateTime(y, mo, d).isBefore(now.subtract(const Duration(days: 30)))) y++;
  }
  return DateTime(y, mo, d, h, mi);
}

bool? _homeFlag(String s) {
  final v = s.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (RegExp(r'^(д|дом|дома|h|home|хозяева)\.?$').hasMatch(v) || v.contains('дома')) return true;
  if (RegExp(r'^(г|гост|гости|в гостях|a|away|выезд)\.?$').hasMatch(v) || v.contains('гост') || v.contains('выезд')) return false;
  return null;
}

Map<String, int>? _matchHeader(List<String> row) {
  final map = <String, int>{};
  for (var i = 0; i < row.length; i++) {
    final c = row[i].toLowerCase().trim();
    if (c.isEmpty) continue;
    if (c.contains('дата') || c == 'день') {
      map['date'] ??= i;
    } else if (c.contains('время') || c == 'начало') {
      map['time'] ??= i;
    } else if (c.contains('соперник') || c.contains('противник') || c.contains('команда') || c.contains('матч') || c.contains('игра')) {
      map['opponent'] ??= i;
    } else if (c.contains('стадион') || c.contains('место') || c.contains('поле') || c.contains('адрес')) {
      map['venue'] ??= i;
    } else if (c.contains('турнир') || c.contains('соревнован') || c.contains('лига') || c.contains('кубок') || c.contains('тур')) {
      map['competition'] ??= i;
    } else if (c.contains('дома') || c.contains('гост') || c.contains('д/г') || c.contains('поле')) {
      map['home'] ??= i;
    }
  }
  return map.containsKey('date') && map.containsKey('opponent') ? map : null;
}

/// Соперник и сторона из «Амкар — Зенит»: своя команда слева — дома, справа — в гостях.
(String, bool?) _opponentOf(String s, List<String> ownNames) {
  var text = s.trim();
  bool? home;
  final flag = RegExp(r'\((д|г|дома|в гостях)\)', caseSensitive: false).firstMatch(text);
  if (flag != null) {
    home = _homeFlag(flag[1]!);
    text = text.replaceFirst(flag[0]!, '').trim();
  }
  final parts = text.split(RegExp(r'\s+[-–—]\s+|\s+vs\.?\s+|\s*:\s+'));
  if (parts.length == 2) {
    bool own(String p) => ownNames.any((n) => n.isNotEmpty && p.toLowerCase().contains(n.toLowerCase()));
    if (own(parts[0])) return (parts[1].trim(), home ?? true);
    if (own(parts[1])) return (parts[0].trim(), home ?? false);
  }
  return (text, home);
}

/// Матчи сезона из таблицы (Excel, Word, CSV) или из строк текста.
List<ImportedMatch> parseMatches(List<List<String>> rows, {required DateTime now, List<String> ownNames = const []}) {
  final out = <ImportedMatch>[];
  Map<String, int>? header;
  for (final row in rows) {
    final cells = row.map((c) => c.trim()).toList();
    if (cells.every((c) => c.isEmpty)) continue;
    final h = _matchHeader(cells);
    if (h != null) {
      header = h;
      continue;
    }
    if (header != null) {
      String cell(String k) => header![k] != null && header[k]! < cells.length ? cells[header[k]!] : '';
      final when = parseDateTime('${cell('date')} ${cell('time')}', now);
      final (opp, side) = _opponentOf(cell('opponent'), ownNames);
      if (when == null || opp.isEmpty) continue;
      out.add(ImportedMatch(
        startsAt: when,
        opponent: opp,
        home: _homeFlag(cell('home')) ?? side ?? true,
        venue: cell('venue'),
        competition: cell('competition'),
      ));
      continue;
    }
    // Без заголовка: «12.10 18:00 Зенит (д)» или «12 октября, Амкар — Зенит».
    final line = cells.where((c) => c.isNotEmpty).join(' ');
    final when = parseDateTime(line, now);
    if (when == null) continue;
    var rest = line
        .replaceAll(_isoDate, ' ')
        .replaceAll(_wordDate, ' ')
        .replaceAll(_numDate, ' ')
        .replaceAll(_time, ' ')
        .replaceAll(RegExp(r'^[\s,.;|–—-]+|[\s,.;|–—-]+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    bool? home;
    for (final w in ['дома', 'в гостях', 'выезд']) {
      if (rest.toLowerCase().contains(w)) {
        home = w == 'дома';
        rest = rest.replaceAll(RegExp(w, caseSensitive: false), '').trim();
      }
    }
    final (opp, side) = _opponentOf(rest.replaceAll(RegExp(r'^[,.;|–—-]+|[,.;|–—-]+$'), '').trim(), ownNames);
    if (opp.isEmpty) continue;
    out.add(ImportedMatch(startsAt: when, opponent: opp, home: home ?? side ?? true));
  }
  return out;
}
