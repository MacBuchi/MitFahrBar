/// invite_text_test.dart – Einladungstext.
library;

import 'package:fahrgemeinschaft/core/invite_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nennt Gruppe, beide Wege in die App und den Zugang', () {
    final text = buildInviteText(
      groupName: 'Dacia Racing',
      handle: 'daciaracing',
    );

    expect(text, contains('Dacia Racing'));
    expect(text, contains(inviteApkUrl));
    expect(text, contains(inviteWebUrl));
    expect(text, contains('Zugang: daciaracing'));
  });

  test('ohne Passwort sagt der Text, dass es separat kommt', () {
    final text = buildInviteText(groupName: 'G', handle: 'g');

    expect(text, isNot(contains('Passwort:')));
    expect(text, contains('bekommst du von mir'));
  });

  test('leeres oder blankes Passwort zählt als keins', () {
    // Sonst stünde „Passwort: " ohne Wert in der Nachricht.
    for (final blank in ['', '   ', '\n']) {
      final text = buildInviteText(
        groupName: 'G',
        handle: 'g',
        password: blank,
      );
      expect(text, isNot(contains('Passwort:')), reason: 'Eingabe: „$blank"');
    }
  });

  test('mit Passwort steht es genau einmal drin', () {
    final text = buildInviteText(
      groupName: 'G',
      handle: 'g',
      password: '  geheim123 ',
    );

    expect(text, contains('Passwort: geheim123'));
    expect(
      'geheim123'.allMatches(text).length,
      1,
      reason: 'Doppelt genannt wäre nur eine weitere Stelle zum Übersehen.',
    );
    expect(text, isNot(contains('bekommst du von mir')));
  });

  test('die Pages-URL trägt das große F', () {
    // GitHub Pages ist groß-/kleinschreibungsempfindlich; mit kleinem f
    // landet die Eingeladene auf einer 404.
    expect(inviteWebUrl, contains('/Fahrgemeinschaft/'));
  });
}
