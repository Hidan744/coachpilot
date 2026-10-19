import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/ui/screens/library/library_screens.dart';
import 'package:coachpilot/ui/screens/library/scheme_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Drill drill(String id, {String cat = 'passing', int ageMin = 6, int playersMin = 2, List<String> eq = const []}) =>
    Drill(id: id, title: 'Упр $id', category: cat, ageMin: ageMin, playersMin: playersMin, equipment: eq, tags: const ['рондо']);

void main() {
  final team = Team(id: 't', name: 'U10', ageGroup: 'U10', level: 'amateur', defaultPlayers: 8, equipment: const ['bibs']);

  test('упражнение подходит команде по возрасту, составу и инвентарю', () {
    expect(drillFitsTeam(drill('a'), team), isTrue);
    expect(drillFitsTeam(drill('b', ageMin: 13), team), isFalse);
    expect(drillFitsTeam(drill('c', playersMin: 10), team), isFalse);
    expect(drillFitsTeam(drill('d', eq: ['ladder']), team), isFalse);
    expect(drillFitsTeam(drill('e', eq: ['balls', 'cones', 'bibs']), team), isTrue);
  });

  test('фильтр: поиск, категория, избранное, мои', () {
    final all = [drill('1'), drill('2', cat: 'finishing'), Drill(id: '3', title: 'Своё', category: 'game')];
    expect(applyFilter(all, const DrillFilter(query: 'рондо'), {}, null).length, 2);
    expect(applyFilter(all, const DrillFilter(category: 'finishing'), {}, null).single.id, '2');
    expect(applyFilter(all, const DrillFilter(tab: 'favorites'), {'1'}, null).single.id, '1');
    final sys = Drill(id: 's', title: 'Сис', category: 'game', source: 'system');
    expect(applyFilter([...all, sys], const DrillFilter(tab: 'mine'), {}, null).length, 3);
  });

  testWidgets('редактор схемы: ставим игрока, рисуем пас, отменяем, удаляем', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Scheme? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.push<Scheme>(
            context,
            MaterialPageRoute(builder: (_) => const SchemeEditorScreen()),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final canvas = find.byKey(const Key('scheme_canvas'));
    final box = tester.getRect(canvas);

    // Игрок синих: выбрать инструмент и коснуться поля.
    await tester.tap(find.bySemanticsLabel('Игрок (синие)'));
    await tester.pump();
    await tester.tapAt(box.center);
    await tester.pump();
    // Пас: протянуть.
    await tester.tap(find.bySemanticsLabel('Пас'));
    await tester.pump();
    await tester.dragFrom(box.topLeft + const Offset(60, 60), const Offset(200, 100));
    await tester.pumpAndSettle();
    // Ещё конус и отмена последнего действия.
    await tester.tap(find.bySemanticsLabel('Конус'));
    await tester.pump();
    await tester.tapAt(box.bottomRight - const Offset(50, 50));
    await tester.pump();
    await tester.tap(find.byTooltip('Отменить'));
    await tester.pump();
    // Выбрать игрока и передвинуть.
    await tester.tap(find.bySemanticsLabel('Выбор и перемещение'));
    await tester.pump();
    await tester.dragFrom(box.center, const Offset(-100, 0));
    await tester.pump();

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final items = result!.items;
    expect(items.map((e) => e.type), ['player_a', 'arrow_pass']);
    expect(items[0].label, '1');
    expect(items[0].x, lessThan(0.5)); // передвинут влево
    expect(items[1].x2! > items[1].x, isTrue);
  });
}
