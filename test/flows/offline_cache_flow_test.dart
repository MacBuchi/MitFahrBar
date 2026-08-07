/// offline_cache_flow_test.dart – Die App startet ohne Netz aus dem letzten
/// bekannten Stand (#169).
///
/// Der Ablauf ist der echte: einmal mit Empfang öffnen, dann ohne. Zwischen
/// beiden Läufen bleibt nur der Zwischenspeicher stehen — die App wird neu
/// aufgebaut wie nach einem Neustart auf dem Gerät.
library;

import 'package:mitfahrbar/data/caching_repository.dart';
import 'package:mitfahrbar/data/carpool_repository.dart';
import 'package:mitfahrbar/data/group_repository.dart';
import 'package:mitfahrbar/data/offline_cache.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_note.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Ein Schalter, den beide Dekorierer teilen — „Flugmodus" für den Test.
class _Wire {
  bool offline = false;

  Never boom() => throw Exception('ClientException with SocketException');
}

class _WiredGroup implements GroupRepository {
  _WiredGroup(this.inner, this.wire);

  final GroupRepository inner;
  final _Wire wire;

  @override
  Future<Group?> myGroup() async =>
      wire.offline ? wire.boom() : inner.myGroup();
}

class _WiredCarpool implements CarpoolRepository {
  _WiredCarpool(this.inner, this.wire);

  final CarpoolRepository inner;
  final _Wire wire;

  Future<T> _read<T>(Future<T> Function() read) async =>
      wire.offline ? wire.boom() : read();

  @override
  Future<List<Person>> loadPersons() => _read(inner.loadPersons);

  @override
  Future<List<Trip>> loadTrips() => _read(inner.loadTrips);

  @override
  Future<AppSettings> loadSettings() => _read(inner.loadSettings);

  @override
  Future<GroupDefaults> loadGroupDefaults() => _read(inner.loadGroupDefaults);

  @override
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7}) =>
      _read(() => inner.loadPlan(from, days: days));

  @override
  Future<List<PlanNote>> loadNotes(DateTime from, {int days = 7}) =>
      _read(() => inner.loadNotes(from, days: days));

  @override
  Future<Map<DateTime, GroupDefaults>> loadPlanDefaults(
    DateTime from, {
    int days = 7,
  }) => _read(() => inner.loadPlanDefaults(from, days: days));

  @override
  Future<void> savePlanDefaults(DateTime date, GroupDefaults defaults) =>
      inner.savePlanDefaults(date, defaults);

  @override
  Future<Person> createPerson(Person person) => inner.createPerson(person);

  @override
  Future<void> updatePerson(Person person) => inner.updatePerson(person);

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) => inner.createTrip(date, participations, note: note);

  @override
  Future<void> updateTrip(Trip trip) => inner.updateTrip(trip);

  @override
  Future<void> deleteTrip(String tripId) => inner.deleteTrip(tripId);

  @override
  Future<void> saveSettings(AppSettings settings) =>
      inner.saveSettings(settings);

  @override
  Future<void> saveGroupDefaults(GroupDefaults defaults) =>
      inner.saveGroupDefaults(defaults);

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) => inner.setAvailability(date, personId, ride);

  @override
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds) =>
      inner.setPlanDrivers(date, driverIds);

  @override
  Future<void> addNote(DateTime date, String personId, String body) =>
      inner.addNote(date, personId, body);

  @override
  Future<void> deleteNote(String noteId) => inner.deleteNote(noteId);
}

void main() {
  testWidgets('ohne Netz öffnet die App den letzten Stand und sagt es', (
    tester,
  ) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    await backend
        .dataFor(groupId)
        .createPerson(const Person(id: '', name: 'Anna', active: true));

    final wire = _Wire();
    final cache = InMemoryOfflineCache(
      clock: () => DateTime(2026, 7, 22, 7, 12),
    );
    final status = OfflineStatus();

    List<Override> wiring() => [
      groupRepositoryProvider.overrideWithValue(
        CachingGroupRepository(
          _WiredGroup(FakeGroupRepository(backend), wire),
          cache,
          status,
          () => groupId,
        ),
      ),
      carpoolRepositoryProvider.overrideWithValue(
        CachingCarpoolRepository(
          _WiredCarpool(FakeRoutingCarpoolRepository(backend), wire),
          cache,
          status,
          () => groupId,
        ),
      ),
      offlineStatusProvider.overrideWithValue(status),
      offlineCacheProvider.overrideWithValue(cache),
    ];

    Future<void> openAndLogIn() async {
      await pumpApp(tester, backend, overrides: wiring());
      // Beim zweiten Öffnen steht die Anmeldung schon — das Fake-Backend
      // behält sie, genau wie Supabase die Sitzung auf dem Gerät. Das ist
      // der Grund, warum ohne Netz überhaupt nur das Gruppen-Gate im Weg
      // steht und nicht der Login.
      if (find.widgetWithText(FilledButton, 'Anmelden').evaluate().isEmpty) {
        return;
      }
      await tester.enterText(find.byType(TextField).first, 'daciaracing');
      await tester.enterText(find.byType(TextField).last, 'geheim123');
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();
    }

    // Erster Lauf: mit Empfang. Nichts Auffälliges, keine Leiste.
    await openAndLogIn();
    expect(find.text('Wer ist dran?'), findsOneWidget);
    expect(find.textContaining('Offline'), findsNothing);

    // Zweiter Lauf: kein Netz mehr. Vor v0.61.0 wäre hier Schluss gewesen —
    // das Gruppen-Gate hätte den Erklär-Schirm aus v0.60.0 gezeigt und die
    // App wäre leer geblieben.
    wire.offline = true;
    await openAndLogIn();

    expect(find.text('Wer ist dran?'), findsOneWidget);
    expect(find.text('Anna'), findsWidgets);
    expect(find.text('Keine Verbindung'), findsNothing);

    // Und der Stand wird benannt, nicht als aktuell ausgegeben.
    expect(find.textContaining('Offline · Stand heute 07:12'), findsOneWidget);
  });
}
