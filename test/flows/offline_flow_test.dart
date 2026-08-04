/// offline_flow_test.dart – Die App darf ohne Netz keine Sackgasse sein (#169).
///
/// Bis v0.59.1 zeigte das Gruppen-Gate bei einem Fehler `Text('Fehler: …')`
/// ohne Rahmen und ohne Weg zurück. Auf dem Pixel 7 Pro im Flugmodus sah man
/// nackten Ausnahmetext samt Projekt-URL und Gruppen-Kennung — und weil
/// `myGroupProvider` an `currentUserIdProvider` hängt (der sich bewusst nur
/// bei echtem An-/Abmelden ändert), lief nach der Rückkehr des Netzes von
/// allein **nichts** neu. Es half nur, die App zu beenden.
///
/// Der Test **tippt** den Knopf. Ein Test, der ihn nur findet, hätte den
/// toten Update-Knopf aus 0.37.0 auch nicht gesehen.
library;

import 'package:mitfahrbar/data/group_repository.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Ein Gruppen-Repository, das auf Kommando scheitert — wie ein Handy, das
/// gerade kein Netz hat.
class _FlakyGroupRepository implements GroupRepository {
  _FlakyGroupRepository(this.backend, {required this.failure});

  final FakeBackend backend;

  /// Solange gesetzt, scheitert jeder Lesezugriff damit.
  Object? failure;

  int calls = 0;

  @override
  Future<Group?> myGroup() async {
    calls++;
    if (failure case final error?) throw error;
    return backend.currentGroup;
  }
}

/// Der echte Wortlaut vom Gerät (Flugmodus, 05.08.2026) — samt Projekt-URL
/// und Gruppen-Kennung, die genau deshalb nicht auf den Schirm gehören.
const _offlineError =
    "ClientException with SocketException: Failed host lookup: "
    "'azrlhlcxhpwmxcinjovp.supabase.co' (OS Error: No address associated "
    "with hostname, errno = 7), uri=https://azrlhlcxhpwmxcinjovp.supabase.co"
    "/rest/v1/groups?select=%2A&id=eq.5edb7dd3-b7ec-49f5-8e6b-6997029db1a9";

Future<_FlakyGroupRepository> _loginAgainst(
  WidgetTester tester,
  FakeBackend backend,
  Object failure,
) async {
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  await backend
      .dataFor(groupId)
      .createPerson(const Person(id: '', name: 'Anna', active: true));

  final groups = _FlakyGroupRepository(backend, failure: failure);
  await pumpApp(
    tester,
    backend,
    overrides: [groupRepositoryProvider.overrideWithValue(groups)],
  );
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
  return groups;
}

void main() {
  testWidgets('ohne Netz erklärt die App den Zustand, statt zu scheitern', (
    tester,
  ) async {
    await _loginAgainst(tester, FakeBackend(), _offlineError);

    expect(find.text('Keine Verbindung'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
    // Die Tabs bleiben aus — das Gate hält, nur eben verständlich.
    expect(find.text('Wer ist dran?'), findsNothing);
  });

  testWidgets('der Rohtext des Fehlers bleibt vom Schirm', (tester) async {
    await _loginAgainst(tester, FakeBackend(), _offlineError);

    // Weder Adresse noch Gruppen-Kennung noch der Ausnahmename. Der Fehler
    // ist nicht verloren: `wireErrorReporting` meldet ihn nach
    // `error_reports` (#136) — dort gehört er hin, nicht vor die Gruppe.
    expect(find.textContaining('supabase.co'), findsNothing);
    expect(find.textContaining('5edb7dd3'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('Fehler:'), findsNothing);
  });

  testWidgets('„Erneut versuchen" holt die App wirklich zurück', (
    tester,
  ) async {
    final backend = FakeBackend();
    final groups = await _loginAgainst(tester, backend, _offlineError);

    expect(find.text('Keine Verbindung'), findsOneWidget);
    final before = groups.calls;

    // Das Netz ist zurück — und jetzt der Kern: Der Knopf wird GETIPPT.
    groups.failure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Erneut versuchen'));
    await tester.pumpAndSettle();

    expect(groups.calls, greaterThan(before));
    expect(find.text('Keine Verbindung'), findsNothing);
    expect(find.text('Wer ist dran?'), findsOneWidget);
  });

  testWidgets('ein anderer Fehler bekommt einen anderen Text', (tester) async {
    // Kein Netzproblem: Das darf nicht als „Keine Verbindung" durchgehen,
    // sonst schickt die Meldung die Gruppe auf die falsche Fährte.
    await _loginAgainst(tester, FakeBackend(), StateError('kaputt'));

    expect(find.text('Das hat nicht geklappt'), findsOneWidget);
    expect(find.text('Keine Verbindung'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('auch aus dem Fehler heraus kommt man wieder heraus', (
    tester,
  ) async {
    // Der zweite Weg weg vom Schirm — dieselbe Lehre wie beim Sperr-Schirm
    // in 0.37.0: Von einem Gate muss ein Weg wegführen, und der muss
    // geprüft sein.
    await _loginAgainst(tester, FakeBackend(), _offlineError);

    await tester.tap(find.widgetWithText(TextButton, 'Abmelden'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
  });
}
