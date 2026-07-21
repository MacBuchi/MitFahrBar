/// help_flow_test.dart – Die Anleitung, über die echte App erreicht.
///
/// Geprüft werden die Kernaussagen, nicht jedes Wort: Der Test soll schlagen,
/// wenn die Anleitung beim nächsten Feature vergessen wird — nicht bei jeder
/// Formulierungsänderung.
library;

import 'package:fahrgemeinschaft/core/widgets/mood_face.dart';
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
  backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  return backend;
}

Future<void> _openHelp(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('So funktioniert RideBuddy'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('das Menü führt zur Anleitung und zurück', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openHelp(tester);

    expect(find.text('So funktioniert RideBuddy'), findsOneWidget);
    expect(find.text('Die eine Regel'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Die Test-Gruppe hat keine Personen — zurück heißt: der Leerzustand
    // der Startseite, nicht die Rangliste.
    expect(find.text('Noch keine Personen angelegt.'), findsOneWidget);
  });

  testWidgets('die Kernaussagen stehen drin', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openHelp(tester);

    // Die Regel, an der alles hängt.
    expect(
      find.textContaining('Wer am wenigsten Punkte hat, ist dran'),
      findsOneWidget,
    );

    // Abschnitte und Kernaussagen in der Reihenfolge, in der sie auf dem
    // Screen stehen: Die Liste baut nur Sichtbares, und scrollUntilVisible
    // scrollt nur abwärts — ein einziger Durchlauf von oben nach unten.
    //
    // Titel als exakter Treffer („Woche" steht auch mitten in Sätzen),
    // Phrasen als eindeutiger Teilstring.
    final expectations = <(String, Finder)>[
      ('Übersicht', find.text('Übersicht')),
      ('Fahrt eintragen', find.text('Fahrt eintragen')),
      ('Tipp-Folge', find.textContaining('Ein drittes Mal')),
      ('Woche', find.text('Woche')),
      ('Fahrtag-Regel', find.textContaining('frühestens am Fahrtag')),
      ('Hajo', find.textContaining('Hajo')),
      ('Historie', find.text('Historie & Statistik')),
      ('Menü', find.text('Das Menü oben rechts')),
      ('Sitzplätze', find.textContaining('inklusive Fahrer')),
      ('Nie löschen', find.textContaining('Gelöscht wird niemand')),
      ('Gut zu wissen', find.text('Gut zu wissen')),
    ];
    for (final (label, finder) in expectations) {
      await tester.scrollUntilVisible(
        finder,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(finder, findsOneWidget, reason: 'Aussage „$label"');
    }
  });

  testWidgets('die echten Gesichter sind eingebunden, keine Nachbauten', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openHelp(tester);

    await tester.scrollUntilVisible(
      find.textContaining('Hajo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byType(MoodFace),
      findsWidgets,
      reason:
          'Die Anleitung zeigt dieselben Widgets wie die App — driftet das '
          'Design, driftet die Anleitung automatisch mit.',
    );
  });
}
