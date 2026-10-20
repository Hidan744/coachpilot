import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/ui/widgets/scheme_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('кнопка ▶ проигрывает шаги и не сбрасывается при пересборке экрана', (tester) async {
    const s = Scheme(field: 'grid', items: [
      SchemeItem(type: 'player_a', x: 0.2, y: 0.5),
      SchemeItem(type: 'ball', x: 0.22, y: 0.52),
      SchemeItem(type: 'player_a', x: 0.8, y: 0.5),
      SchemeItem(type: 'arrow_pass', x: 0.2, y: 0.5, x2: 0.8, y2: 0.5, step: 1),
      SchemeItem(type: 'arrow_pass', x: 0.8, y: 0.5, x2: 0.2, y2: 0.5, step: 2),
    ]);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: SchemeView(s)))));
    await tester.tap(find.byTooltip('Показать движение'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Шаг 1 из 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Шаг 2 из 2'), findsOneWidget);
    // родитель пересобирается с «новой», но такой же схемой — анимация не сбрасывается
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: SchemeView(Scheme.fromJson(s.toJson()))))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Шаг 2 из 2'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.replay), findsOneWidget);
  });
}
