// Экспорт плана тренировки: текст для мессенджера и PDF для печати.
// Содержимое берётся из плана как есть: блоки, тайминг, снимки упражнений, пояснения конструктора.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models.dart';
import '../plan_rules.dart';
import '../session_summary.dart';

String _clock(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String _when(DateTime? d) => d == null ? 'Без даты' : DateFormat('d MMMM y, HH:mm', 'ru').format(d);

/// Параметры конструктора одной строкой: формат, интенсивность, уровень.
String planParamsLine(TrainingSession s) {
  final p = s.params;
  return [
    if (formatLabels[p['format']] != null) '${formatLabels[p['format']]} тренировка',
    if (intensityLabels[p['intensity']] != null) 'интенсивность ${intensityLabels[p['intensity']]!.toLowerCase()}',
    if (Levels.all[p['level']] != null) 'уровень ${Levels.all[p['level']]!.toLowerCase()}',
    if ((p['positions'] as List?)?.isNotEmpty ?? false)
      'акцент: ${(p['positions'] as List).map((x) => (Positions.all[x] ?? '$x').toLowerCase()).join(', ')}',
  ].join(' · ');
}

/// Какие пункты варианта сложности действуют для блока.
List<String> variantLines(TrainingBlock b) {
  final d = b.drillSnapshot;
  if (d == null) return const [];
  return switch (b.variant) {
    'easier' => d.easier,
    'harder' => d.harder,
    _ => const [],
  };
}

const variantLabels = {'base': 'Базовый', 'easier': 'Проще', 'harder': 'Сложнее'};

/// План текстом — скопировать в мессенджер или заметки.
String planAsText(TrainingSession s, {Team? team}) {
  final out = StringBuffer()
    ..writeln(s.title)
    ..writeln([_when(s.scheduledAt), if (team != null) team.name, '${s.durationMin} мин'].join(' · '));
  if (s.goal.isNotEmpty) out.writeln('Цель: ${s.goal}');
  final params = planParamsLine(s);
  if (params.isNotEmpty) out.writeln(params);
  out.writeln();
  var start = 0;
  for (final b in s.blocks) {
    final d = b.drillSnapshot;
    out.writeln('${_clock(start)} · ${Phases.all[b.phase]} · ${b.title} — ${b.durationMin} мин');
    if (b.dosage.isNotEmpty) out.writeln('  Дозировка: ${b.dosage}');
    if (d != null && d.fieldSize.isNotEmpty) out.writeln('  Площадка: ${d.fieldSize}; игроков: от ${d.playersMin}');
    if (d != null && d.equipment.isNotEmpty) {
      out.writeln('  Инвентарь: ${d.equipment.map((e) => Equipment.all[e] ?? e).join(', ')}');
    }
    if (b.why.isNotEmpty) out.writeln('  Почему: ${b.why}');
    if (d != null) {
      for (final st in d.steps) {
        out.writeln('  • $st');
      }
      if (d.coachingPoints.isNotEmpty) out.writeln('  Подсказки: ${d.coachingPoints.join('; ')}');
      if (d.successCriteria.isNotEmpty) out.writeln('  Успех: ${d.successCriteria.join('; ')}');
    }
    final v = variantLines(b);
    if (v.isNotEmpty) out.writeln('  ${variantLabels[b.variant]}: ${v.join('; ')}');
    if (b.notes.isNotEmpty) out.writeln('  Заметка: ${b.notes}');
    start += b.durationMin;
  }
  out.writeln();
  out.write('Итого: $start мин из ${s.durationMin}');
  return out.toString();
}

/// Шрифты PDF: обычный, жирный и заголовочный (кириллица).
class PdfFonts {
  const PdfFonts(this.regular, this.bold, this.display);

  final pw.Font regular, bold, display;
}

// В шрифтах нет стрелки — заменяем на тире, чтобы в PDF не было пустых квадратов.
String _t(String s) => s.replaceAll('→', '—').replaceAll('←', '—');

/// План в PDF A4: шапка, тайминг по блокам, карточки упражнений с инструкциями.
Future<Uint8List> planPdf(TrainingSession s, PdfFonts f, {Team? team, String coach = ''}) async {
  final red = PdfColor.fromInt(0xFFE30613), muted = PdfColor.fromInt(0xFF5A5A63);
  pw.TextStyle st({double size = 10, bool bold = false, PdfColor? color}) =>
      pw.TextStyle(font: bold ? f.bold : f.regular, fontSize: size, color: color);
  pw.Widget label(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 5, bottom: 1),
        child: pw.Text(text.toUpperCase(), style: st(size: 7.5, bold: true, color: muted)),
      );
  pw.Widget bullets(List<String> items) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [for (final i in items) pw.Bullet(text: _t(i), style: st(size: 9.5), bulletSize: 3, margin: const pw.EdgeInsets.only(top: 1))],
      );

  final doc = pw.Document(title: s.title, author: coach.isEmpty ? 'CoachPilot AI' : coach);
  var start = 0;
  final rows = <List<String>>[];
  for (final b in s.blocks) {
    rows.add([_clock(start), Phases.all[b.phase]!, _t(b.title), '${b.durationMin}']);
    start += b.durationMin;
  }
  final total = start;
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    footer: (c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('CoachPilot AI${coach.isEmpty ? '' : ' · $coach'}', style: st(size: 8, color: muted)),
      pw.Text('${c.pageNumber} / ${c.pagesCount}', style: st(size: 8, color: muted)),
    ]),
    build: (c) => [
      pw.Text(_t(s.title), style: pw.TextStyle(font: f.display, fontSize: 22)),
      pw.SizedBox(height: 2),
      pw.Text([_when(s.scheduledAt), if (team != null) team.name, '${s.durationMin} мин'].join(' · '), style: st(color: muted)),
      if (s.goal.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('Цель: ${_t(s.goal)}', style: st(size: 11, bold: true))),
      if (planParamsLine(s).isNotEmpty) pw.Text(planParamsLine(s), style: st(color: muted)),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: ['Начало', 'Часть', 'Упражнение', 'Мин'],
        data: [
          ...rows,
          ['', '', 'Итого', '$total'],
        ],
        headerStyle: st(size: 9, bold: true, color: PdfColors.white),
        headerDecoration: pw.BoxDecoration(color: red),
        cellStyle: st(size: 9.5),
        cellAlignments: {0: pw.Alignment.centerLeft, 3: pw.Alignment.centerRight},
        columnWidths: {0: const pw.FixedColumnWidth(48), 1: const pw.FixedColumnWidth(90), 3: const pw.FixedColumnWidth(36)},
      ),
      if (total != s.durationMin)
        pw.Text('Сумма блоков $total мин, занятие ${s.durationMin} мин — проверьте тайминг.', style: st(color: red)),
      pw.SizedBox(height: 8),
      for (final b in s.blocks) ...[
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: red, width: 3))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${Phases.all[b.phase]!.toUpperCase()} · ${b.durationMin} МИН', style: st(size: 8, bold: true, color: red)),
            pw.Text(_t(b.title), style: st(size: 13, bold: true)),
            if (b.dosage.isNotEmpty) pw.Text('Дозировка: ${_t(b.dosage)}', style: st(size: 9.5)),
            if (b.why.isNotEmpty) ...[label('Почему это упражнение'), pw.Text(_t(b.why), style: st(size: 9.5))],
            ...() {
              final d = b.drillSnapshot;
              if (d == null) return <pw.Widget>[];
              return <pw.Widget>[
                pw.Text(
                  [
                    if (d.fieldSize.isNotEmpty) 'Площадка: ${d.fieldSize}',
                    'Игроков: ${d.playersMin}–${d.playersMax}',
                    if (d.equipment.isNotEmpty) 'Инвентарь: ${d.equipment.map((e) => Equipment.all[e] ?? e).join(', ')}',
                  ].join(' · '),
                  style: st(size: 9, color: muted),
                ),
                if (d.setup.isNotEmpty) ...[label('Организация'), pw.Text(_t(d.setup), style: st(size: 9.5))],
                if (d.steps.isNotEmpty) ...[label('Выполнение'), bullets(d.steps)],
                if (d.rules.isNotEmpty) ...[label('Правила'), bullets(d.rules)],
                if (d.coachingPoints.isNotEmpty) ...[label('Подсказки тренера'), bullets(d.coachingPoints)],
                if (d.successCriteria.isNotEmpty) ...[label('Критерии успеха'), bullets(d.successCriteria)],
                if (d.easier.isNotEmpty) ...[label(b.variant == 'easier' ? 'Проще (выбрано)' : 'Проще'), bullets(d.easier)],
                if (d.harder.isNotEmpty) ...[label(b.variant == 'harder' ? 'Сложнее (выбрано)' : 'Сложнее'), bullets(d.harder)],
              ];
            }(),
            if (b.notes.isNotEmpty) ...[label('Заметка тренера'), pw.Text(_t(b.notes), style: st(size: 9.5))],
          ]),
        ),
      ],
    ],
  ));
  return doc.save();
}

/// Загрузить шрифты PDF из ресурсов приложения.
Future<PdfFonts> loadPdfFonts() async => PdfFonts(
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto_400.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto_700.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/Oswald_700Bold.ttf')),
    );


/// Отчёт о занятии в PDF: сводка с основаниями, комментарии по игрокам, предложения AI отдельно.
Future<Uint8List> reportPdf(TrainingSession s, SessionReport? r, SessionSummary sum, Map<String, String> names, PdfFonts f) async {
  final red = PdfColor.fromInt(0xFFE30613), muted = PdfColor.fromInt(0xFF5A5A63);
  pw.TextStyle st({double size = 10, bool bold = false, PdfColor? color}) =>
      pw.TextStyle(font: bold ? f.bold : f.regular, fontSize: size, color: color);
  pw.Widget group(String title, List<SummaryItem> items) => items.isEmpty
      ? pw.SizedBox()
      : pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title.toUpperCase(), style: st(size: 9, bold: true, color: red)),
            for (final i in items)
              pw.Bullet(
                text: _t(i.text) + (i.basis.isEmpty ? '' : '  [${i.basis}]'),
                style: st(size: 10),
                bulletSize: 3,
              ),
          ]),
        );
  final doc = pw.Document(title: 'Отчёт: ${s.title}', author: 'CoachPilot AI');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    build: (c) => [
      pw.Text('Отчёт о занятии', style: st(size: 9, bold: true, color: muted)),
      pw.Text(_t(s.title), style: pw.TextStyle(font: f.display, fontSize: 22)),
      pw.Text(
        [
          _when(s.finishedAt ?? s.scheduledAt),
          '${s.durationMin} мин',
          if (r?.rating != null) 'оценка ${r!.rating} из 5',
          if (r?.rpe != null) 'нагрузка RPE ${r!.rpe}',
        ].join(' · '),
        style: st(color: muted),
      ),
      if (s.goal.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('Цель: ${_t(s.goal)}', style: st(size: 11, bold: true))),
      group('Выполнено', sum.achieved),
      group('Не выполнено', sum.notDone),
      group('Проблемы', sum.problems),
      if (r != null && r.playerNotes.isNotEmpty)
        group('По игрокам', [for (final e in r.playerNotes.entries) SummaryItem('${names[e.key] ?? 'Игрок'}: ${e.value}')]),
      group('На следующее занятие', sum.next),
      if (r != null && r.aiSuggestions.isNotEmpty)
        group('Предложения AI (не наблюдения тренера)', [for (final x in r.aiSuggestions) SummaryItem(x)]),
      group('Не хватает данных', [for (final m in sum.missingData) SummaryItem(m)]),
    ],
  ));
  return doc.save();
}
