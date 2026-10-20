import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:coachpilot/core/file_import.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List docx(String bodyXml) {
  final xml = '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$bodyXml</w:body></w:document>';
  final a = Archive()..addFile(ArchiveFile('word/document.xml', utf8.encode(xml).length, utf8.encode(xml)));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

String p(String t) => '<w:p><w:r><w:t>$t</w:t></w:r></w:p>';
String tr(List<String> cells) => '<w:tr>${cells.map((c) => '<w:tc>${p(c)}</w:tc>').join()}</w:tr>';

void main() {
  test('Excel с заголовками: фамилия, имя, дата рождения, позиция, номер', () {
    final book = Excel.createExcel();
    final sheet = book['Sheet1'];
    sheet.appendRow([TextCellValue('№'), TextCellValue('Фамилия'), TextCellValue('Имя'), TextCellValue('Дата рождения'), TextCellValue('Позиция')]);
    sheet.appendRow([IntCellValue(7), TextCellValue('Петров'), TextCellValue('Саша'), TextCellValue('12.03.2014'), TextCellValue('нападающий')]);
    sheet.appendRow([IntCellValue(1), TextCellValue('Иванов'), TextCellValue('Миша'), IntCellValue(2013), TextCellValue('Вратарь')]);
    final players = parsePlayers(readTable('team.xlsx', Uint8List.fromList(book.encode()!)));
    expect(players.map((e) => e.fullName), ['Саша Петров', 'Миша Иванов']);
    expect(players[0].birthYear, 2014);
    expect(players[0].position, 'FW');
    expect(players[0].number, 7);
    expect(players[1].position, 'GK');
  });

  test('Word-список: ФИО, год, позиция, номер', () {
    final bytes = docx([
      p('1. Сидоров Иван Петрович, 2014, защитник, №4'),
      p('2. Кузнецова Анна 2015 пз'),
      p('3. Напалков Тимур 2014'),
    ].join());
    final players = parsePlayers(readTable('list.docx', bytes));
    expect(players.map((e) => e.fullName), ['Иван Сидоров', 'Анна Кузнецова', 'Тимур Напалков']);
    expect(players[0].number, 4);
    expect(players[0].position, 'DF');
    expect(players[1].position, 'MF');
    expect(players[2].position, isNull, reason: 'фамилия Напалков — не «нападающий»');
  });

  test('Word с таблицей ФИО', () {
    final bytes = docx('<w:tbl>${tr(['ФИО', 'Год рождения', 'Амплуа'])}${tr(['Петров Саша', '2014', 'вр'])}</w:tbl>');
    final players = parsePlayers(readTable('t.docx', bytes));
    expect(players.single.fullName, 'Саша Петров');
    expect(players.single.position, 'GK');
  });

  test('CSV с точкой с запятой и имя перед фамилией', () {
    final csv = 'Имя;Фамилия;Год\nПётр;Смирнов;2012\n';
    final players = parsePlayers(readTable('a.csv', Uint8List.fromList(utf8.encode(csv))));
    expect(players.single.fullName, 'Пётр Смирнов');
    expect(players.single.birthYear, 2012);
    final loose = parsePlayers(readTable('b.txt', Uint8List.fromList(utf8.encode('Пётр Смирнов 2012\nОлег Белов'))));
    expect(loose.map((e) => e.fullName), ['Пётр Смирнов', 'Олег Белов']);
  });

  test('понятные ошибки на неподдерживаемые форматы', () {
    expect(() => readTable('old.xls', Uint8List(0)), throwsA(isA<ImportException>()));
    expect(() => readTable('x.pdf', Uint8List(0)), throwsA(isA<ImportException>()));
    expect(() => readTable('bad.docx', Uint8List.fromList([1, 2, 3])), throwsA(isA<ImportException>()));
  });

  test('xlsx с абсолютными путями внутри (Google Таблицы, openpyxl) открывается', () {
    final bytes = File('test/fixtures/roster_absolute_paths.xlsx').readAsBytesSync();
    final players = parsePlayers(readTable('roster.xlsx', bytes));
    expect(players.length, 20);
    expect(players.first.fullName, 'Артём Ковалёв');
    expect(players.first.position, 'GK');
    expect(players.first.number, 1);
    expect(players.first.birthYear, 2010);
    expect(players.every((p) => p.position != null && p.number != null), isTrue);
  });
}
