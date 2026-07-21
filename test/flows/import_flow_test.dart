/// import_flow_test.dart – CSV-Import über die echte App.
///
/// Das Format prüft `csv_import_test.dart`. Hier geht es um das, was den
/// zweistufigen Ablauf überhaupt rechtfertigt: dass **nichts** geschrieben
/// wird, bevor jemand bestätigt hat, wer wer ist.
library;

import 'package:fahrgemeinschaft/data/providers.dart';
import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _openImport(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fahrten importieren (CSV)'));
  await tester.pumpAndSettle();
}

List<Override> _file(String? content) => [
  filePickerProvider.overrideWithValue(() async => content),
];

void main() {
  late FakeBackend backend;
  late String groupId;

  setUp(() {
    backend = FakeBackend();
    groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
  });

  Future<Map<String, String>> addPersons(List<String> names) async {
    final data = backend.dataFor(groupId);
    for (final name in names) {
      await data.createPerson(Person(id: '', name: name, active: true));
    }
    return {for (final p in await data.loadPersons()) p.name: p.id};
  }

  const csv =
      'Datum;Anna;Bernd;Notiz\r\n'
      '09.03.2026;Fahrer;Mit;\r\n'
      '10.03.2026;Mit;Fahrer;\r\n';

  testWidgets('bekannte Namen werden zugeordnet und die Fahrten übernommen', (
    tester,
  ) async {
    await addPersons(['Anna', 'Bernd']);
    await pumpApp(tester, backend, overrides: _file(csv));
    await _login(tester);
    await _openImport(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('2 Fahrten gefunden'), findsOneWidget);
    expect(
      await backend.dataFor(groupId).loadTrips(),
      isEmpty,
      reason: 'Vor dem Bestätigen darf nichts geschrieben sein.',
    );

    await tester.tap(find.widgetWithText(FilledButton, '2 Fahrten übernehmen'));
    await tester.pumpAndSettle();

    final trips = await backend.dataFor(groupId).loadTrips();
    expect(trips, hasLength(2));
    expect(find.textContaining('2 Fahrten übernommen'), findsOneWidget);
    expect(
      (await backend.dataFor(groupId).loadPersons()),
      hasLength(2),
      reason: 'Bekannte Namen dürfen keine zweite Person anlegen.',
    );
  });

  // Der Kern von Issue #34: `persons.name` ist in der Datenbank nicht
  // eindeutig. Würde der Import still anlegen, entstünden aus einem
  // Tippfehler zwei Personen — und das verschiebt rückwirkend die Punkte
  // aller anderen.
  testWidgets('ein Tippfehler lässt sich auf die richtige Person schieben', (
    tester,
  ) async {
    final ids = await addPersons(['Anna', 'Bernd']);
    await pumpApp(
      tester,
      backend,
      overrides: _file('Datum;Anna;Bernnd;Notiz\r\n09.03.2026;Fahrer;Mit;\r\n'),
    );
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    // „Bernnd" ist unbekannt und stünde auf „neu anlegen".
    expect(find.text('Bernnd'), findsOneWidget);
    expect(find.text('neu anlegen'), findsOneWidget);

    await tester.tap(find.text('neu anlegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ist Bernd').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '1 Fahrt übernehmen'));
    await tester.pumpAndSettle();

    final persons = await backend.dataFor(groupId).loadPersons();
    expect(
      persons,
      hasLength(2),
      reason: 'Der Tippfehler darf keine dritte Person hinterlassen.',
    );
    final trip = (await backend.dataFor(groupId).loadTrips()).single;
    expect(trip.participations[ids['Bernd']], ParticipationStatus.passenger);
  });

  testWidgets('neue Personen werden angelegt, wenn man sie stehen lässt', (
    tester,
  ) async {
    await addPersons(['Anna']);
    await pumpApp(tester, backend, overrides: _file(csv));
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '2 Fahrten übernehmen'));
    await tester.pumpAndSettle();

    final persons = await backend.dataFor(groupId).loadPersons();
    expect(persons.map((p) => p.name), containsAll(['Anna', 'Bernd']));
    expect(find.textContaining('1 Person angelegt'), findsOneWidget);
  });

  // Die Fahrt ohne die weggelassene Person anzulegen, änderte still die
  // Punkte aller übrigen an diesem Tag. Und der Knopf sagt die ehrliche
  // Zahl an — nicht, was in der Datei steht (Gerätetest 2026-07-21).
  testWidgets('wird jemand weggelassen, entfällt seine Fahrt ganz', (
    tester,
  ) async {
    await addPersons(['Anna']);
    // Fahrt 1 hat Bernd dabei, Fahrt 2 nicht — nur sie bleibt übrig.
    await pumpApp(
      tester,
      backend,
      overrides: _file(
        'Datum;Anna;Bernd;Notiz\r\n'
        '09.03.2026;Fahrer;Mit;\r\n'
        '10.03.2026;Fahrer;;\r\n',
      ),
    );
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '2 Fahrten übernehmen'), findsOne);

    await tester.tap(find.text('neu anlegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('weglassen').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '1 Fahrt übernehmen'));
    await tester.pumpAndSettle();

    expect(
      await backend.dataFor(groupId).loadTrips(),
      hasLength(1),
      reason: 'Die Fahrt mit Bernd entfällt ganz, die ohne ihn bleibt.',
    );
    expect(find.textContaining('jemand war weggelassen'), findsOneWidget);
  });

  // Bleibt gar nichts übrig, gibt es auch nichts zu drücken — ein Knopf,
  // der „2 Fahrten übernehmen" verspricht und 0 schreibt, wäre gelogen.
  testWidgets('entfallen alle Fahrten, ist der Knopf aus', (tester) async {
    await addPersons(['Anna']);
    await pumpApp(tester, backend, overrides: _file(csv));
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('neu anlegen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('weglassen').last);
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Nichts zu übernehmen'),
    );
    expect(button.onPressed, isNull);
    expect(await backend.dataFor(groupId).loadTrips(), isEmpty);
  });

  testWidgets('ein Tag, der schon eingetragen ist, wird nicht verdoppelt', (
    tester,
  ) async {
    final ids = await addPersons(['Anna', 'Bernd']);
    await backend.dataFor(groupId).createTrip(DateTime(2026, 3, 9), {
      ids['Anna']!: ParticipationStatus.driver,
    });

    await pumpApp(tester, backend, overrides: _file(csv));
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();
    // Der Knopf rechnet den belegten Tag schon heraus.
    await tester.tap(find.widgetWithText(FilledButton, '1 Fahrt übernehmen'));
    await tester.pumpAndSettle();

    expect(await backend.dataFor(groupId).loadTrips(), hasLength(2));
    expect(find.textContaining('Tag war schon eingetragen'), findsOneWidget);
  });

  testWidgets('krumme Zeilen werden benannt, die guten trotzdem übernommen', (
    tester,
  ) async {
    await addPersons(['Anna']);
    await pumpApp(
      tester,
      backend,
      overrides: _file(
        'Datum;Anna\r\n09.03.2026;Fahrer\r\nkein-datum;Fahrer\r\n',
      ),
    );
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Zeile 3'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '1 Fahrt übernehmen'), findsOne);
  });

  testWidgets('eine Datei ohne Kopfzeile führt zu keinem Schreibknopf', (
    tester,
  ) async {
    await addPersons(['Anna']);
    await pumpApp(tester, backend, overrides: _file('Tag;Anna\r\n'));
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('keine Fahrt lesen'), findsOneWidget);
    expect(find.textContaining('übernehmen'), findsNothing);
  });

  testWidgets('Abbrechen im Dateidialog passiert einfach nichts', (
    tester,
  ) async {
    await addPersons(['Anna']);
    await pumpApp(tester, backend, overrides: _file(null));
    await _login(tester);
    await _openImport(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CSV-Datei wählen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('gefunden'), findsNothing);
    expect(find.textContaining('keine Fahrt lesen'), findsNothing);
  });
}
