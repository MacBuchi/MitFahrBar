/// licenses_flow_test.dart – Der Weg zu den Lizenzen über die echte App.
library;

import 'package:fahrgemeinschaft/models/person.dart';
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

// Die SIL OFL der beiden Schriften verlangt, dass ihr Lizenztext beim Nutzer
// ankommt — ein registrierter Text ohne erreichbaren Einstieg erfüllt das
// nicht. Fällt der Menü-Eintrag bei einem Umbau still weg, merkt es sonst
// niemand.
void main() {
  testWidgets('das Konto-Menü führt zu den Open-Source-Lizenzen', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend);
    await _login(tester);

    await tester.tap(find.byTooltip('Zugang'));
    await tester.pumpAndSettle();

    expect(
      find.text('Open-Source-Lizenzen'),
      findsOneWidget,
      reason:
          'Ohne diesen Einstieg ist der Lizenztext der Schriften in der App '
          'nicht erreichbar.',
    );

    await tester.tap(find.text('Open-Source-Lizenzen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(LicensePage),
      findsOneWidget,
      reason: 'Der Eintrag muss die Lizenzseite öffnen.',
    );
  });
}
