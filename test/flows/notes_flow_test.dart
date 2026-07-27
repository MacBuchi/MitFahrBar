/// notes_flow_test.dart – Anmerkungen zum Plantag über die echte App (#127).
///
/// Der Zugang wird **angetippt**, nicht nur gefunden: Ein sichtbarer Knopf,
/// der nirgendwo hinführt, ist die Klasse Fehler des toten Update-Knopfs aus
/// 0.37.0.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.backend, this.anna, this.bert);

  final FakeBackend backend;
  final String anna;
  final String bert;
}

/// Zwei Personen, beide für [testToday] eingetragen — daraus wird eine
/// „nächste Fahrt" und damit ein Banner mit Sprechblase.
Future<_Fixture> _fixture() async {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(id);
  final ids = <String>[];
  for (final name in ['Anna', 'Bert']) {
    final person = await data.createPerson(
      Person(id: '', name: name, active: true),
    );
    await data.setAvailability(testToday, person.id, PlanRide.full);
    ids.add(person.id);
  }
  return _Fixture(backend, ids.first, ids.last);
}

/// Öffnet die Anmerkungen über die Sprechblase am Banner der nächsten Fahrt.
Future<void> _openNotes(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Anmerkungen'));
  await tester.pumpAndSettle();
}

Future<void> _write(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.byTooltip('Anmerkung senden'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('eine Anmerkung schreiben und wiederfinden', (tester) async {
    final f = await _fixture();
    await pumpApp(tester, f.backend);
    await _login(tester);
    await _openNotes(tester);

    // Ohne Geräte-Zuordnung muss der Verfasser gewählt werden — die
    // Sendezeile fragt danach, statt zu sperren.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bert').last);
    await tester.pumpAndSettle();

    await _write(tester, 'Komme erst um 9.');

    expect(find.text('Komme erst um 9.'), findsOneWidget);
    expect(find.textContaining('Bert'), findsWidgets);
  });

  testWidgets('ohne gewählte Person ist der Senden-Knopf gesperrt', (
    tester,
  ) async {
    final f = await _fixture();
    await pumpApp(tester, f.backend);
    await _login(tester);
    await _openNotes(tester);

    await tester.enterText(find.byType(TextField).last, 'Etwas');
    await tester.pumpAndSettle();

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Anmerkung senden'),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      button.onPressed,
      isNull,
      reason:
          'Ohne Verfasser gäbe es keine person_id — gesperrt ist ehrlicher '
          'als ein Fehler nach dem Tippen.',
    );
  });

  testWidgets('die Geräte-Zuordnung belegt den Verfasser vor', (tester) async {
    final f = await _fixture();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openNotes(tester);

    // Kein Auswählen nötig: „Ich bin" (#121) steht schon im Feld.
    await _write(tester, 'Ich bringe Kuchen mit.');

    expect(find.text('Ich bringe Kuchen mit.'), findsOneWidget);
  });

  testWidgets('leere Anmerkungen werden abgefangen', (tester) async {
    final f = await _fixture();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openNotes(tester);

    await _write(tester, '   ');

    expect(
      find.textContaining('Bitte schreib etwas'),
      findsOneWidget,
      reason:
          'Der Client spiegelt den Check der Datenbank '
          '(`char_length(btrim(body)) between 1 and 500`) — ohne das sähe '
          'die Nutzerin einen rohen Postgres-Fehler.',
    );
  });

  testWidgets('eine Anmerkung lässt sich wieder löschen', (tester) async {
    final f = await _fixture();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openNotes(tester);
    await _write(tester, 'Doch nicht.');
    expect(find.text('Doch nicht.'), findsOneWidget);

    await tester.tap(find.byTooltip('Anmerkung löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Doch nicht.'), findsNothing);
  });

  testWidgets('der Planer zählt sie an der Tageszeile und führt hin', (
    tester,
  ) async {
    final f = await _fixture();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openNotes(tester);
    await _write(tester, 'Komme erst um 9.');

    // Zurück auf die Übersicht, von dort in die Woche.
    // Nicht `pageBack()`: Das sucht den Tooltip „Back", die App ist aber
    // deutsch und der Knopf heißt „Zurück".
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heute (Mi, 22.07.)'));
    await tester.pumpAndSettle();

    // Die Tageszeilen stehen unter Raster und Wochenbilanz — im Testviewport
    // sind nur die ersten gebaut.
    await tester.scrollUntilVisible(
      find.text('Mittwoch, 22.7.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('· 1 Anmerkung'),
      findsOneWidget,
      reason:
          'Der Zähler hängt am subtitle und nicht am trailing: Dort stehen '
          'je nach Zustand schon zwei Knöpfe, und ein dritter müsste in '
          'alle fünf Zweige.',
    );

    // Und die Tageszeile führt hin — antippen, nicht nur finden.
    await tester.tap(find.textContaining('· 1 Anmerkung'));
    await tester.pumpAndSettle();
    expect(find.text('Komme erst um 9.'), findsOneWidget);
  });

  testWidgets('das Banner nennt die jüngste Anmerkung', (tester) async {
    final f = await _fixture();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openNotes(tester);
    await _write(tester, 'Komme erst um 9.');
    // Nicht `pageBack()`: Das sucht den Tooltip „Back", die App ist aber
    // deutsch und der Knopf heißt „Zurück".
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Anna: Komme erst um 9.'),
      findsOneWidget,
      reason:
          'Wortlaut aus push_digest.dart: Was das Handy meldet und was die '
          'App zeigt, darf nicht auseinanderlaufen.',
    );
  });

  testWidgets('eine unlesbare Adresse scheitert nicht, sie erklärt', (
    tester,
  ) async {
    final f = await _fixture();
    await pumpApp(tester, f.backend);
    await _login(tester);

    // Auf Web ist `/notes/:date` eine echte, tippbare Adresse — hier wird sie
    // von Hand angesteuert, weil kein Knopf dorthin führen kann.
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/notes/kein-datum');
    await tester.pumpAndSettle();

    expect(find.textContaining('nicht lesbar'), findsOneWidget);

    // Und der Weg heraus — angetippt, nicht nur gefunden.
    await tester.tap(find.widgetWithText(FilledButton, 'Zur Übersicht'));
    await tester.pumpAndSettle();
    expect(find.text('Wer ist dran?'), findsOneWidget);
  });

  testWidgets('direkt geöffnet führt ein Knopf zur Übersicht', (tester) async {
    final f = await _fixture();
    await pumpApp(tester, f.backend);
    await _login(tester);

    // `go` statt `push`: genau die Lage nach einem Reload oder einem
    // geteilten Link — kein Zurück-Eintrag, also auch kein automatischer
    // Zurück-Knopf. Im Browser gefunden, nicht im Test: Ohne den eigenen
    // Knopf säße man auf dem Schirm fest.
    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go('/notes/2026-07-22');
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(find.byTooltip('Zur Übersicht'));
    await tester.pumpAndSettle();
    expect(find.text('Wer ist dran?'), findsOneWidget);
  });
}
