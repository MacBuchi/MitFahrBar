/// update_required_flow_test.dart – Sperre für zu alte Clients, echte App.
///
/// Die Logik prüft `update_check_test.dart`. Hier geht es um die Stelle, an
/// der sie sitzt: Der Schirm liegt über allem, auch über dem Login — und er
/// darf nur dann auftauchen, wenn er wirklich soll.
library;

import 'package:fahrgemeinschaft/core/update_check.dart';
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
}
