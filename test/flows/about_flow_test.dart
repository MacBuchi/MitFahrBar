/// about_flow_test.dart – „Über MitFahrBar" über die echte App erreicht.
///
/// Der Dialog beantwortet, was sonst nirgends stand (25.07.2026): welche
/// Version läuft, was sich mit ihr geändert hat — und er führt zum
/// Update, wenn eines bereitsteht. Geprüft werden die drei Zustände:
/// nüchtern (nur Version), mit Notes, mit verfügbarem Update.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/core/widgets/mitfahrbar_mark.dart';

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

Future<void> _openAbout(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  // Das Menü scrollt auf der kleinen Test-Fläche — den Eintrag erst ins
  // Bild holen, sonst tippt der Test ins Leere (wie beim Lizenzen-Flow).
  await tester.ensureVisible(find.text('Über MitFahrBar'));
  await tester.tap(find.text('Über MitFahrBar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('der Dialog zeigt Marke und laufende Version', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openAbout(tester);

    // pumpApp stellt die Version fest auf 1.0.0.
    expect(find.text('Version 1.0.0'), findsOneWidget);
    expect(find.byType(MitFahrBarWordmark), findsOneWidget);
    // Ohne Netz (Override liefert null) gibt es keinen Notes-Abschnitt
    // und ohne Update keinen Update-Knopf — nüchtern, kein Fehlerbalken.
    expect(find.text('Was ist neu in dieser Version:'), findsNothing);
    expect(find.textContaining('ist verfügbar'), findsNothing);

    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('Version 1.0.0'), findsNothing);
  });

  testWidgets('die Release-Notes der laufenden Version stehen geglättet drin', (
    tester,
  ) async {
    await pumpApp(
      tester,
      _backend(),
      overrides: [
        currentReleaseNotesProvider.overrideWith(
          (ref) => Future.value(
            '## Behoben\n\n- **Die Reifen** sind im dunklen Design sichtbar.',
          ),
        ),
      ],
    );
    await _login(tester);
    await _openAbout(tester);

    expect(find.text('Was ist neu in dieser Version:'), findsOneWidget);
    // Geglättet wie im Update-Dialog: keine Rauten, keine Sternchen.
    expect(
      find.textContaining('Die Reifen sind im dunklen Design sichtbar.'),
      findsOneWidget,
    );
    expect(find.textContaining('**'), findsNothing);
  });

  testWidgets('steht ein Update bereit, führt der Dialog dorthin', (
    tester,
  ) async {
    final backend = _backend();
    backend.update = const UpdateInfo(
      latestVersion: '2.0.0',
      releaseUrl: 'https://example.invalid/release',
    );
    await pumpApp(tester, backend);
    await _login(tester);
    await _openAbout(tester);

    final button = find.text('Version 2.0.0 ist verfügbar');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    // „Über" ist zu, der Update-Dialog offen.
    expect(find.text('Version 1.0.0'), findsNothing);
    expect(find.text('Version 2.0.0 verfügbar'), findsOneWidget);
  });
  testWidgets('die Datenquellen sind genannt — das ist Lizenzpflicht', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openAbout(tester);

    // Jede Quelle verlangt eine Nennung: CC BY 4.0 bei den Live-Spritpreisen,
    // CC BY-NC-SA 4.0 beim historischen Preisarchiv, ODbL bei OpenStreetMap.
    // Verschwindet eine still, ist das kein Schönheitsfehler, sondern ein
    // Lizenzverstoß — und niemandem fiele es auf, weil nichts kaputtgeht.
    expect(find.text('Woher die Daten kommen'), findsOneWidget);
    expect(find.textContaining('Tankerkönig'), findsOneWidget);
    expect(find.textContaining('CC BY 4.0'), findsOneWidget);
    // Die zurückliegenden Wochen stammen aus dem Archiv, und das steht unter
    // einer ANDEREN Lizenz als die API. Eine Nennung für beide wäre falsch.
    expect(find.textContaining('CC BY-NC-SA 4.0'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(find.textContaining('ODbL'), findsOneWidget);
  });
}
