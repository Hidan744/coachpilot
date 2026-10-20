import 'package:coachpilot/core/tactics.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Player pl(String last, String? pos, [int? n]) =>
    Player(id: last, teamId: 't', firstName: 'И', lastName: last, position: pos, number: n);

void main() {
  test('все расстановки дают нужное число игроков и не выходят за поле', () {
    for (final group in formations.entries) {
      final expected = int.parse(group.key.split('×').first);
      for (final f in group.value) {
        final pts = formationPoints(f);
        expect(pts.length, expected, reason: f);
        expect(playersInFormation(f), expected);
        for (final p in [...pts, ...formationPoints(f, opponent: true)]) {
          expect(p.x, inInclusiveRange(0.05, 0.95), reason: f);
          expect(p.y, inInclusiveRange(0.05, 0.95), reason: f);
        }
      }
    }
  });

  test('вратарь внизу, атака выше обороны, соперник зеркально', () {
    final pts = formationPoints('4-3-3');
    expect(pts.first.y, greaterThan(0.9));
    expect(pts[1].y, greaterThan(pts.last.y));
    final opp = formationPoints('4-3-3', opponent: true);
    expect(opp.first.y, lessThan(0.1));
  });

  test('состав расставляется по позициям', () {
    final players = [
      pl('Нападающий', 'FW', 9),
      pl('Защитник1', 'DF', 2),
      pl('Вратарь', 'GK', 1),
      pl('Хав', 'MF', 8),
      pl('Защитник2', 'DF', 3),
      pl('Без позиции', null),
    ];
    final lineup = assignLineup('2-3-1', players);
    expect(lineup.length, 7);
    expect(lineup[0]!.lastName, 'Вратарь');
    expect(lineup.sublist(1, 3).map((p) => p!.lastName), ['Защитник1', 'Защитник2']);
    expect(lineup[3]!.lastName, 'Хав');
    expect(lineup[6]!.lastName, 'Нападающий');
    expect(lineup.where((p) => p == null).length, 1);
    final items = formationItems('2-3-1', lineup: lineup);
    expect(items.first.type, 'goalkeeper');
    expect(items.first.label, '1|Вратарь');
    expect(items[4].label, 'Б|Без позиции');
  });

  test('поворот доски туда и обратно возвращает координаты', () {
    final s = Scheme(field: 'full_v', items: [
      const SchemeItem(type: 'player_a', x: 0.2, y: 0.8, label: '7|Петров'),
      const SchemeItem(type: 'arrow_run', x: 0.2, y: 0.8, x2: 0.3, y2: 0.5, step: 2),
      const SchemeItem(type: 'pen', x: 0.1, y: 0.1, points: [Offset2(0.1, 0.1), Offset2(0.4, 0.2)], color: '#FFEB3B'),
    ]);
    final h = rotateBoard(s);
    expect(h.field, 'full');
    // Атака вверх на вертикальном поле — атака вправо на горизонтальном.
    expect(h.items[1].x2!, greaterThan(h.items[1].x));
    final back = rotateBoard(h);
    expect(back.field, 'full_v');
    for (var i = 0; i < s.items.length; i++) {
      expect(back.items[i].x, closeTo(s.items[i].x, 1e-9));
      expect(back.items[i].y, closeTo(s.items[i].y, 1e-9));
    }
    expect(back.items[2].points![1].x, closeTo(0.4, 1e-9));
    expect(back.items[1].step, 2);
  });

  test('линия от руки упрощается и json сохраняет точки', () {
    final pts = [for (var i = 0; i < 2000; i++) Offset2(i / 2000, 0.5)];
    final s = simplifyStroke(pts);
    expect(s.length, lessThanOrEqualTo(400));
    expect(s.first.x, 0);
    expect(s.last.x, pts.last.x);
    final item = SchemeItem(type: 'pen', x: 0, y: 0.5, points: s, color: '#FFFFFF');
    final back = SchemeItem.fromJson(item.toJson());
    expect(back.points!.length, s.length);
    expect(back.color, '#FFFFFF');
  });
}
