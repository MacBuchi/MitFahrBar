/// update_required_flow_test.dart – Sperre für zu alte Clients, echte App.
///
/// Die Logik prüft `update_check_test.dart`. Hier geht es um die Stelle, an
/// der sie sitzt: Der Schirm liegt über allem, auch über dem Login — er darf
/// nur dann auftauchen, wenn er wirklich soll, **und von ihm muss ein Weg
/// wegführen**.
///
/// Der zweite Teil fehlte bis 0.38.0, und das hat gekostet: Geprüft war nur,
/// DASS der Schirm erscheint, nie dass sein Knopf etwas tut. Er tat nichts —
/// der Schirm ersetzt den Router-Navigator, also fand `showDialog` keinen,
/// warf, und Flutter schluckte die Exception. Auf dem Gerät (Pixel 7,
/// 26.07.2026) blieb nur Deinstallieren und Neuinstallieren von Hand.
/// Ein sichtbarer Schirm ist eben nur die halbe Zusage.
library;

import 'package:mitfahrbar/core/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

FakeBackend _backend({String? minimum, bool updateAvailable = true}) {
  final backend = FakeBackend()..minSupportedVersion = minimum;
  backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  if (updateAvailable) {
    backend.update = const UpdateInfo(
      latestVersion: '9.9.9',
      releaseUrl: 'https://example.invalid/release',
    );
  }
  return backend;
}

void main() {
  // pumpApp setzt die laufende Version auf 1.0.0.
  testWidgets('ein zu alter Client kommt nicht einmal zum Login', (
    tester,
  ) async {
    await pumpApp(tester, _backend(minimum: '2.0.0'));

    expect(find.text('Update erforderlich'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Anmelden'),
      findsNothing,
      reason: 'Wer ausgesperrt ist, soll sich gar nicht erst anmelden.',
    );
    expect(find.textContaining('9.9.9'), findsOneWidget);
  });

  testWidgets('mit passender Version läuft die App normal', (tester) async {
    await pumpApp(tester, _backend(minimum: '1.0.0'));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
  });

  // Der Regelfall bis zur ersten erzwungenen Version — und zugleich der
  // Offline-Fall, in dem die Mindestversion unbekannt bleibt.
  testWidgets('ohne Mindestversion sperrt nichts', (tester) async {
    await pumpApp(tester, _backend());

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
  });

  // Die wichtigste Zusage: Wer schon auf dem Neuesten ist, wird nie
  // ausgesperrt — sonst gäbe es keinen Weg zurück in die App.
  testWidgets('ohne verfügbares Update sperrt selbst Unsinn nicht', (
    tester,
  ) async {
    await pumpApp(tester, _backend(minimum: '99.0.0', updateAvailable: false));

    expect(find.text('Update erforderlich'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
  });

  // Der eigentliche Regressionstest: Ein Schirm, dessen Knopf nichts tut, ist
  // schlimmer als gar kein Schirm — dann führt kein Weg mehr aus der App
  // heraus außer Deinstallieren.
  testWidgets('der Knopf auf dem Schirm öffnet wirklich den Update-Dialog', (
    tester,
  ) async {
    await pumpApp(tester, _backend(minimum: '2.0.0'));
    expect(find.text('Update erforderlich'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Update installieren'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'Ohne eigenen Navigator wirft showDialog hier „Navigator operation '
          'requested with a context that does not include a Navigator" — die '
          'Exception landet im Framework, und auf dem Gerät passiert sichtbar '
          'nichts.',
    );
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'Der Schirm braucht einen eigenen Navigator (siehe app.dart).',
    );
  });

  // Die zweite Rettungsleine, absichtlich ohne Dialog: Sie muss auch dann
  // noch tragen, wenn am Navigator wieder etwas kaputtgeht.
  testWidgets('daneben steht ein Weg, der ohne Dialog auskommt', (
    tester,
  ) async {
    await pumpApp(tester, _backend(minimum: '2.0.0'));

    final browser = find.widgetWithText(
      TextButton,
      'Stattdessen im Browser laden',
    );
    expect(
      browser,
      findsOneWidget,
      reason:
          'Der einzige Update-Weg, der weder Navigator noch Overlay braucht. '
          'Fällt er weg, hängt wieder alles an einer einzigen Mechanik.',
    );

    await tester.tap(browser);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Auch ohne erreichbaren Browser darf der Tap nicht werfen — der '
          'Screen meldet den Fehlschlag selbst und zeigt die Adresse.',
    );
  });
}
