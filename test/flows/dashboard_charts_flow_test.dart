/// dashboard_charts_flow_test.dart – Die Auswertungen auf der Startseite.
library;

import 'package:mitfahrbar/core/widgets/charts.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

String _setUpGroup(FakeBackend backend) => backend.addGroup(
  handle: 'daciaracing',
  password: 'geheim123',
  name: 'Dacia Racing',
);

/// Hohe Testfläche: Die ListView baut nur, was sichtbar ist – auf der
/// Standardgröße läge die Hälfte der Karten unter der Kante, und ein
/// `findsNothing` wäre dann auch dann erfüllt, wenn die Karte existiert.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Legt zwei Personen an und für jedes Element von [monthsAgo] eine Fahrt
/// so viele Monate vor dem Testtag.
Future<void> _seed(FakeBackend backend, List<int> monthsAgo) async {
  final data = backend.dataFor(_setUpGroup(backend));
  final ids = <String>[];
  for (final name in ['Anna', 'Bert']) {
    final person = await data.createPerson(
      Person(id: '', name: name, active: true),
    );
    ids.add(person.id);
  }
  for (final back in monthsAgo) {
    await data.createTrip(
      DateTime(testToday.year, testToday.month - back, 10),
      {
        ids[0]: ParticipationStatus.driver,
        ids[1]: ParticipationStatus.passenger,
      },
    );
  }
}

/// Der waagerechte Scroll-Zustand des Monats-Diagramms.
ScrollPosition _plotScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(MonthlyTripsChart),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  // Das Zeitfenster reicht seit #119 bis zur ersten Fahrt. Passt das nicht in
  // die Breite, wird gewischt statt die Säulen zu Strichen zu quetschen.
  group('Monats-Diagramm', () {
    testWidgets('lange Historie macht das Diagramm scrollbar', (tester) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      // Knapp drei Jahre — mehr, als in eine Handybreite passt.
      await _seed(backend, [0, 6, 12, 24, 34]);

      await pumpApp(tester, backend);
      await _login(tester);

      expect(
        _plotScroll(tester).maxScrollExtent,
        greaterThan(0),
        reason:
            'Eine Scrollleiste, an der es nichts zu scrollen gibt, macht die '
            'Historie nicht erreichbar.',
      );
      // Der Untertitel nennt den abgedeckten Zeitraum — hier reicht er ins
      // Jahr der ersten Fahrt zurück.
      expect(find.textContaining('Sept. 2023'), findsOneWidget);
    });

    // Im Browser gibt es keinen Finger. Flutters Standardverhalten lässt auf
    // Web und Desktop nur Finger ziehen — ohne die eigene ScrollBehavior
    // käme man dort nur mit dem Mausrad an die Historie, und auf dem
    // Testgerät (Android) fiele das nie auf.
    testWidgets('auch die Maus darf ziehen', (tester) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await _seed(backend, [0, 6, 12, 24, 34]);

      await pumpApp(tester, backend);
      await _login(tester);

      final before = _plotScroll(tester).pixels;
      await tester.drag(
        find.byType(MonthlyTripsChart),
        const Offset(120, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(
        _plotScroll(tester).pixels,
        greaterThan(before),
        reason: 'Ziehen nach rechts holt die älteren Monate herein.',
      );
    });

    testWidgets('kurze Historie passt ohne Wischen', (tester) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await _seed(backend, [0, 1, 2]);

      await pumpApp(tester, backend);
      await _login(tester);

      expect(
        _plotScroll(tester).maxScrollExtent,
        0,
        reason:
            'Zwölf Monate passen in die Breite — dann darf nichts wackeln, '
            'was nach mehr Inhalt aussieht.',
      );
    });
  });

  // Nicht hier geprüft: dass die Zahlen über den Säulen weg sind und die
  // Hilfslinien auf ihren Achsenwerten liegen. Beides ist auf Canvas gemalt,
  // ein Widget-Test sähe davon nichts — ein `find`-Test darauf wäre auch vor
  // der Änderung grün gewesen. Das entscheidet der Blick auf den Demo-Build
  // (.claude/skills/run-web), die Skala selbst hängt an `axisTicks` in
  // test/chart_data_test.dart.

  testWidgets('mit Fahrten zeigt die Startseite die Auswertungen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    final data = backend.dataFor(groupId);

    final ids = <String>[];
    for (final name in ['Anna', 'Bert']) {
      final person = await data.createPerson(
        Person(id: '', name: name, active: true),
      );
      ids.add(person.id);
    }
    await data.createTrip(DateTime.now(), {
      ids[0]: ParticipationStatus.driver,
      ids[1]: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.text('Gemeinsam erreicht'), findsOneWidget);
    expect(find.text('Fahrten pro Monat'), findsOneWidget);
    expect(find.text('Wie ihr unterwegs seid'), findsOneWidget);
    // Die Legende benennt die Kategorien – Farbe allein trägt die Zuordnung
    // nie allein.
    expect(find.text('gefahren'), findsOneWidget);
    expect(find.text('mitgefahren'), findsOneWidget);
    expect(find.text('1-way'), findsOneWidget);
  });

  testWidgets('ohne Fahrten bleiben die Diagramme aus', (tester) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    await backend
        .dataFor(groupId)
        .createPerson(const Person(id: '', name: 'Anna', active: true));

    await pumpApp(tester, backend);
    await _login(tester);

    // Eine leere Achse sagt weniger als gar keine Karte.
    expect(find.text('Fahrten pro Monat'), findsNothing);
    expect(find.text('Wie ihr unterwegs seid'), findsNothing);
  });
}
