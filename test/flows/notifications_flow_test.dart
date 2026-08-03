/// notifications_flow_test.dart – Benachrichtigungen einrichten (Issue #101).
///
/// **Wer** benachrichtigt wird, steht seit #121 nicht mehr hier, sondern in
/// der Geräte-Zuordnung (`identity_flow_test.dart`). Hier bleibt: ob dieses
/// Gerät welche bekommt, wann — und dass die Zuordnung an der Gruppe hängt,
/// sonst bekäme ein Gerät nach einem Gruppenwechsel weiter die Nachrichten der
/// alten.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/data/push_repository.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Steht für alles, was beim Laden schiefgehen kann: fehlende Tabelle,
/// abgelehnte RLS, kein Netz.
class _BrokenPushRepository extends NoopPushRepository {
  @override
  Future<PushState> stateFor(String token) async =>
      throw StateError('keine Tabelle');
}

class _Fixture {
  const _Fixture(this.backend, this.anna, this.ben);
  final FakeBackend backend;
  final String anna;
  final String ben;
}

Future<_Fixture> _backend() async {
  final backend = FakeBackend();
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(groupId);
  final anna = await data.createPerson(
    const Person(id: '', name: 'Anna', active: true),
  );
  final ben = await data.createPerson(
    const Person(id: '', name: 'Ben', active: true),
  );
  await data.createPerson(const Person(id: '', name: 'Alt', active: false));
  return _Fixture(backend, anna.id, ben.id);
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Benachrichtigungen'));
  await tester.pumpAndSettle();
}

/// Hohe Fläche: Seit #164 stehen unter den Zeiten noch Erinnerung und
/// Vorlauf. Auf der Standardgröße liegen sie außerhalb, und eine ListView
/// baut, was sie nicht zeigt, gar nicht erst.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Der Hauptschalter — seit #121 der Einschalter statt der Personen-Auswahl.
Future<void> _toggle(WidgetTester tester) async {
  await tester.tap(find.text('Benachrichtigungen auf diesem Gerät'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wer einschaltet, bekommt die Vorbelegung angelegt', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);

    // Vorher gibt es nichts — keine Zeile heißt keine Benachrichtigungen.
    expect(push.prefs, isEmpty);
    expect(find.text('Abends der Blick auf morgen'), findsNothing);
    // Für wen es gilt, sagt der Schalter — gewählt wird es im Menü.
    expect(find.text('für Anna'), findsOneWidget);

    await _toggle(tester);

    expect(push.prefs, hasLength(1));
    final prefs = push.prefs.values.single;
    expect(prefs.personId, f.anna);
    expect(prefs.eveningTime.format(), '21:00');
    expect(prefs.departureTime.format(), '07:30');
    expect(prefs.eveningEnabled, isTrue);
    expect(find.text('Abends der Blick auf morgen'), findsOneWidget);
  });

  // Die Zuordnung im Menü ist die Wahrheit, `push_devices` folgt ihr. Ohne
  // diesen Abgleich bekäme das Gerät nach einem Wechsel weiter die Meldungen
  // der vorigen Person — und niemand käme darauf, warum.
  testWidgets('eine geänderte Zuordnung zieht die Zustellung nach', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);
    expect(push.devices['test-token']?.$2, f.anna);

    // Zurück und im Menü auf Ben umstellen.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ich bin'));
    await tester.pumpAndSettle();
    // „Ben" steht auch im Ranking hinter dem Dialog — auf den im Dialog
    // eingrenzen, sonst tippt der Test auf die Übersicht.
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Ben')),
    );
    await tester.pumpAndSettle();

    await _open(tester);

    expect(push.devices['test-token']?.$2, f.ben);
    expect(find.text('für Ben'), findsOneWidget);
  });

  testWidgets('ein Schalter landet sofort in den Einstellungen', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    await tester.tap(find.text('Änderungen bis zur Abfahrt'));
    await tester.pumpAndSettle();

    expect(push.prefs.values.single.changesEnabled, isFalse);
  });

  // Die beiden Schalter sehen gleichwertig aus, sind es aber nicht:
  // `dueMessages` meldet eine Änderung nur, wenn für den Tag schon ein
  // Abend-Push protokolliert ist. Ohne Abend-Blick entsteht diese Zeile nie
  // — „Änderungen bis zur Abfahrt" liefe also leer, während der Untertitel
  // etwas anderes verspricht. Wer nur die Abendmeldung zu viel findet,
  // verlöre stillschweigend beides und merkte es erst, wenn eine Umstellung
  // unbemerkt bleibt.
  testWidgets('ohne Abend-Blick sperrt der Änderungs-Schalter und sagt warum', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    SwitchListTile changes() => tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Änderungen bis zur Abfahrt'),
    );
    expect(changes().onChanged, isNotNull);

    await tester.tap(find.text('Abends der Blick auf morgen'));
    await tester.pumpAndSettle();

    expect(
      changes().onChanged,
      isNull,
      reason:
          'Ein bedienbarer Schalter, der nichts bewirkt, ist schlimmer als '
          'gar keiner.',
    );
    expect(
      changes().value,
      isFalse,
      reason: 'Er soll sich als aus lesen, solange er wirkungslos ist.',
    );
    expect(find.textContaining('Braucht den Abend-Blick'), findsOneWidget);
    expect(
      push.prefs.values.single.changesEnabled,
      isTrue,
      reason:
          'Nur die Anzeige folgt, der gespeicherte Wert nicht — sonst müsste '
          'man ihn nach dem Wiedereinschalten neu setzen.',
    );

    await tester.tap(find.text('Abends der Blick auf morgen'));
    await tester.pumpAndSettle();

    expect(changes().onChanged, isNotNull);
    expect(
      changes().value,
      isTrue,
      reason: 'Die eigene Einstellung ist wieder da, unverändert.',
    );
  });

  // Die Abfahrts-Erinnerung (#164) hängt an den Gruppenzeiten (#139) — ohne
  // sie liefe der Schalter genauso leer wie der Änderungs-Schalter ohne
  // Abend-Blick. Gesperrt wird er deshalb nicht stumm: Der Untertitel sagt,
  // wo die Zeiten herkommen.
  testWidgets('ohne Gruppenzeiten sperrt die Erinnerung und sagt woher', (
    tester,
  ) async {
    _tall(tester);
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    SwitchListTile reminder() => tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Erinnerung zur Abfahrt'),
    );
    expect(reminder().onChanged, isNull);
    expect(reminder().value, isFalse);
    expect(find.textContaining('Fahrt & Treffpunkt'), findsOneWidget);
  });

  testWidgets('mit Gruppenzeiten lässt sie sich einschalten', (tester) async {
    _tall(tester);
    final f = await _backend();
    await f.backend
        .dataFor('group-1')
        .saveGroupDefaults(const GroupDefaults(outboundTime: DayTime(7, 30)));
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    // Vorgabe AUS — das ist die Entscheidung, nicht die Vorsicht.
    expect(push.prefs.values.single.remindersEnabled, isFalse);

    await tester.tap(find.text('Erinnerung zur Abfahrt'));
    await tester.pumpAndSettle();
    expect(push.prefs.values.single.remindersEnabled, isTrue);
    expect(
      push.prefs.values.single.reminderLeadMinutes,
      15,
      reason: 'Die Vorbelegung kommt aus defaultReminderLead.',
    );

    // Der Vorlauf ist eine Dauer, keine Uhrzeit — deshalb eine Auswahl.
    await tester.tap(find.text('Vorlauf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 Minuten'));
    await tester.pumpAndSettle();
    expect(push.prefs.values.single.reminderLeadMinutes, 30);
  });

  testWidgets('der Vorlauf ist gesperrt, solange die Erinnerung aus ist', (
    tester,
  ) async {
    _tall(tester);
    final f = await _backend();
    await f.backend
        .dataFor('group-1')
        .saveGroupDefaults(const GroupDefaults(outboundTime: DayTime(7, 30)));
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Vorlauf')).enabled,
      isFalse,
      reason:
          'Eine Dauer einzustellen für etwas, das nicht kommt, ist dieselbe '
          'Falle wie ein Schalter ohne Wirkung.',
    );
  });

  testWidgets('sie ist unabhängig vom Abend-Blick', (tester) async {
    _tall(tester);
    final f = await _backend();
    await f.backend
        .dataFor('group-1')
        .saveGroupDefaults(const GroupDefaults(outboundTime: DayTime(7, 30)));
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    await tester.tap(find.text('Abends der Blick auf morgen'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Erinnerung zur Abfahrt'),
          )
          .onChanged,
      isNotNull,
      reason:
          'Anders als die Änderungs-Meldung braucht sie keinen Abend-Push in '
          'push_log — sie hängt an der Uhr der Gruppe. Wer nur den Schubs '
          'kurz vorher will, bekommt ihn auch allein.',
    );
  });

  testWidgets('Ausschalten nimmt das Gerät aus der Zustellung', (tester) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);
    await _toggle(tester);

    expect(push.devices['test-token'], isNull);
    expect(find.text('Abends der Blick auf morgen'), findsNothing);
    expect(
      push.prefs,
      hasLength(1),
      reason:
          'Die Einstellungen der Person bleiben stehen — ein zweites Gerät '
          'derselben Person soll nicht mit abgeschaltet werden.',
    );
  });

  testWidgets('die Test-Benachrichtigung geht an dieses Gerät', (tester) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    // Der Knopf steht unten in der Liste: Was nicht im Blickfeld ist, baut
    // die ListView gar nicht erst — vor dem Tippen also hinscrollen.
    await tester.scrollUntilVisible(
      find.text('Test-Benachrichtigung senden'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test-Benachrichtigung senden'));
    await tester.pumpAndSettle();

    expect(push.tests, ['test-token']);
    expect(
      find.textContaining('Startbildschirm'),
      findsOneWidget,
      reason:
          'Solange die App vorne ist, zeigt weder Android noch der Browser '
          'eine Benachrichtigung an — ohne diesen Hinweis wartet man auf '
          'etwas, das erst beim Wechseln erscheint.',
    );
  });

  // Der Knopf darf keinen Erfolg behaupten, den er nicht geprüft hat —
  // dieselbe Klasse Fehler wie der tote Update-Knopf in 0.37.0. Die Function
  // antwortet auch bei gescheitertem Versand mit 200 und meldet den Ausgang
  // je Gerät im Rumpf.
  testWidgets('ein abgelehnter Versand wird als Fehlschlag gemeldet', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend)..testAccepted = false;
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);

    await tester.scrollUntilVisible(
      find.text('Test-Benachrichtigung senden'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test-Benachrichtigung senden'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Konnte nicht zugestellt werden'), findsOne);
    expect(
      find.textContaining('Unterwegs'),
      findsNothing,
      reason: 'Ein Fehlschlag darf nie wie ein geglückter Versand aussehen.',
    );
  });

  // Die Kernursache von 0.39.0: Trifft eine Nachricht ein, während die App
  // vorne ist, zeigt sie weder Android noch der Service Worker an — FCM
  // liefert sie ausschließlich an `onMessage`. Bis dahin hörte niemand zu,
  // und die Nachricht verschwand spurlos. Nicht nur beim Test-Knopf: Auch
  // der echte Abend-Versand verpuffte, wenn jemand die App zufällig offen
  // hatte — und weil der Job ihn als zugestellt verbucht, kam er nie wieder.
  testWidgets('eine eintreffende Nachricht wird auch außerhalb des '
      'Benachrichtigungs-Screens sichtbar', (tester) async {
    final f = await _backend();
    await pumpApp(tester, f.backend);
    await _login(tester);

    // Wir stehen auf der Übersicht — der Screen, auf dem man am ehesten ist.
    expect(find.text('Wer ist dran?'), findsOneWidget);

    f.backend.deliverPush('Morgen (Mo, 27.07.)', 'Du fährst · dabei: Ben');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Morgen (Mo, 27.07.)'),
      findsOneWidget,
      reason:
          'Der Handler gehört global in app.dart (scaffoldMessengerKey). In '
          'einem einzelnen Screen verdrahtet zeigte er nichts, sobald man '
          'woanders steht — also fast immer.',
    );
    expect(find.textContaining('Du fährst'), findsOneWidget);
  });

  testWidgets('ohne Berechtigung bleibt der Screen leer statt kaputt', (
    tester,
  ) async {
    final f = await _backend();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [
        // Kein Token = abgelehnt oder nicht unterstützt.
        pushTokenProvider.overrideWithValue(
          ({required bool ask}) async => null,
        ),
      ],
    );
    await _login(tester);
    await _open(tester);

    expect(find.text('Abends der Blick auf morgen'), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(
              SwitchListTile,
              'Benachrichtigungen auf diesem Gerät',
            ),
          )
          .onChanged,
      isNotNull,
      reason:
          'Der Schalter bleibt bedienbar: Erst beim Einschalten wird gefragt '
          '— ein Screen, der ohne Berechtigung gar nichts anbietet, führt in '
          'die Sackgasse.',
    );
  });

  testWidgets('ein Fehler beim Laden endet nicht im ewigen Ladekreis', (
    tester,
  ) async {
    final f = await _backend();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [
        pushRepositoryProvider.overrideWithValue(_BrokenPushRepository()),
      ],
    );
    await _login(tester);
    await _open(tester);

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'Ohne catch in _load verschwindet die Ausnahme still in der '
          'async-Funktion, _loading bleibt true — und der Screen sieht aus '
          'wie ein Hänger. Genau so aufgefallen, als die Tabellen in '
          'Produktion noch fehlten.',
    );
    expect(find.textContaining('nicht geladen werden'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('ein Gerät der einen Gruppe zeigt in der anderen nichts', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    f.backend.addGroup(
      handle: 'andere',
      password: 'geheim123',
      name: 'Andere Gruppe',
    );
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _toggle(tester);
    expect(push.devices['test-token']?.$2, isNotNull);

    // Dasselbe Gerät, dasselbe Token, andere Gruppe angemeldet. Geprüft wird
    // hier bewusst am Repository statt über einen zweiten Login-Durchlauf:
    // An- und Abmelden hat mit auth_flow_test.dart einen eigenen Test, und
    // der Inhalt dieses hier ist die Mandantengrenze.
    f.backend.setCurrentEmail('andere@grp.fahrgemeinschaft.app');
    await tester.pumpAndSettle();

    expect(
      (await push.stateFor('test-token')).personId,
      isNull,
      reason:
          'Die Zuordnung gehört der Gruppe. Sähe die zweite Gruppe sie, '
          'liefe sie beim Zuordnen in eine Unique-Verletzung auf einer '
          'Zeile, die die RLS ihr nicht einmal zeigen darf.',
    );
  });
}
