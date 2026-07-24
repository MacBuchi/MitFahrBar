/// admin_flow_test.dart – Gruppen-Anfragen freigeben und ablehnen.
library;

import 'package:mitfahrbar/models/group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _loginAs(WidgetTester tester, String handle) async {
  await tester.enterText(find.byType(TextField).first, handle);
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

FakeBackend _backendWithRequest() {
  final backend = FakeBackend();
  backend.addGroup(
    handle: 'verwaltung',
    password: 'geheim123',
    name: 'Verwaltung',
    isAdmin: true,
  );
  backend.addGroup(
    handle: 'pendler-nord',
    password: 'geheim123',
    name: 'Pendler Nord',
    status: GroupStatus.pending,
  );
  return backend;
}

void main() {
  testWidgets('Admin sieht offene Anfrage und gibt sie frei', (tester) async {
    final backend = _backendWithRequest();

    await pumpApp(tester, backend);
    await _loginAs(tester, 'verwaltung');

    await tester.tap(find.byIcon(Icons.admin_panel_settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Pendler Nord'), findsOneWidget);
    expect(find.textContaining('Anmeldename: pendler-nord'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Freigeben'));
    await tester.pumpAndSettle();

    // Anfrage ist abgearbeitet und die Gruppe freigeschaltet.
    expect(find.text('Keine offenen Anfragen.'), findsOneWidget);
    final approved = backend.groups.values.firstWhere(
      (g) => g.handle == 'pendler-nord',
    );
    expect(approved.status, GroupStatus.active);
  });

  testWidgets('Ablehnen schaltet die Gruppe nicht frei', (tester) async {
    final backend = _backendWithRequest();

    await pumpApp(tester, backend);
    await _loginAs(tester, 'verwaltung');
    await tester.tap(find.byIcon(Icons.admin_panel_settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Ablehnen'));
    await tester.pumpAndSettle();

    final rejected = backend.groups.values.firstWhere(
      (g) => g.handle == 'pendler-nord',
    );
    expect(rejected.status, GroupStatus.rejected);
  });

  testWidgets('normale Gruppe hat keinen Zugang zur Freigabe', (tester) async {
    final backend = _backendWithRequest();
    backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );

    await pumpApp(tester, backend);
    await _loginAs(tester, 'daciaracing');

    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
  });
}
