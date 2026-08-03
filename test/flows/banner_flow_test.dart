/// banner_flow_test.dart – Nächste Fahrt, Update-Hinweis und Feedback über
/// die echte App.
library;

import 'package:mitfahrbar/core/tokens.dart';
import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
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
/// sind — die Zutat, aus der eine „nächste Fahrt" wird. Über [days] lassen
/// sich weitere Tage besetzen (z. B. der Folgetag für den 12-Uhr-Wechsel).
Future<FakeBackend> _rideBackend({List<DateTime>? days}) async {
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
    for (final day in days ?? [testToday]) {
      await data.setAvailability(day, person.id, PlanRide.full);
    }
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

    // #131: Ab 12 Uhr gehört die Übersicht der morgigen Fahrt — der
    // Vormittag der heutigen. Beide Tage sind besetzt, damit der Wechsel
    // wirklich an der Uhrzeit hängt und nicht am leeren Heute.
    testWidgets('ab 12 Uhr zeigt das Banner morgen', (tester) async {
      final backend = await _rideBackend(
        days: [testToday, testToday.add(const Duration(days: 1))],
      );
      await pumpApp(
        tester,
        backend,
        overrides: [
          nowProvider.overrideWithValue(() => DateTime(2026, 7, 22, 12)),
        ],
      );
      await _login(tester);

      expect(find.text('Morgen (Do, 23.07.)'), findsOneWidget);
      expect(find.text('Heute (Mi, 22.07.)'), findsNothing);
    });

    // #139: Die festen Vorgaben stehen im selben Streifen — was das Handy
    // meldet und was die Übersicht zeigt, kommt aus derselben Funktion.
    testWidgets('nennt Abfahrt und Treffpunkt, wenn sie gepflegt sind', (
      tester,
    ) async {
      final backend = await _rideBackend();
      await backend
          .dataFor('group-1')
          .saveGroupDefaults(
            const GroupDefaults(
              outboundTime: DayTime(7, 15),
              returnTime: DayTime(16, 30),
              meetingPoint: 'Parkplatz Rathaus',
            ),
          );
      await pumpApp(tester, backend);
      await _login(tester);

      expect(
        find.textContaining('Abfahrt 07:15 · Rückfahrt 16:30'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Treffpunkt Parkplatz Rathaus'),
        findsOneWidget,
      );
    });

    testWidgets('ohne Vorgaben steht davon kein Wort im Banner', (
      tester,
    ) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      expect(
        find.textContaining('Abfahrt'),
        findsNothing,
        reason:
            'Wer die Felder nie ausfüllt, soll von der ganzen Sache nichts '
            'merken — kein „Abfahrt —", kein „Treffpunkt unbekannt".',
      );
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

    testWidgets('trägt die Töne des Design-Sets, nicht die des Schemas', (
      tester,
    ) async {
      final backend = await _rideBackend();
      backend.update = const UpdateInfo(
        latestVersion: '9.9.9',
        releaseUrl: 'https://example.invalid/r',
      );
      await pumpApp(tester, backend);
      await _login(tester);

      final context = tester.element(find.text('Heute (Mi, 22.07.)'));
      final brightness = Theme.of(context).brightness;

      // Die Fläche liegt seit v0.47.0 in `Ink` und nicht mehr in
      // `Material.color` — anders trägt sie keinen Verlauf.
      BoxDecoration decorationOf(String text) =>
          tester
                  .widget<Ink>(
                    find
                        .ancestor(
                          of: find.text(text),
                          matching: find.byType(Ink),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;

      expect(
        decorationOf('Heute (Mi, 22.07.)').gradient,
        AppBannerTones.nextRide(brightness).gradient,
        reason:
            'Das dauerhafte Banner trägt den Verlauf „Deep Teal Flow" aus '
            'dem Design-Set. Vorher stand hier der aus dem Cyan-Seed '
            'abgeleitete Lavendel, der in der Gruppe als Stilbruch auffiel.',
      );
      expect(
        decorationOf('Version 9.9.9 ist verfügbar').color,
        AppBannerTones.update(brightness).surface,
        reason:
            'Der Update-Hinweis kommt und geht — da ist Herausfallen der '
            'Zweck, und das Design-Set weist „Sunset Coral" ausdrücklich '
            'den Release-News zu. Er ist flächig, nicht verlaufend: Zwei '
            'farbige Verläufe übereinander wären ein Streifenmuster.',
      );
      expect(
        decorationOf('Version 9.9.9 ist verfügbar').gradient,
        isNull,
        reason: 'Nur das dauerhafte Banner trägt einen Verlauf.',
      );
      expect(
        decorationOf('Wunsch oder Fehler melden').color,
        isNot(AppBannerTones.update(brightness).surface),
        reason:
            'Feedback-Angebot und Update-Hinweis stehen übereinander und '
            'dürfen nicht derselbe Streifen sein.',
      );
    });

    testWidgets('der Anmerkungs-Zähler trägt den eigenen Akzent', (
      tester,
    ) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      final badge = tester.widget<Badge>(find.byType(Badge).first);
      expect(
        badge.backgroundColor,
        AppAccents.notesChip,
        reason:
            'Der Akzent sitzt allein auf dem Zähler, der seine eigene '
            'Fläche mitbringt. Frei auf dem Verlauf wäre Magenta unlesbar '
            '(1,61:1 auf dem hellen Teal) — das Design-Set nennt die Regel '
            '„nie zwei Akzente im selben Banner".',
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
