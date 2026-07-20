/// banner_flow_test.dart – Update-Hinweis und Feedback über die echte App.
library;

import 'package:fahrgemeinschaft/core/update_check.dart';
import 'package:fahrgemeinschaft/models/person.dart';
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

void main() {
  testWidgets('ohne neue Version erscheint kein Update-Hinweis', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.textContaining('ist verfügbar'), findsNothing);
  });

  testWidgets('neue Version zeigt Hinweis und Details', (tester) async {
    final backend = _backend()
      ..update = const UpdateInfo(
        latestVersion: '9.9.9',
        releaseUrl: 'https://example.invalid/release',
        releaseNotes: 'Schnellere Erfassung',
      );

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.text('Version 9.9.9 ist verfügbar'), findsOneWidget);

    await tester.tap(find.text('Version 9.9.9 ist verfügbar'));
    await tester.pumpAndSettle();
    expect(find.text('Schnellere Erfassung'), findsOneWidget);
  });

  testWidgets('Update-Hinweis lässt sich ausblenden', (tester) async {
    final backend = _backend()
      ..update = const UpdateInfo(
        latestVersion: '9.9.9',
        releaseUrl: 'https://example.invalid/r',
      );

    await pumpApp(tester, backend);
    await _login(tester);
    expect(find.text('Version 9.9.9 ist verfügbar'), findsOneWidget);

    await tester.tap(find.byTooltip('Ausblenden').first);
    await tester.pumpAndSettle();

    expect(find.text('Version 9.9.9 ist verfügbar'), findsNothing);
  });

  testWidgets('Fehlermeldung wird gesendet und gespeichert', (tester) async {
    final backend = _backend();
    await pumpApp(tester, backend);
    await _login(tester);

    await tester.tap(find.text('Wunsch oder Fehler melden'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fehler'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Historie zeigt die Fahrt nicht.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await tester.pumpAndSettle();

    expect(backend.feedback, hasLength(1));
    expect(backend.feedback.single['type'], 'bug');
    expect(
      backend.feedback.single['message'],
      'Historie zeigt die Fahrt nicht.',
    );
    expect(find.textContaining('Danke'), findsOneWidget);
  });

  testWidgets('zu kurze Rückmeldung wird abgefangen', (tester) async {
    final backend = _backend();
    await pumpApp(tester, backend);
    await _login(tester);

    await tester.tap(find.text('Wunsch oder Fehler melden'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hm');
    await tester.tap(find.widgetWithText(FilledButton, 'Senden'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ein paar Worte mehr'), findsOneWidget);
    expect(backend.feedback, isEmpty);
  });
}
