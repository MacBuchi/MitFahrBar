/// invite_flow_test.dart – Jemanden einladen, über die echte App.
///
/// Der Text selbst hängt an `invite_text_test.dart`. Hier geht es um das,
/// was am Weitergeben eines Passworts heikel ist: dass man vorher sieht, was
/// rausgeht — und dass es nirgends hängen bleibt, wo es später auftaucht.
library;

import 'package:fahrgemeinschaft/core/log.dart';
import 'package:fahrgemeinschaft/core/share_outcome.dart';
import 'package:fahrgemeinschaft/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _password = 'streng-geheim-42';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

FakeBackend _backend() {
  final backend = FakeBackend();
  backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  return backend;
}

Future<void> _openInvite(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Jemanden einladen'));
  await tester.pumpAndSettle();
}

/// Fängt ab, was die App weitergeben würde.
class _Captured {
  String? text;
  int calls = 0;
}

List<Override> _sharer(_Captured captured, {bool fail = false}) => [
  textSharerProvider.overrideWithValue((String text, {String? subject}) async {
    captured
      ..text = text
      ..calls += 1;
    if (fail) throw StateError('kein Teilen-Menü: $text');
    return ShareOutcome.shared;
  }),
];

void main() {
  testWidgets('die Einladung nennt Gruppe und Zugang, ohne Passwort', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openInvite(tester);

    expect(find.textContaining('Zugang: daciaracing'), findsOneWidget);
    expect(
      find.textContaining('bekommst du von mir'),
      findsOneWidget,
      reason: 'Ohne Eingabe geht die Einladung ohne Passwort raus.',
    );
    expect(find.textContaining('Passwort: '), findsNothing);
  });

  // Niemand soll etwas teilen, das er nicht gelesen hat.
  testWidgets('die Vorschau wächst beim Tippen mit', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openInvite(tester);

    await tester.enterText(find.byType(TextField).last, _password);
    await tester.pumpAndSettle();

    expect(find.textContaining('Passwort: $_password'), findsOneWidget);
    expect(
      find.textContaining('dauerhaft im Chat-Verlauf'),
      findsOneWidget,
      reason: 'Die Warnung erscheint erst, wenn wirklich eines drinsteht.',
    );
  });

  // `logRing` kann per Rückmeldung in einem **öffentlichen** GitHub-Issue
  // landen. Stünde das Gruppenpasswort dort, wäre der Zugang öffentlich.
  //
  // Geprüft wird der Fehlerpfad, weil er der gefährliche ist: Eine
  // Fehlermeldung, die den Nachrichtentext mitschleppt, wäre die
  // naheliegende Bequemlichkeit.
  testWidgets('das Passwort landet auch beim Fehlschlag nicht im Protokoll', (
    tester,
  ) async {
    logRing.clear();
    final captured = _Captured();

    // Der Fehlerpfad ist der gefährliche: Die Ausnahme trägt hier absichtlich
    // den ganzen Nachrichtentext, damit auffiele, wenn ihn jemand ins Log
    // schriebe.
    await pumpApp(tester, _backend(), overrides: _sharer(captured, fail: true));
    await _login(tester);
    await _openInvite(tester);
    await tester.enterText(find.byType(TextField).last, _password);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Teilen'));
    await tester.pumpAndSettle();

    expect(
      logRing.lines.join('\n'),
      isNot(contains(_password)),
      reason: 'Der Zugang der Gruppe darf nie in einem Log stehen.',
    );
    expect(
      find.text('Teilen fehlgeschlagen.'),
      findsOneWidget,
      reason: 'Der Fehler wird gemeldet, aber ohne den Nachrichtentext.',
    );
  });

  testWidgets('geteilt wird genau die Nachricht aus der Vorschau', (
    tester,
  ) async {
    final captured = _Captured();
    await pumpApp(tester, _backend(), overrides: _sharer(captured));
    await _login(tester);
    await _openInvite(tester);
    await tester.enterText(find.byType(TextField).last, _password);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Teilen'));
    await tester.pumpAndSettle();

    expect(captured.calls, 1);
    expect(captured.text, contains('Passwort: $_password'));
    expect(captured.text, contains('Zugang: daciaracing'));
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'Nach dem Teilen schließt der Dialog.',
    );
    expect(find.text('Einladung geteilt.'), findsOneWidget);
  });
}
