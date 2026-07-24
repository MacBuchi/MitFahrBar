/// feedback_log_flow_test.dart – Protokoll an eine Rückmeldung hängen.
library;

import 'package:mitfahrbar/core/log.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

FakeBackend _backend() {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  backend
      .dataFor(id)
      .createPerson(const Person(id: '', name: 'Anna', active: true));
  return backend;
}

Future<void> _openFeedback(WidgetTester tester) async {
  await tester.tap(find.text('Wunsch oder Fehler melden'));
  await tester.pumpAndSettle();
}

void main() {
  // logRing ist global; ohne Zurücksetzen färbt ein Test auf den nächsten ab.
  setUp(logRing.clear);
  tearDown(logRing.clear);

  testWidgets('ohne Protokoll gibt es nichts anzuhängen', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openFeedback(tester);

    expect(
      find.text('Fehlerprotokoll anhängen'),
      findsNothing,
      reason:
          'Eine Checkbox ohne Inhalt erklärt sich nicht und weckt falsche '
          'Erwartungen.',
    );
  });

  // Die Rückmeldung wird ein öffentliches GitHub-Issue. Deshalb darf das
  // Protokoll nur mitgehen, wenn es ausdrücklich angehakt wurde.
  testWidgets('das Protokoll geht nur mit, wenn man es anhakt', (tester) async {
    logRing.add('FEHLER Verbindung abgebrochen');
    final backend = _backend();

    await pumpApp(tester, backend);
    await _login(tester);
    await _openFeedback(tester);

    expect(find.text('Fehlerprotokoll anhängen'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Geht nicht.');
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await tester.pumpAndSettle();

    expect(
      backend.feedback.single['message'],
      'Geht nicht.',
      reason: 'Standardmäßig abgewählt — nichts geht ungefragt mit.',
    );
  });

  testWidgets('angehakt landet das Protokoll in der Rückmeldung', (
    tester,
  ) async {
    logRing.add('FEHLER Verbindung abgebrochen');
    final backend = _backend();

    await pumpApp(tester, backend);
    await _login(tester);
    await _openFeedback(tester);

    // Vorschau statt Vertrauensvorschuss: erst sichtbar, dann absendbar.
    await tester.tap(find.text('Fehlerprotokoll anhängen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Verbindung abgebrochen'),
      findsOneWidget,
      reason: 'Wer etwas Öffentliches mitschickt, soll es vorher sehen.',
    );

    await tester.enterText(find.byType(TextField).last, 'Geht nicht.');
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await tester.pumpAndSettle();

    final message = backend.feedback.single['message']! as String;
    expect(message, startsWith('Geht nicht.'));
    expect(message, contains('Verbindung abgebrochen'));
  });
}
