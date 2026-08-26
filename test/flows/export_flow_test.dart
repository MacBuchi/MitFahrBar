/// export_flow_test.dart – CSV-Export über die echte App.
///
/// Das Format selbst prüft `csv_export_test.dart`; hier geht es um den Weg
/// dorthin: Menüeintrag, geladener Stand, Rückmeldung an die Nutzerin.
library;

import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Fängt ab, was die App auf die Plattform schreiben würde.
class _CapturedFile {
  String? name;
  String? content;
  List<String> names = const [];
  int calls = 0;
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _export(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fahrten exportieren (CSV)'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  late _CapturedFile captured;
  late List<Override> overrides;

  setUp(() {
    backend = FakeBackend();
    captured = _CapturedFile();
    overrides = [
      fileSaverProvider.overrideWithValue((files) async {
        // Die Fahrten-Datei ist die erste; daneben liegt seit #272 die
        // Parameter-Datei. Der Test greift gezielt zu, statt „die eine
        // Datei" anzunehmen — sonst wäre nicht zu sehen, wenn die Sicherung
        // stillschweigend auf eine Datei zurückfiele.
        captured
          ..name = files.first.name
          ..content = files.first.content
          ..names = [for (final f in files) f.name]
          ..calls += 1;
      }),
    ];
  });

  Future<String> setUpGroup({
    List<String> names = const ['Anna', 'Bernd'],
    bool withTrip = true,
  }) async {
    final id = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(id);
    final ids = <String, String>{};
    for (final name in names) {
      final person = await data.createPerson(
        Person(id: '', name: name, active: true),
      );
      ids[name] = person.id;
    }
    if (withTrip && names.length >= 2) {
      await data.createTrip(DateTime(2026, 3, 9), {
        ids[names[0]]!: ParticipationStatus.driver,
        ids[names[1]]!: ParticipationStatus.passenger,
      });
    }
    return id;
  }

  testWidgets('Export liefert Kopfzeile und die eingetragene Fahrt', (
    tester,
  ) async {
    await setUpGroup();
    await pumpApp(tester, backend, overrides: overrides);
    await _login(tester);
    await _export(tester);

    expect(captured.calls, 1);
    expect(captured.name, endsWith('.csv'));
    expect(captured.content, isNotNull);

    final lines = captured.content!
        .split('\r\n')
        .where((l) => l.isNotEmpty)
        .toList();
    expect(lines.first, '﻿Datum;Anna;Bernd;Notiz');
    expect(lines[1], '09.03.2026;Fahrer;Mit;');
  });

  testWidgets('meldet die Anzahl der Fahrten zurück', (tester) async {
    await setUpGroup();
    await pumpApp(tester, backend, overrides: overrides);
    await _login(tester);
    await _export(tester);

    expect(
      find.text('2 Dateien erstellt: 1 Fahrten und die Parameter.'),
      findsOneWidget,
    );
  });

  testWidgets('die Sicherung enthält die Parameter, nie die Archiv-Preise', (
    tester,
  ) async {
    // #272: Die Parameter-Datei liegt neben den Fahrten — die Wochenwerte
    // des Preisarchivs aber NICHT. Sie stehen unter CC BY-NC-SA, und eine
    // weiterreichbare Datei wäre die Weitergabe, die die ShareAlike-Klausel
    // auslöst (test/price_archive_license_test.dart).
    await setUpGroup();
    await pumpApp(tester, backend, overrides: overrides);
    await _login(tester);
    await _export(tester);

    expect(captured.names, hasLength(2));
    expect(captured.names.first, contains('fahrten'));
    expect(captured.names.last, contains('parameter'));
    expect(
      captured.names.any((n) => n.contains('preis') || n.contains('sprit')),
      isFalse,
      reason: 'Eine Preis-Datei wäre die Weitergabe der Archivwerte.',
    );
  });

  testWidgets('ohne Fahrten entsteht die Vorlage, nicht ein Fehler', (
    tester,
  ) async {
    await setUpGroup(withTrip: false);
    await pumpApp(tester, backend, overrides: overrides);
    await _login(tester);
    await _export(tester);

    expect(captured.calls, 1);
    expect(
      captured.content!.split('\r\n').where((l) => l.isNotEmpty),
      hasLength(1),
    );
    expect(
      find.text('Leere Vorlage mit allen Personen-Spalten erstellt.'),
      findsOneWidget,
    );
  });

  testWidgets('ein fehlgeschlagener Export sagt das auch', (tester) async {
    await setUpGroup();
    await pumpApp(
      tester,
      backend,
      overrides: [
        fileSaverProvider.overrideWithValue((files) async {
          throw StateError('kein Teilen-Menü');
        }),
      ],
    );
    await _login(tester);
    await _export(tester);

    expect(find.text('Export fehlgeschlagen.'), findsOneWidget);
  });
}
