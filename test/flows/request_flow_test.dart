/// request_flow_test.dart – „Neue Gruppe anfragen" über die echte App.
///
/// Seit die Anfrage serverseitig läuft (Edge Function `request-group`),
/// meldet sie NICHT mehr an: Die Bestätigungsseite ist ein Zwischenstand,
/// kein Login — erst die Freigabe macht die Gruppe nutzbar. Und ein
/// vergebener Anmeldename wird klar gemeldet, statt still zu scheitern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _submitRequest(WidgetTester tester, String groupName) async {
  await _tap(tester, find.text('Neue Gruppe anfragen'));
  await tester.enterText(find.byType(TextField).at(0), groupName);
  await tester.enterText(find.byType(TextField).at(1), 'pendler');
  await tester.enterText(find.byType(TextField).at(2), 'gemeinsam-geheim-1');
  await _tap(tester, find.widgetWithText(FilledButton, 'Anfrage senden'));
}

void main() {
  testWidgets('Anfrage legt ein pending-Konto an, ohne anzumelden', (
    tester,
  ) async {
    final backend = FakeBackend();
    await pumpApp(tester, backend, splash: false);
    await _submitRequest(tester, 'Pendler Musterstadt');

    expect(find.text('Anfrage gestellt'), findsOneWidget);
    expect(
      backend.currentEmail,
      isNull,
      reason: 'Die Anfrage meldet nicht an — sie bleibt eine Anfrage.',
    );
    expect(
      backend.accounts.keys,
      contains('pendler@grp.fahrgemeinschaft.app'),
      reason: 'Das Gruppen-Konto existiert und wartet auf Freigabe.',
    );
  });

  testWidgets('gedrosselte Anlage wird ehrlich erklärt', (tester) async {
    final backend = FakeBackend()..signupThrottled = true;
    await pumpApp(tester, backend, splash: false);
    await _submitRequest(tester, 'Zu viele');

    expect(
      find.textContaining('ungewöhnlich viele Anfragen'),
      findsOneWidget,
      reason:
          'Die Drossel (Missbrauchsschutz #69) darf nicht wie ein '
          'technischer Fehler aussehen — sonst hagelt es Rückmeldungen.',
    );
    expect(
      backend.accounts,
      isEmpty,
      reason: 'Gedrosselt heißt: nichts angelegt.',
    );
  });

  testWidgets('vergebener Anmeldename wird klar gemeldet', (tester) async {
    final backend = FakeBackend();
    backend.addGroup(handle: 'pendler', password: 'geheim123', name: 'Pendler');
    await pumpApp(tester, backend, splash: false);
    await _submitRequest(tester, 'Zweite Gruppe');

    expect(find.text('Der Anmeldename ist schon vergeben.'), findsOneWidget);
    expect(find.text('Anfrage gestellt'), findsNothing);
  });
}
