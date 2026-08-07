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

    // #183: Bei EINEM Auto gilt dessen Abweichung allen — das Banner muss
    // dieselbe Zeit nennen wie die Erinnerung, sonst steht hier 07:30,
    // während das Handy um 06:45 weckt.
    testWidgets('die Abweichung des einzigen Autos schlägt die Vorgabe', (
      tester,
    ) async {
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      final anna = await data.createPerson(
        const Person(id: '', name: 'Anna', active: true),
      );
      await data.setAvailability(testToday, anna.id, PlanRide.full);
      await data.saveGroupDefaults(
        const GroupDefaults(outboundTime: DayTime(7, 30)),
      );
      // Anna ist als Einzige verfügbar und damit die Fahrerin des einzigen
      // Autos — ihre Auto-Zeile gilt dem ganzen Tag.
      await data.saveCarDefaults(
        testToday,
        anna.id,
        const GroupDefaults(outboundTime: DayTime(6, 45)),
      );
      await pumpApp(tester, backend);
      await _login(tester);

      expect(find.textContaining('Abfahrt 06:45'), findsOneWidget);
      expect(
        find.textContaining('Abfahrt 07:30'),
        findsNothing,
        reason:
            'Die Vorgabe gilt an diesem Tag nicht — sie zu zeigen hieße, '
            'zwei Wahrheiten über dieselbe Abfahrt zu verbreiten.',
      );
    });

    // #189: Ab zwei Autos zählt der Streifen sie einzeln auf — mit ihren
    // Mitfahrern und ihrer eigenen Zeit. Für diesen Fall gab es bis hierher
    // gar keinen Test durch die App; gemessen wurde nur der Ein-Auto-Fall.
    testWidgets('zwei Autos stehen einzeln, jedes mit seiner Zeit', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      // Vier Personen à zwei Sitzen ergeben zwei Autos (Issue #62).
      final ids = <String, String>{};
      for (final name in ['Anna', 'Bert', 'Clara', 'Dora']) {
        final person = await data.createPerson(
          Person(id: '', name: name, active: true, seats: 2),
        );
        ids[name] = person.id;
        await data.setAvailability(testToday, person.id, PlanRide.full);
      }
      await pumpApp(tester, backend);
      await _login(tester);

      // Gezeichnet sind es Zeilen mit Farbmarken — vorgelesen bleibt es ein
      // Satz. Beides gehört geprüft: Die Marke sagt einem Screenreader
      // nichts, und der Satz allein wäre der alte Zustand.
      expect(
        find.bySemanticsLabel(RegExp('Auto 1: .* · Auto 2: ')),
        findsOneWidget,
        reason:
            'Die Frage vor der Abfahrt ist „mit wem fahre ich" — ein Topf '
            'aus den Mitfahrern beider Autos beantwortet sie nicht. Und wer '
            'nichts sieht, muss denselben Satz hören.',
      );
      expect(
        find.byKey(const ValueKey('car-badge-1')),
        findsOneWidget,
        reason:
            'Die Nummer trägt die Zuordnung mit — ohne sie verlöre jeder '
            'Rot-Grün-Schwache und jeder Graustufen-Screenshot sie.',
      );
      expect(find.byKey(const ValueKey('car-badge-2')), findsOneWidget);
      expect(
        find.textContaining('2 Autos'),
        findsNothing,
        reason: 'Wer „Auto 1" und „Auto 2" liest, hat sie gezählt.',
      );
      handle.dispose();
    });

    // Der gemeldete Punkt vom 07.08.: „was pro Fahrzeug auf den ersten Blick
    // hervorgehen sollte, wenn Treffpunkt oder Uhrzeit abweichen — das ist
    // aktuell nicht der Fall." Als Wort im Fließtext ging es unter.
    testWidgets('die Abweichung eines Autos steht als eigener Chip da', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      final ids = <String>[];
      for (final name in ['Anna', 'Bert', 'Clara', 'Dora']) {
        final person = await data.createPerson(
          Person(id: '', name: name, active: true, seats: 2),
        );
        ids.add(person.id);
        await data.setAvailability(testToday, person.id, PlanRide.full);
      }
      // Beide möglichen Fahrer bekommen dieselbe Zeit — so trägt der Test
      // die Abweichung, egal welchen der beiden der Vorschlag wählt.
      for (final personId in ids) {
        await data.saveCarDefaults(
          testToday,
          personId,
          const GroupDefaults(outboundTime: DayTime(6, 45)),
        );
      }
      await pumpApp(tester, backend);
      await _login(tester);

      expect(
        find.text('hin 06:45'),
        findsWidgets,
        reason: 'Die abweichende Zeit gehört sichtbar an ihr Auto.',
      );
      final glyph = tester.widget<Icon>(find.byIcon(Icons.schedule).first);
      expect(
        glyph.color,
        AppAccents.notesChipInk,
        reason:
            'Der Chip trägt den Anmerkungs-Akzent: Eine geänderte Zeit IST '
            'eine Anmerkung (entschieden 07.08.). Als farbige Schrift ginge '
            'es nicht — der Untertitel läuft über das helle Verlaufsende.',
      );
      handle.dispose();
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
            'Der Zähler bringt seine eigene Fläche mit — frei auf dem hellen '
            'Teal wäre Magenta mit 1,61:1 unlesbar. Deshalb sitzt der Knopf '
            'am dunklen Ende des Verlaufs.',
      );
    });

    // #189: „bei Kommentaren auch Chatsymbol in gleicher Farbe". Die Blase
    // hat keine eigene Fläche, sie liegt frei auf dem Verlauf — deshalb gilt
    // das nur am dunklen Ende, und deshalb misst der Kontrast-Test es mit.
    testWidgets('die Sprechblase wird magenta, sobald es Anmerkungen gibt', (
      tester,
    ) async {
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      final anna = await data.createPerson(
        const Person(id: '', name: 'Anna', active: true),
      );
      await data.setAvailability(testToday, anna.id, PlanRide.full);
      await data.addNote(testToday, anna.id, 'Komme erst um 9');
      await pumpApp(tester, backend);
      await _login(tester);

      Icon bubble() => tester.widget<Icon>(
        find
            .descendant(of: find.byType(Badge), matching: find.byType(Icon))
            .first,
      );
      expect(bubble().color, AppAccents.notesChip);
      expect(
        bubble().icon,
        Icons.chat_bubble_rounded,
        reason: 'Gefüllt, sobald etwas drinsteht — Farbe UND Form.',
      );
    });

    testWidgets('ohne Anmerkung bleibt die Sprechblase weiß', (tester) async {
      await pumpApp(tester, await _rideBackend());
      await _login(tester);

      final bubble = tester.widget<Icon>(
        find
            .descendant(of: find.byType(Badge), matching: find.byType(Icon))
            .first,
      );
      expect(
        bubble.color,
        AppBannerTones.nextRide(Brightness.light).foreground,
        reason:
            'Die andere Richtung: Ein Akzent ohne Anmerkung zeigte auf '
            'nichts. Rot verifiziert.',
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
