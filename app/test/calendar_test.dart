import 'package:coachpilot/core/calendar.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final slot = ScheduleSlot(
    id: 's1',
    teamId: 'u16',
    title: 'Тренировка U16',
    weekdays: [1, 3],
    startTime: '10:00',
    durationMin: 120,
    validFrom: DateTime(2026, 9, 1),
    validTo: DateTime(2026, 11, 30),
  );
  final pro = ScheduleSlot(id: 's2', teamId: 'pro', title: 'Основа', weekdays: [1], startTime: '16:00');
  final match = Match(id: 'm1', teamId: 'pro', opponent: 'Зенит', startsAt: DateTime(2026, 10, 19, 19, 0));

  test('регулярная тренировка в свои дни недели и в пределах сезона', () {
    expect(slot.occursOn(DateTime(2026, 10, 19)), isTrue); // понедельник
    expect(slot.occursOn(DateTime(2026, 10, 20)), isFalse); // вторник
    expect(slot.occursOn(DateTime(2026, 8, 31)), isFalse); // до начала сезона
    expect(slot.occursOn(DateTime(2026, 11, 30, 15)), isTrue); // последний день включительно
    expect(slot.endTime, '12:00');
    expect(slot.daysLabel, 'Пн, Ср');
  });

  test('события дня по времени, фильтр по командам', () {
    final day = DateTime(2026, 10, 19);
    final all = eventsForDay(day, matches: [match], slots: [slot, pro], sessions: []);
    expect(all.map((e) => e.title), ['Тренировка U16', 'Основа', 'Зенит']);
    expect(all.first.end, DateTime(2026, 10, 19, 12));
    final onlyU16 = eventsForDay(day, matches: [match], slots: [slot, pro], sessions: [], teamIds: {'u16'});
    expect(onlyU16.map((e) => e.title), ['Тренировка U16']);
  });

  test('занятие с планом заменяет регулярную тренировку того же времени', () {
    final day = DateTime(2026, 10, 19);
    final s = TrainingSession(
      id: 't1',
      teamId: 'u16',
      title: 'Передачи',
      durationMin: 120,
      status: 'planned',
      scheduledAt: DateTime(2026, 10, 19, 10, 0),
    );
    final cancelled = TrainingSession(
      id: 't2',
      teamId: 'pro',
      title: 'Отменена',
      durationMin: 60,
      status: 'cancelled',
      scheduledAt: DateTime(2026, 10, 19, 16, 0),
    );
    final ev = eventsForDay(day, matches: const [], slots: [slot, pro], sessions: [s, cancelled]);
    expect(ev.map((e) => '${e.kind.name}:${e.title}'), ['training:Передачи', 'slot:Основа']);
  });

  test('проведённое занятие показывается в день проведения', () {
    final s = TrainingSession(
      id: 't',
      title: 'Перенесли',
      durationMin: 60,
      status: 'done',
      scheduledAt: DateTime(2026, 10, 21, 18),
      startedAt: DateTime(2026, 10, 20, 10),
    );
    expect(eventsForDay(DateTime(2026, 10, 20), matches: const [], slots: const [], sessions: [s]).length, 1);
    expect(eventsForDay(DateTime(2026, 10, 21), matches: const [], slots: const [], sessions: [s]), isEmpty);
  });

  test('сетка месяца начинается с понедельника и кончается воскресеньем', () {
    final g = monthGrid(DateTime(2026, 10));
    expect(g.first, DateTime(2026, 9, 28));
    expect(g.last, DateTime(2026, 11, 1));
    expect(g.length % 7, 0);
  });

  test('json матча и расписания', () {
    final j = slot.toJson();
    expect(j['valid_from'], '2026-09-01');
    final back = ScheduleSlot.fromJson('s1', j);
    expect(back.weekdays, [1, 3]);
    expect(back.validTo, DateTime(2026, 11, 30));
    final mj = Match.fromJson('m1', match.toJson());
    expect(mj.startsAt, match.startsAt);
    expect(mj.home, isTrue);
  });

  group('импорт матчей', () {
    final now = DateTime(2026, 8, 1);

    test('таблица с заголовком', () {
      final rows = [
        ['Календарь игр сезона 2026/27'],
        ['Дата', 'Время', 'Соперник', 'Д/Г', 'Стадион', 'Турнир'],
        ['15.08.2026', '18:00', 'Зенит U16', 'Д', 'Звезда', 'Первенство'],
        ['22.08', '12:30', 'Урал U16', 'гости', '', 'Первенство'],
        ['', '', '', '', '', ''],
        ['ошибка', '', 'Нет даты', '', '', ''],
      ];
      final m = parseMatches(rows, now: now);
      expect(m.length, 2);
      expect(m[0].startsAt, DateTime(2026, 8, 15, 18));
      expect(m[0].opponent, 'Зенит U16');
      expect(m[0].home, isTrue);
      expect(m[0].venue, 'Звезда');
      expect(m[0].competition, 'Первенство');
      expect(m[1].startsAt, DateTime(2026, 8, 22, 12, 30));
      expect(m[1].home, isFalse);
    });

    test('строки текста и своя команда в паре', () {
      final rows = [
        ['5 сентября 16:00 Амкар — Зенит'],
        ['12.09 Урал - Амкар'],
        ['19 сен, Крылья Советов (г)'],
        ['10.01 Спартак дома'],
      ];
      final m = parseMatches(rows, now: now, ownNames: ['Амкар']);
      expect(m.map((e) => e.opponent), ['Зенит', 'Урал', 'Крылья Советов', 'Спартак']);
      expect(m.map((e) => e.home), [true, false, false, true]);
      expect(m[0].startsAt, DateTime(2026, 9, 5, 16));
      expect(m[1].startsAt, DateTime(2026, 9, 12, 12));
      // Январь раньше «сейчас» — значит, следующего года.
      expect(m[3].startsAt.year, 2027);
    });
  });
}
