import 'package:coachpilot/core/parent_report.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final player = Player(id: 'p', teamId: 't', firstName: 'Пётр', lastName: 'Сидоров');

  test('сообщение родителям содержит только открытое', () {
    final text = parentMessage(
      player: player,
      team: Team(id: 't', name: 'U12', ageGroup: 'U12', level: 'amateur', defaultPlayers: 12),
      present: 9,
      total: 10,
      coach: 'Иван',
      notes: [
        ParentNote(id: '1', playerId: 'p', category: 'nutrition', text: 'Завтрак за 2 часа', writtenAt: DateTime(2026, 10, 1)),
        ParentNote(id: '2', playerId: 'p', category: 'psychology', text: 'Секрет', writtenAt: DateTime(2026, 10, 2), shared: false),
      ],
      plans: [
        DevelopmentPlan(id: 'a', playerId: 'p', period: 'week', title: 'Левая нога', items: const [
          PlanItem(text: '100 передач', done: true),
          PlanItem(text: 'Приём левой', kind: 'goal'),
        ]),
        DevelopmentPlan(id: 'b', playerId: 'p', period: 'season', title: 'Скрытый', shared: false),
      ],
    );
    expect(text, contains('Пётр Сидоров · U12'));
    expect(text, contains('90% (9 из 10)'));
    expect(text, contains('Питание (01.10): Завтрак за 2 часа'));
    expect(text, contains('✅ 100 передач'));
    expect(text, contains('▫️ Цель: Приём левой'));
    expect(text, contains('Тренер: Иван'));
    expect(text, isNot(contains('Секрет')));
    expect(text, isNot(contains('Скрытый')));
  });

  test('даты периода плана', () {
    final wed = DateTime(2026, 10, 21);
    expect(periodRange('week', wed), (DateTime(2026, 10, 19), DateTime(2026, 10, 25)));
    expect(periodRange('month', wed), (DateTime(2026, 10, 1), DateTime(2026, 10, 31)));
    expect(periodRange('season', wed).$2, DateTime(2027, 5, 31));
    expect(periodRange('season', DateTime(2027, 2, 1)).$2, DateTime(2027, 5, 31));
  });

  test('json плана развития', () {
    final p = DevelopmentPlan(
      id: 'a',
      playerId: 'p',
      period: 'month',
      title: 'Скорость',
      startsOn: DateTime(2026, 10, 1),
      endsOn: DateTime(2026, 10, 31),
      focus: const ['physical'],
      items: const [PlanItem(text: 'Рывки', done: true)],
    );
    final j = p.toJson();
    expect(j['starts_on'], '2026-10-01');
    final back = DevelopmentPlan.fromJson('a', j);
    expect(back.items.single.done, isTrue);
    expect(back.endsOn, DateTime(2026, 10, 31));
    expect(back.focus, ['physical']);
  });
}
