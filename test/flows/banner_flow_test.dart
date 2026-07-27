/// banner_flow_test.dart – Nächste Fahrt, Update-Hinweis und Feedback über
/// die echte App.
library;

import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
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

/// Wie [_backend], aber mit zwei Personen, die für den Testtag eingetragen
/// sind — die Zutat, aus der eine „nächste Fahrt" wird.
Future<FakeBackend> _rideBackend() async {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(id);
  for (final name in ['Anna', 'Bert']) {
    final person = await data.createPerson(
      Person(id: '', name: name, active: true),
    );
    await data.setAvailability(testToday, person.id, PlanRide.full);
  }
  return backend;
}

void main() {
  // Das Banner „nächste Fahrt" (#122): der Inhalt der Abend-Meldung, aber
  // ohne Handy.
  group('Nächste Fahrt', () {
    testWidgets('nennt Tag, Fahrer und Mitfahrer', (tester) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      // testToday ist Mittwoch, der 22.07.2026 — heute ist noch nichts
      // eingetragen, also ist heute die nächste Fahrt.
      expect(find.text('Heute (Mi, 22.07.)'), findsOneWidget);
      expect(find.textContaining('fährt · dabei: '), findsOneWidget);
    });

    testWidgets('führt angetippt in die Woche', (tester) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      // Tippen, nicht nur finden: Ein Knopf, der sichtbar ist und nichts
      // tut, war schon einmal der Ausfall (Update-Schirm 0.37.0).
      await tester.tap(find.text('Heute (Mi, 22.07.)'));
      await tester.pumpAndSettle();

      expect(find.text('Wochenplan'), findsOneWidget);
    });

    testWidgets('lässt sich nicht ausblenden', (tester) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      expect(find.text('Heute (Mi, 22.07.)'), findsOneWidget);
      expect(
        find.byTooltip('Ausblenden'),
        findsOneWidget,
        reason:
            'Nur der Feedback-Hinweis darf weggetippt werden. Bekäme die '
            'nächste Fahrt auch einen Knopf, wären es zwei — und „alles auf '
            'einen Blick" (#122) erfüllt kein weggetipptes Banner.',
      );
      // Der Test oben zählt über den ganzen Schirm und würde einen zweiten
      // Knopf am FALSCHEN Banner nicht bemerken; diese Zusicherung hängt am
      // richtigen. Der Anmerkungs-Knopf (#127) trägt deshalb einen eigenen
      // Tooltip — hieße er auch „Ausblenden", wäre die Prüfung oben rot,
      // ohne dass die Regel verletzt wäre.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Heute (Mi, 22.07.)'),
            matching: find.byType(InkWell),
          ),
          matching: find.byTooltip('Ausblenden'),
        ),
        findsNothing,
      );
    });

    testWidgets('führt über die Sprechblase in die Anmerkungen', (
      tester,
    ) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      // Tippen, nicht nur finden.
      await tester.tap(find.byTooltip('Anmerkungen'));
      await tester.pumpAndSettle();

      expect(find.text('Anmerkungen'), findsWidgets);
      expect(
        find.textContaining('Komme erst um 9'),
        findsOneWidget,
        reason: 'Der leere Schirm nennt ein Beispiel.',
      );
    });

    testWidgets('trägt die Markenfarbe, nicht den Fremdton', (tester) async {
      final backend = await _rideBackend();
      backend.update = const UpdateInfo(
        latestVersion: '9.9.9',
        releaseUrl: 'https://example.invalid/r',
      );
      await pumpApp(tester, backend);
      await _login(tester);

      final context = tester.element(find.text('Heute (Mi, 22.07.)'));
      final scheme = Theme.of(context).colorScheme;

      Color colorOf(String text) => tester
          .widget<Material>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Material))
                .first,
          )
          .color!;

      expect(
        colorOf('Heute (Mi, 22.07.)'),
        scheme.primaryContainer,
        reason:
            'Material 3 leitet `tertiary` aus einem Cyan-Seed als Lavendel '
            'ab — der einzige fremde Ton der Oberfläche. Auf dem dauerhaften '
            'Banner fiel er in der Gruppe als Stilbruch auf (v0.47.0).',
      );
      expect(
        colorOf('Version 9.9.9 ist verfügbar'),
        scheme.tertiaryContainer,
        reason:
            'Dorthin ist der Fremdton gewandert: Der Update-Hinweis kommt '
            'und geht, da ist Herausfallen der Zweck. Tauschte man beide '
            'zurück, stünden nach dieser Änderung zwei gleichfarbige '
            'Streifen übereinander.',
      );
    });

    testWidgets('bleibt weg, solange niemand eingetragen ist', (tester) async {
      // _backend() legt Anna an, aber keine Verfügbarkeit.
      await pumpApp(tester, _backend());
      await _login(tester);

      expect(find.textContaining('dabei: '), findsNothing);
      expect(find.textContaining('Kein Fahrer'), findsNothing);
    });
  });

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
