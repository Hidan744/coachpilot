import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/export/plan_export.dart';
import 'package:coachpilot/core/plan_rules.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  final bundle = jsonDecode(File('assets/catalog.json').readAsStringSync()) as Json;
  final library = (bundle['drills'] as List).cast<Json>().map((r) => Drill.fromJson(r['id'] as String, r['data'] as Json)).toList();
  Team team(String age, int players) => Team(
        id: 't',
        name: 'T',
        ageGroup: age,
        level: 'amateur',
        defaultPlayers: players,
        equipment: const ['balls', 'cones', 'bibs', 'goals', 'mini_goals'],
      );

  /// Секунды работы и отдыха из строки дозировки — должны давать длительность блока.
  int dosageSeconds(String d) {
    if (!d.contains('серии')) return int.parse(RegExp(r'(\d+) мин').firstMatch(d)!.group(1)!) * 60;
    int sec(String s) {
      final m = RegExp(r'(\d+) мин').firstMatch(s), c = RegExp(r'(\d+) с').firstMatch(s);
      return (m == null ? 0 : int.parse(m.group(1)!) * 60) + (c == null ? 0 : int.parse(c.group(1)!));
    }
    final series = int.parse(RegExp(r'^(\d+) серии').firstMatch(d)!.group(1)!);
    final work = sec(RegExp(r'× ([^,]+),').firstMatch(d)!.group(1)!);
    final rest = sec(RegExp(r'отдых ([^м]+мин|\d+ с)').firstMatch(d)!.group(1)!);
    final extra = RegExp(r'последняя \+([^)]+)\)').firstMatch(d);
    return series * work + (series - 1) * rest + (extra == null ? 0 : sec(extra.group(1)!));
  }

  for (final format in ['team', 'group', 'individual']) {
    for (final intensity in ['low', 'medium', 'high']) {
      for (final duration in [30, 60, 90, 120]) {
        test('конструктор: $format, $intensity, $duration мин — сумма и дозировка сходятся', () {
          final players = format == 'individual' ? 2 : 14;
          final blocks = planByRules(
            library: library,
            team: team('U14', players),
            players: players,
            durationMin: duration,
            goal: 'Передачи и открывания',
            format: format,
            intensity: intensity,
          );
          expect(blocks, isNotEmpty);
          expect(blocks.fold<int>(0, (a, b) => a + b.durationMin), duration);
          for (final b in blocks) {
            expect(b.why, isNotEmpty, reason: b.title);
            expect(dosageSeconds(b.dosage), b.durationMin * 60, reason: '${b.title}: ${b.dosage}');
          }
          if (format == 'individual') {
            expect(blocks.where((b) => b.phase == 'game'), isEmpty);
            expect(blocks.every((b) => b.drillSnapshot!.playersMin <= 4), isTrue);
          }
        });
      }
    }
  }

  test('акцент на позиции и уровень: защитники — оборона, начальный уровень — упрощённый вариант', () {
    final blocks = planByRules(
      library: library,
      team: team('U14', 14),
      players: 14,
      durationMin: 90,
      goal: 'Игра в обороне',
      positions: const ['DF'],
      level: 'beginner',
    );
    final main = blocks.where((b) => b.phase == 'main').toList();
    expect(main.any((b) => b.drillSnapshot!.category == 'defending'), isTrue);
    expect(main.first.why, contains('Цель «Игра в обороне»'));
    expect(main.any((b) => b.variant == 'easier'), isTrue);
  });

  test('интенсивность влияет на выбор упражнений основной части', () {
    String ints(String i) => planByRules(
          library: library,
          team: team('U14', 14),
          players: 14,
          durationMin: 90,
          goal: 'Передачи',
          intensity: i,
        ).where((b) => b.phase == 'main').map((b) => b.drillSnapshot!.intensity).join(',');
    expect(ints('high'), isNot(ints('low')));
  });

  test('похожее упражнение: та же категория, не из плана', () {
    final blocks = planByRules(library: library, team: team('U12', 12), players: 12, durationMin: 60, goal: 'Удары по воротам');
    final main = blocks.firstWhere((b) => b.phase == 'main');
    final d = similarDrill(
      library: library,
      block: main,
      team: team('U12', 12),
      players: 12,
      inPlan: {for (final b in blocks) ?b.drillId},
    );
    expect(d, isNotNull);
    expect(d!.category, main.drillSnapshot!.category);
    expect(blocks.map((b) => b.drillId), isNot(contains(d.id)));
  });

  test('экспорт: текст и PDF с кириллицей', () async {
    final blocks = planByRules(library: library, team: team('U12', 12), players: 12, durationMin: 75, goal: 'Передачи', intensity: 'high');
    final s = TrainingSession(
      id: 's',
      title: 'Передачи в одно касание',
      goal: 'Передачи',
      durationMin: 75,
      blocks: [blocks.first.copyWith(variant: 'easier'), ...blocks.skip(1)],
      params: const {'format': 'group', 'intensity': 'high', 'level': 'amateur', 'positions': ['MF']},
    );
    final text = planAsText(s);
    expect(text, contains('Цель: Передачи'));
    expect(text, contains('Групповая тренировка · интенсивность высокая'));
    expect(text, contains('Итого: 75 мин из 75'));
    expect(text, contains('Почему:'));
    final fonts = PdfFonts(
      pw.Font.ttf(File('assets/fonts/Roboto_400.ttf').readAsBytesSync().buffer.asByteData()),
      pw.Font.ttf(File('assets/fonts/Roboto_700.ttf').readAsBytesSync().buffer.asByteData()),
      pw.Font.ttf(File('assets/fonts/Oswald_700Bold.ttf').readAsBytesSync().buffer.asByteData()),
    );
    final pdf = await planPdf(s, fonts);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(10000));
  });

  test('блок плана: новые поля сохраняются и читаются', () {
    const b = TrainingBlock(id: 'b1', phase: 'main', title: 'X', durationMin: 10, why: 'потому что', dosage: '2 серии', variant: 'harder');
    final back = TrainingBlock.fromJson(b.toJson());
    expect([back.why, back.dosage, back.variant], ['потому что', '2 серии', 'harder']);
    expect(TrainingBlock.fromJson(const TrainingBlock(id: 'b', phase: 'main', title: 'Y', durationMin: 5).toJson()).variant, 'base');
  });
}
