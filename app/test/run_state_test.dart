import 'package:coachpilot/core/run_state.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const blocks = [
    TrainingBlock(id: 'a', phase: 'warmup', title: 'Р', durationMin: 10),
    TrainingBlock(id: 'b', phase: 'main', title: 'О', durationMin: 20),
    TrainingBlock(id: 'c', phase: 'game', title: 'И', durationMin: 15),
  ];
  final t0 = DateTime(2026, 10, 20, 18);
  DateTime at(int sec) => t0.add(Duration(seconds: sec));

  test('таймер считает по меткам времени и учитывает паузу', () {
    final r = RunState()..start(t0);
    expect(r.remaining(blocks[0], at(90)), const Duration(minutes: 8, seconds: 30));
    r.pause(at(120));
    // пауза 5 минут не идёт в зачёт
    expect(r.elapsed(at(420)), const Duration(seconds: 120));
    r.start(at(420));
    expect(r.elapsed(at(480)), const Duration(seconds: 180));
  });

  test('перебор времени — отрицательный остаток, формат +мм:сс', () {
    final r = RunState()..start(t0);
    final rem = r.remaining(blocks[0], at(10 * 60 + 35));
    expect(rem.isNegative, isTrue);
    expect(formatClock(rem), '+00:35');
    expect(formatClock(const Duration(minutes: 9, seconds: 5)), '09:05');
  });

  test('±1 минута меняет план блока, но не меньше 1 минуты', () {
    final r = RunState();
    r.adjust(blocks[0], 2);
    expect(r.planned(blocks[0]), const Duration(minutes: 12));
    for (var i = 0; i < 20; i++) {
      r.adjust(blocks[0], -1);
    }
    expect(r.planned(blocks[0]), const Duration(minutes: 1));
  });

  test('переходы, пропуск, возврат, завершение и фактическое время', () {
    final r = RunState()..start(t0);
    expect(r.next(blocks, at(600)), isFalse); // 10 мин разминки
    expect(r.index, 1);
    expect(r.running, isTrue);
    expect(r.next(blocks, at(660), skip: true), isFalse);
    expect(r.skipped, {'b'});
    r.back(blocks, at(670)); // ошибочно пропустили — вернулись
    expect(r.index, 1);
    expect(r.skipped, isEmpty);
    expect(r.elapsed(at(670)), const Duration(seconds: 60));
    expect(r.next(blocks, at(1800)), isFalse);
    expect(r.next(blocks, at(2700)), isTrue);
    expect(r.finished, isTrue);
    expect(r.actualSec, {'a': 600, 'b': 1190, 'c': 900});
  });

  test('сохранение и восстановление состояния (перезапуск приложения)', () {
    final r = RunState()..start(t0);
    r.adjust(blocks[0], 1);
    r.next(blocks, at(300), skip: true);
    final back = RunState.decode(r.encode());
    expect(back.index, 1);
    expect(back.startedAtMs, at(300).millisecondsSinceEpoch);
    expect(back.extraMin, {'a': 1});
    expect(back.skipped, {'a'});
    // время продолжает идти после «перезапуска»
    expect(back.elapsed(at(360)), const Duration(seconds: 60));
  });
}
