import 'dart:convert';

import 'package:coachpilot/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Team t(String age, [String? kind]) => Team(id: 't', name: 'T', ageGroup: age, level: 'amateur', defaultPlayers: 14, kind: kind);

  test('тип команды по возрасту, если тренер не задал', () {
    expect(t('U9').profile, 'kids');
    expect(t('U16').profile, 'youth');
    expect(t('adult').profile, 'amateur');
    expect(t('adult', 'individual').profile, 'individual');
  });

  test('функции по типу команды', () {
    expect(t('U12').hasParents, isTrue);
    expect(t('adult').hasParents, isFalse);
    expect(t('U17', 'academy').hasParents, isTrue);
    expect(t('adult', 'individual').hasMatches, isFalse);
    expect(t('U12').hasMatches, isTrue);
  });

  test('тип команды и согласие родителя сохраняются', () {
    final team = Team.fromJson('t', jsonDecode(jsonEncode(t('U14', 'academy').toJson())) as Json);
    expect(team.kind, 'academy');
    final p = Player(id: 'p', teamId: 't', firstName: 'Миша', consent: ParentConsent(given: true, by: 'Мама', on: DateTime(2026, 9, 1)));
    final back = Player.fromJson('p', jsonDecode(jsonEncode(p.toJson())) as Json);
    expect(back.consent.given, isTrue);
    expect(back.consent.by, 'Мама');
    expect(back.consent.on, DateTime(2026, 9, 1));
  });
}
