import 'package:coachpilot/core/scheme_animation.dart';
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

  testWidgets('редактор схемы: игрок с мячом, ведение по точкам, пас партнёру, отмена', (tester) async {
    tester.view.physicalSize = const Size(800, 1500);
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
    // Поле меняет размер, когда появляются панели инструментов, — считаем координаты каждый раз.
    Offset at(double x, double y) {
      final box = tester.getRect(canvas);
      return Offset(box.left + box.width * x, box.top + box.height * y);
    }

    // Два игрока: A внизу слева, B справа.
    await tester.tap(find.bySemanticsLabel('Игрок (красные)'));
    await tester.pump();
    await tester.tapAt(at(0.2, 0.8));
    await tester.pump();
    await tester.tapAt(at(0.8, 0.5));
    await tester.pump();
    // Мяч у игрока A.
    await tester.tap(find.bySemanticsLabel('Мяч'));
    await tester.pump();
    await tester.tapAt(at(0.21, 0.81));
    await tester.pump();
    // Второй мяч тому же игроку не ставится.
    await tester.tapAt(at(0.2, 0.8));
    await tester.pump();
    expect(find.text('У этого игрока уже есть мяч'), findsOneWidget);

    // Движение: A ведёт мяч по двум точкам.
    await tester.tap(find.bySemanticsLabel('Движение игрока'));
    await tester.pump();
    await tester.tapAt(at(0.2, 0.8));
    await tester.pump();
    expect(find.textContaining('Ведение'), findsWidgets);
    await tester.tapAt(at(0.35, 0.6));
    await tester.pump();
    await tester.tapAt(at(0.5, 0.45));
    await tester.pump();
    expect(find.text('Точек: 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(find.textContaining('Точек'), findsNothing);

    // Шаг 2: A (уже в новой точке) отдаёт пас B.
    await tester.tapAt(at(0.5, 0.45));
    await tester.pump();
    await tester.tap(find.text('Пас'));
    await tester.pump();
    await tester.tapAt(at(0.8, 0.5));
    await tester.pump();

    // Конус и отмена.
    await tester.tap(find.bySemanticsLabel('Конус'));
    await tester.pump();
    await tester.tapAt(at(0.9, 0.9));
    await tester.pump();
    await tester.tap(find.byTooltip('Отменить').first);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Готово'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    final items = result!.items;
    expect(items.map((e) => e.type), ['player_a', 'player_a', 'ball', 'arrow_dribble', 'arrow_pass']);
    final a = items[0], b = items[1], ball = items[2], dribble = items[3], pass = items[4];
    expect(a.id, isNotNull);
    expect(ball.holder, a.id);
    expect(dribble.actor, a.id);
    expect(dribble.points!.length, 3);
    expect(dribble.step, 1);
    expect(pass.actor, a.id);
    expect(pass.target, b.id);
    expect(pass.step, 2);

    // Проигрывание: игрок доходит до последней точки, мяч в итоге у B, второго мяча нет.
    final anim = SchemeAnimation(result!);
    final end = anim.positionsAt(2);
    expect((end[0]! - const Offset(0.5, 0.45)).distance, lessThan(0.01));
    expect((end[2]! - (Offset(b.x, b.y) + ballOffset)).distance, lessThan(0.01));
    expect(anim.virtualKeys, isEmpty);
  });
}
