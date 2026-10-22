import 'dart:convert';
import 'dart:io';

import 'package:coachpilot/core/export/plan_export.dart';
import 'package:coachpilot/core/export/scheme_image.dart';
import 'package:coachpilot/core/plan_context.dart';
import 'package:coachpilot/data/models.dart';
import 'package:coachpilot/ui/screens/calendar/match_review_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  final now = DateTime(2026, 10, 20, 12);
  final review = MatchReview(
    summary: 'Контролировали мяч, но мало моментов',
    conclusions: 'Медленный выход из обороны',
    tasks: const ['Выход из-под прессинга через опорника'],
    playerNotes: const {'p1': 'Хорошо открывался'},
    videoUrl: 'https://video.example/match',
    episodes: const [
      VideoEpisode(id: 'e2', t: 1530, tag: 'mistake', comment: 'Потеря в центре', players: ['p1', 'p2']),
      VideoEpisode(id: 'e1', t: 312, tag: 'goal', comment: 'Гол после стандарта', players: ['p2']),
    ],
  );
  final match = Match(id: 'm', teamId: 't', opponent: 'Динамо', startsAt: now.subtract(const Duration(days: 2)), scoreFor: 1, scoreAgainst: 1, review: review);

  test('таймкоды', () {
    expect(parseTimecode('12:35'), 755);
    expect(parseTimecode('1:02:10'), 3730);
    expect(parseTimecode('95'), 95);
    expect(parseTimecode('12:75'), isNull);
    expect(parseTimecode('abc'), isNull);
    expect(const VideoEpisode(id: 'x', t: 755).time, '12:35');
  });

  test('разбор матча сохраняется и не теряется при правке формы матча', () {
    final back = Match.fromJson('m', jsonDecode(jsonEncode(match.toJson())) as Json);
    expect(back.review.tasks, review.tasks);
    expect(back.review.episodes.map((e) => e.id), ['e2', 'e1']);
    expect(back.review.playerNotes['p1'], 'Хорошо открывался');
    final edited = Match(id: 'm', teamId: 't', opponent: 'Динамо-2', startsAt: match.startsAt).copyWith(review: back.review);
    expect(edited.review.summary, review.summary);
  });

  test('текст разбора и обратная связь игроку — эпизоды по времени, только его', () {
    final names = {'p1': 'Иван Петров', 'p2': 'Олег Сидоров'};
    final all = matchReviewText(match, names);
    expect(all.indexOf('5:12'), lessThan(all.indexOf('25:30')));
    expect(all, contains('Выход из-под прессинга'));
    final fb = playerFeedbackText(match, 'p1', names);
    expect(fb, contains('Иван Петров'));
    expect(fb, contains('Хорошо открывался'));
    expect(fb, contains('25:30'));
    expect(fb, isNot(contains('5:12 —')));
  });

  test('задачи после матча становятся приоритетами конструктора', () {
    final h = teamHistory(
      team: Team(id: 't', name: 'T', ageGroup: 'U14', level: 'amateur', defaultPlayers: 14),
      sessions: const [],
      reports: const {},
      attendance: const [],
      players: const [],
      matches: [match],
      now: now,
    );
    expect(h.priorities.single.text, 'Выход из-под прессинга через опорника');
    expect(h.priorities.single.source, contains('Динамо'));
  });

  test('схема доски рисуется в PNG и PDF', () async {
    const scheme = Scheme(field: 'half', items: [
      SchemeItem(type: 'player_a', x: 0.3, y: 0.5, label: '9'),
      SchemeItem(type: 'arrow_pass', x: 0.3, y: 0.5, x2: 0.6, y2: 0.4),
    ]);
    final png = await schemePng(scheme, width: 400);
    expect(png.sublist(1, 4), utf8.encode('PNG'));
    final fonts = PdfFonts(
      pw.Font.ttf(File('assets/fonts/Roboto_400.ttf').readAsBytesSync().buffer.asByteData()),
      pw.Font.ttf(File('assets/fonts/Roboto_700.ttf').readAsBytesSync().buffer.asByteData()),
      pw.Font.ttf(File('assets/fonts/Oswald_700Bold.ttf').readAsBytesSync().buffer.asByteData()),
    );
    final pdf = await boardPdf(TacticBoard(id: 'b', title: 'Прессинг', scheme: scheme, notes: 'Сдвиг к мячу'), fonts);
    expect(utf8.decode(pdf.sublist(0, 4)), '%PDF');
  });
}
