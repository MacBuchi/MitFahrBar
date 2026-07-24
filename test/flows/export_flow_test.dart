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
      fileSaverProvider.overrideWithValue(({
        required String name,
        required String content,
      }) async {
        captured
          ..name = name
          ..content = content
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

    expect(find.text('CSV mit 1 Fahrten erstellt.'), findsOneWidget);
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
        fileSaverProvider.overrideWithValue(({
          required String name,
          required String content,
        }) async {
          throw StateError('kein Teilen-Menü');
        }),
      ],
    );
    await _login(tester);
    await _export(tester);

    expect(find.text('Export fehlgeschlagen.'), findsOneWidget);
  });
}
