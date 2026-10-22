// Тактическая схема в картинку и PDF — без экрана, тем же рисованием, что и на доске.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models.dart';
import '../../ui/widgets/scheme_view.dart';
import 'plan_export.dart' show PdfFonts;

/// PNG схемы шириной [width] пикселей; высота — по пропорциям поля.
Future<Uint8List> schemePng(Scheme scheme, {double width = 1400}) async {
  final size = Size(width, width / fieldAspect(scheme.field));
  final recorder = ui.PictureRecorder();
  SchemePainter(scheme).paint(Canvas(recorder), size);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// PDF доски: название, расстановка, схема и заметки — для печати и раздачи игрокам.
Future<Uint8List> boardPdf(TacticBoard b, PdfFonts f) async {
  final png = await schemePng(b.scheme, width: 1600);
  final doc = pw.Document(title: b.title, author: 'CoachPilot AI');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(b.title, style: pw.TextStyle(font: f.display, fontSize: 22)),
      if (b.formation.isNotEmpty) pw.Text('Схема: ${b.formation}', style: pw.TextStyle(font: f.regular, fontSize: 11)),
      pw.SizedBox(height: 12),
      pw.Expanded(child: pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain))),
      if (b.notes.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        pw.Text(b.notes, style: pw.TextStyle(font: f.regular, fontSize: 11)),
      ],
    ]),
  ));
  return doc.save();
}
