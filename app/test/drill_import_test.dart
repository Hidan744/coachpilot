import 'package:coachpilot/core/drill_import.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '''
Упражнение 1. Квадрат 4 на 2
Цель: удержание мяча и открывание под пас.
Организация: квадрат 12×12 м, конусы по углам, манишки двух цветов.
Время: 12 мин. Игроков 6-10, возраст 10-13 лет.
1. Четверо по периметру держат мяч.
2. Двое в центре отбирают.
3. Потерявший мяч меняется с водящим.
Подсказки:
- открывайся до получения мяча
- пас в дальнюю ногу
Усложнение: два касания.

Удары после обводки
Цель — завершение атаки.
Игрок ведёт мяч, обводит стойку и бьёт по воротам. Вратарь в воротах. После удара подбирает мяч и встаёт в конец колонны.
''';

void main() {
  test('свободный текст: два упражнения с разделами и метаданными', () {
    final drills = parseDrillsFromText(sample);
    expect(drills, hasLength(2));
    final a = drills[0];
    expect(a.title, 'Квадрат 4 на 2');
    expect(a.category, 'possession');
    expect(a.goal, 'удержание мяча и открывание под пас.');
    expect(a.setup, contains('квадрат 12×12'));
    expect(a.steps, hasLength(3));
    expect(a.coachingPoints, ['открывайся до получения мяча', 'пас в дальнюю ногу']);
    expect(a.harder, ['два касания.']);
    expect(a.durationMin, 12);
    expect((a.playersMin, a.playersMax), (6, 10));
    expect((a.ageMin, a.ageMax), (10, 13));
    expect(a.equipment, containsAll(['cones', 'bibs']));

    final b = drills[1];
    expect(b.title, 'Удары после обводки');
    expect(b.category, 'finishing');
    expect(b.steps.length, greaterThanOrEqualTo(2), reason: 'длинный абзац делится на шаги по предложениям');
    expect(b.equipment, containsAll(['balls', 'poles', 'goals']));
    expect(b.equipment, isNot(contains('mini_goals')));
  });

  test('таблица: колонки «Название», «Описание», «Время», «Категория»', () {
    final drills = parseDrillsFromTable([
      ['Название', 'Категория', 'Описание', 'Время, мин', 'Игроки', 'Инвентарь'],
      ['Рондо 5×2', 'Владение', '1. Пять по кругу. 2. Двое в центре.', '15', '7-12', 'мячи, фишки'],
      ['Игра 4×4', '', 'Игра на мини-ворота', '20', '8-10', 'мини-ворота'],
    ]);
    expect(drills.map((d) => d.title), ['Рондо 5×2', 'Игра 4×4']);
    expect(drills[0].category, 'possession');
    expect(drills[0].steps, ['Пять по кругу.', 'Двое в центре.']);
    expect(drills[0].durationMin, 15);
    expect(drills[1].category, 'game');
    expect(drills[1].equipment, ['mini_goals']);
  });

  test('категория по ключевым словам', () {
    expect(guessCategory('Разминка с мячом'), 'warmup');
    expect(guessCategory('Пас в одно касание'), 'passing');
    expect(guessCategory('Что-то непонятное'), 'technique');
  });
}
