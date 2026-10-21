import 'package:coachpilot/core/lineup.dart';
import 'package:coachpilot/core/performance.dart';
import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Player _p(String id, String pos) => Player(id: id, teamId: 't', firstName: id, lastName: id.toUpperCase(), position: pos);

MatchStat _s(String player, int match, Map<String, double> stats, {int minutes = 90, double? rating, bool started = true}) =>
    MatchStat(id: '$player-$match', matchId: 'm$match', playerId: player, minutes: minutes, rating: rating, started: started, stats: stats);

void main() {
  final now = DateTime(2026, 10, 21, 12);

  test('роли мест в схеме', () {
    String keys(String f) => slotRoles(f).map((r) => r.key).join(' ');
    expect(keys('4-3-3'), 'gk fb cb cb fb cm dm cm wf st wf');
    expect(keys('4-2-3-1'), 'gk fb cb cb fb dm dm wm am wm st');
    expect(keys('3-5-2'), 'gk cb cb cb wm cm dm cm wm st st');
    expect(keys('4-4-2'), 'gk fb cb cb fb wm cm cm wm st st');
    expect(slotRoles('2-3-1').length, 7);
  });

  test('готовность: травма, дисквалификация, усталость', () {
    final p = _p('a', 'MF');
    expect(readiness(p, matches: const [], attendance: [(now.subtract(const Duration(days: 3)), 'injured')], now: now).unavailable,
        contains('Травма'));
    // Травма, после которой игрок уже тренировался, не мешает.
    expect(
        readiness(p,
                matches: const [],
                attendance: [(now.subtract(const Duration(days: 6)), 'injured'), (now.subtract(const Duration(days: 2)), 'present')],
                now: now)
            .unavailable,
        isNull);
    expect(readiness(p, matches: [(now.subtract(const Duration(days: 4)), _s('a', 1, {'red': 1}))], attendance: const [], now: now).unavailable,
        contains('красная'));
    final tired = readiness(p, matches: [(now.subtract(const Duration(days: 2)), _s('a', 1, {}))], attendance: const [], now: now);
    expect(tired.unavailable, isNull);
    expect(tired.adjust, lessThan(0));
    expect(tired.tired, isTrue);
  });

  test('стиль игры меняет выбор: прессинг — бегущий, владение — точный', () {
    final runner = _p('run', 'MF'), passer = _p('pas', 'MF'), filler = _p('fil', 'MF');
    final season = seasonStats([
      for (var m = 0; m < 3; m++) ...[
        _s('run', m, {'tackles': 4, 'recoveries': 6, 'sprints': 30, 'distance': 12, 'passes': 30, 'passes_ok': 21, 'losses': 5}),
        _s('pas', m, {'tackles': 1, 'recoveries': 2, 'sprints': 10, 'distance': 9.5, 'passes': 60, 'passes_ok': 56, 'losses': 1}),
        _s('fil', m, {'tackles': 2, 'recoveries': 3, 'sprints': 18, 'distance': 10.5, 'passes': 40, 'passes_ok': 32, 'losses': 3}),
      ],
    ]);
    final cm = roles['cm']!;
    final press = RoleScorer(season, style: 'press'), possession = RoleScorer(season, style: 'possession');
    expect(press.fit(runner, cm).score, greaterThan(press.fit(passer, cm).score));
    expect(possession.fit(passer, cm).score, greaterThan(possession.fit(runner, cm).score));
    expect(possession.fit(passer, cm).reasons.join(' '), contains('точность передач'));
    expect(press.fit(filler, roles['gk']!).warnings, contains('Не вратарь'));
  });

  test('подбор состава: вратарь в воротах, травмированный на трибуне, у мест есть замена', () {
    final players = [
      _p('gk1', 'GK'), _p('gk2', 'GK'),
      for (var i = 0; i < 5; i++) _p('df$i', 'DF'),
      for (var i = 0; i < 5; i++) _p('mf$i', 'MF'),
      for (var i = 0; i < 3; i++) _p('fw$i', 'FW'),
    ];
    final season = seasonStats([
      _s('gk1', 1, {'saves': 5, 'conceded': 1}, rating: 7.2),
      _s('gk2', 2, {'saves': 2, 'conceded': 3}, rating: 6.0),
      for (var i = 0; i < 5; i++) _s('df$i', 1, {'tackles': 2.0 + i, 'interceptions': 1.0 + i, 'duels': 8, 'duels_won': 3.0 + i}),
      for (var i = 0; i < 5; i++) _s('mf$i', 1, {'passes': 40.0 + i * 5, 'passes_ok': 30.0 + i * 5, 'key_passes': i.toDouble()}),
      for (var i = 0; i < 3; i++) _s('fw$i', 1, {'goals': i.toDouble(), 'shots': 3, 'shots_on': 1.0 + i}),
    ]);
    final ready = {
      for (final p in players) p.id: Readiness(),
      'df4': Readiness(unavailable: 'Травма (отмечено 19.10)'),
    };
    final l = suggestLineup(formation: '4-3-3', style: 'press', players: players, season: season, ready: ready);
    expect(l.picks.length, 11);
    expect(l.picks.first.player!.id, 'gk1');
    expect(l.players.whereType<Player>().map((p) => p.id), isNot(contains('df4')));
    expect(l.unavailable.single.$1.id, 'df4');
    expect(l.players.whereType<Player>().toSet().length, 11);
    expect(l.bench.map((b) => b.$1.id), contains('gk2'));
    expect(l.picks.first.alternatives.first.$1.id, 'gk2');
    expect(l.strength, inInclusiveRange(1, 100));
  });

  test('замены: карточка и фолы — та же позиция; проигрываем — больше атаки', () {
    final mf = _p('mf', 'MF'), df = _p('df', 'DF'), benchMf = _p('bmf', 'MF'), benchFw = _p('bfw', 'FW');
    final season = seasonStats([
      _s('bmf', 1, {'passes': 50, 'passes_ok': 45, 'key_passes': 2}),
      _s('bfw', 1, {'goals': 2, 'shots': 5, 'shots_on': 3}),
    ]);
    final ready = {for (final p in [mf, df, benchMf, benchFw]) p.id: Readiness()};
    final live = {'mf': _s('mf', 9, {'yellow': 1, 'fouls': 2}), 'df': _s('df', 9, {'tackles': 2})};

    final level = substitutionAdvice(
        onField: [mf, df], bench: [benchMf, benchFw], live: live, minute: 50, ourGoals: 1, theirGoals: 1, season: season, ready: ready);
    expect(level.first.out.id, 'mf');
    expect(level.first.into!.id, 'bmf');
    expect(level.first.why.first, contains('Жёлтая'));

    final losing = substitutionAdvice(
        onField: [mf, df], bench: [benchMf, benchFw], live: {'df': _s('df', 9, {'tackles': 2})}, minute: 70, ourGoals: 0, theirGoals: 1,
        season: season, ready: ready);
    expect(losing, isNotEmpty);
    expect(losing.first.into!.id, 'bfw');
    expect(losing.first.plan, contains('больше атаки'));
  });

  test('кто на поле по статистике матча', () {
    expect(onFieldNow(_s('a', 1, {}), 90), isTrue);
    expect(onFieldNow(_s('a', 1, {}, minutes: 60), 90), isFalse); // заменён
    expect(onFieldNow(_s('a', 1, {}, minutes: 30, started: false), 90), isTrue); // вышел на замену
    expect(onFieldNow(_s('a', 1, {'red': 1}), 90), isFalse);
    expect(onFieldNow(null, 90), isFalse);
  });
}
