import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/data/repo.dart';
import 'package:coachpilot/ui/screens/team/team_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('статистика посещаемости: опоздание считается, уважительная причина не учитывается', () {
    Attendance a(String p, String s) => Attendance(id: newId(), sessionId: newId(), playerId: p, status: s);
    final all = [a('p1', 'present'), a('p1', 'late'), a('p1', 'absent'), a('p1', 'excused'), a('p2', 'present')];
    expect(attendanceStats(all, 'p1'), (2, 3));
    expect(attendanceStats(all, 'p2'), (1, 1));
    expect(attendanceStats(all, 'p3'), (0, 0));
  });

  test('id посещаемости детерминирован и совпадает с uuid5 на сервере', () {
    expect(attendanceId('7c9e6679-7425-40de-944b-e07fc1f90ae7', 'abc'), attendanceId('7c9e6679-7425-40de-944b-e07fc1f90ae7', 'abc'));
    // python: uuid.uuid5(uuid.UUID('7c9e6679-7425-40de-944b-e07fc1f90ae7'), 'abc')
    expect(attendanceId('7c9e6679-7425-40de-944b-e07fc1f90ae7', 'abc'), 'bbe1865a-5144-58fb-b080-09165040f2d6');
  });

  test('TrainingSession: JSON туда-обратно, сумма минут блоков', () {
    final s = TrainingSession(
      id: 'x',
      title: 'Т',
      durationMin: 60,
      scheduledAt: DateTime.utc(2026, 10, 20, 15),
      blocks: const [
        TrainingBlock(id: 'a', phase: 'warmup', title: 'Р', durationMin: 15),
        TrainingBlock(id: 'b', phase: 'main', title: 'О', durationMin: 45, notes: 'n'),
      ],
    );
    final back = TrainingSession.fromJson('x', s.toJson());
    expect(back.plannedMinutes, 60);
    expect(back.blocks[1].notes, 'n');
    expect(back.scheduledAt!.toUtc(), DateTime.utc(2026, 10, 20, 15));
  });

  test('Drill со схемой: JSON туда-обратно', () {
    final d = Drill(
      id: 'd',
      title: 'Квадрат',
      category: 'possession',
      easier: const ['больше зона'],
      scheme: const Scheme(field: 'grid', items: [
        SchemeItem(type: 'player_a', x: 0.1, y: 0.2),
        SchemeItem(type: 'arrow_pass', x: 0.1, y: 0.2, x2: 0.5, y2: 0.5),
      ]),
    );
    final back = Drill.fromJson('d', d.toJson());
    expect(back.scheme!.items[1].x2, 0.5);
    expect(back.easier, ['больше зона']);
  });
}
