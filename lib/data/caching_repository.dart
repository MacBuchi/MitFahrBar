/// caching_repository.dart – Repositories, die den letzten bekannten Stand
/// zurückgeben, wenn das Netz schweigt (Issue #169).
///
/// Dekorierer statt Umbau: Die Provider bleiben, wie sie sind, und die echten
/// Repositories wissen nichts davon. Damit liegt die ganze Regel „was
/// passiert ohne Netz" an einer Stelle — und die Fakes der Testsuite laufen
/// unverändert daran vorbei.
///
/// **Nur Lesezugriffe.** Schreiben wird durchgereicht und scheitert ohne Netz
/// ehrlich. Ein „später hochschieben"-Korb wäre ein eigenes Vorhaben: Er
/// müsste beantworten, was passiert, wenn zwei Leute denselben Tag offline
/// unterschiedlich eintragen, und er kollidierte mit „die Existenz einer
/// Zeile in `trips` **ist** die Bestätigung". Bewusst nicht gebaut
/// (entschieden mit Marcus, 05.08.2026).
library;

import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/group_defaults.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
import '../models/trip.dart';
import 'carpool_repository.dart';
import 'group_repository.dart';
import 'offline_cache.dart';

/// Woher der zuletzt gezeigte Stand kam.
///
/// `value == null` heißt „frisch vom Server", sonst steht dort der Zeitpunkt,
/// an dem der gezeigte Stand geholt wurde.
///
/// Bewusst ein [ValueNotifier] und kein Riverpod-Zustand: Die Meldung
/// entsteht **während** ein Provider lädt. Schriebe sie dabei in einen
/// Provider, stieße sie eine Invalidierung mitten in der Build-Phase an —
/// genau der Grund, warum dieses Projekt auf Riverpod 2 festgenagelt ist.
///
/// Der zuletzt beendete Lesezugriff gewinnt. Das ist eine bewusste
/// Vereinfachung: In der Praxis ist Netz da oder nicht, und ein Zähler über
/// gleichzeitig laufende Lesezugriffe machte die Anzeige nicht ehrlicher,
/// nur schwerer zu erklären.
class OfflineStatus {
  final notifier = _Holder();

  void markCached(DateTime at) => notifier.value = at;

  void markFresh() => notifier.value = null;
}

class _Holder {
  DateTime? _value;
  final _listeners = <void Function()>[];

  DateTime? get value => _value;

  set value(DateTime? next) {
    if (_value == next) return;
    _value = next;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

/// Gemeinsamer Ablauf: erst das Netz, bei Fehlschlag der Speicher.
class _CacheLayer {
  _CacheLayer(this.cache, this.status, this.groupId);

  final OfflineCache cache;
  final OfflineStatus status;

  /// Die angemeldete Gruppe. `null` heißt: kein Zwischenspeicher — ohne
  /// Gruppenkennung wüsste niemand, wessen Zeilen dort liegen.
  final String? Function() groupId;

  /// Zuletzt gesehene Gruppe — wechselt sie, fliegt alles Fremde raus.
  ///
  /// Bewusst hier und nicht beim Abmelden: Ein Abmelde-Haken liefe nicht,
  /// wenn jemand die App im angemeldeten Zustand schließt und die nächste
  /// Person sich anmeldet. Am Lesezugriff hängt es zwangsläufig.
  static String? _lastGroupId;

  Future<T> read<T>(
    String key,
    Future<T> Function() fromNetwork,
    Object? Function(T value) encode,
    T Function(Object? raw) decode,
  ) async {
    final id = groupId();
    if (id != null && id != _lastGroupId) {
      _lastGroupId = id;
      await cache.keepOnly(id);
    }
    try {
      final value = await fromNetwork();
      status.markFresh();
      if (id != null) {
        // Erst nach einem erfolgreichen Netz-Lesezugriff — ein Treffer aus
        // dem Speicher darf seinen eigenen Zeitstempel nie auffrischen.
        await cache.write(id, key, encode(value));
      }
      return value;
    } catch (error) {
      if (id == null) rethrow;
      final stored = await cache.read(id, key);
      if (stored == null) rethrow;
      status.markCached(stored.storedAt);
      return decode(stored.value);
    }
  }
}

class CachingGroupRepository implements GroupRepository {
  CachingGroupRepository(
    this._inner,
    OfflineCache cache,
    OfflineStatus status,
    String? Function() groupId,
  ) : _layer = _CacheLayer(cache, status, groupId);

  final GroupRepository _inner;
  final _CacheLayer _layer;

  @override
  Future<Group?> myGroup() => _layer.read(
    'group',
    _inner.myGroup,
    (group) => group?.toJson(),
    (raw) => raw == null
        ? null
        : Group.fromJson(Map<String, dynamic>.from(raw as Map)),
  );
}

class CachingCarpoolRepository implements CarpoolRepository {
  CachingCarpoolRepository(
    this._inner,
    OfflineCache cache,
    OfflineStatus status,
    String? Function() groupId,
  ) : _layer = _CacheLayer(cache, status, groupId);

  final CarpoolRepository _inner;
  final _CacheLayer _layer;

  static List<Map<String, dynamic>> _maps(Object? raw) => [
    for (final row in raw as List) Map<String, dynamic>.from(row as Map),
  ];

  @override
  Future<List<Person>> loadPersons() => _layer.read(
    'persons',
    _inner.loadPersons,
    (persons) => [for (final p in persons) p.toJson()],
    (raw) => [for (final row in _maps(raw)) Person.fromJson(row)],
  );

  @override
  Future<List<Trip>> loadTrips() => _layer.read(
    'trips',
    _inner.loadTrips,
    (trips) => [for (final t in trips) t.toJson()],
    (raw) => [for (final row in _maps(raw)) Trip.fromJson(row)],
  );

  @override
  Future<AppSettings> loadSettings() => _layer.read(
    'settings',
    _inner.loadSettings,
    (settings) => settings.toMap(),
    (raw) => AppSettings.fromMap({
      for (final e in (raw as Map).entries)
        e.key as String: (e.value as num).toDouble(),
    }),
  );

  @override
  Future<GroupDefaults> loadGroupDefaults() => _layer.read(
    'group_defaults',
    _inner.loadGroupDefaults,
    (defaults) => defaults.toJson(),
    (raw) => GroupDefaults.fromJson(
      raw == null ? null : Map<String, Object?>.from(raw as Map),
    ),
  );

  /// Der Schlüssel trägt die Woche: Ein Wochenwechsel darf nicht den Plan der
  /// Vorwoche als aktuellen ausgeben.
  @override
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7}) => _layer.read(
    'plan.${from.toIso8601String().substring(0, 10)}.$days',
    () => _inner.loadPlan(from, days: days),
    (plan) => plan.toJson(),
    (raw) => WeekPlan.fromJson(Map<String, dynamic>.from(raw as Map)),
  );

  @override
  Future<List<PlanNote>> loadNotes(DateTime from, {int days = 7}) =>
      _layer.read(
        'notes.${from.toIso8601String().substring(0, 10)}.$days',
        () => _inner.loadNotes(from, days: days),
        (notes) => [for (final n in notes) n.toJson()],
        (raw) => [for (final row in _maps(raw)) PlanNote.fromJson(row)],
      );

  /// Wie [loadPlan] mit der Woche im Schlüssel — die Abweichungen gehören zu
  /// genau dieser Spanne.
  @override
  Future<Map<DateTime, GroupDefaults>> loadPlanDefaults(
    DateTime from, {
    int days = 7,
  }) => _layer.read(
    'plandefaults.${from.toIso8601String().substring(0, 10)}.$days',
    () => _inner.loadPlanDefaults(from, days: days),
    (byDay) => {
      for (final e in byDay.entries)
        e.key.toIso8601String().substring(0, 10): e.value.toJson(),
    },
    (raw) => {
      for (final e in (raw as Map).entries)
        DateTime.parse(e.key as String): GroupDefaults.fromJson(
          Map<String, Object?>.from(e.value as Map),
        ),
    },
  );

  /// Wie [loadPlanDefaults], eine Ebene tiefer.
  @override
  Future<Map<DateTime, Map<String, GroupDefaults>>> loadCarDefaults(
    DateTime from, {
    int days = 7,
  }) => _layer.read(
    'cardefaults.${from.toIso8601String().substring(0, 10)}.$days',
    () => _inner.loadCarDefaults(from, days: days),
    (byDay) => {
      for (final day in byDay.entries)
        day.key.toIso8601String().substring(0, 10): {
          for (final car in day.value.entries) car.key: car.value.toJson(),
        },
    },
    (raw) => {
      for (final day in (raw as Map).entries)
        DateTime.parse(day.key as String): {
          for (final car in (day.value as Map).entries)
            car.key as String: GroupDefaults.fromJson(
              Map<String, Object?>.from(car.value as Map),
            ),
        },
    },
  );

  // Ab hier: alles Schreibende geht unverändert durch. Ohne Netz scheitert
  // es, und die Oberfläche sagt das — siehe Kopf dieser Datei.

  @override
  Future<void> savePlanDefaults(DateTime date, GroupDefaults defaults) =>
      _inner.savePlanDefaults(date, defaults);

  @override
  Future<void> saveCarDefaults(
    DateTime date,
    String driverId,
    GroupDefaults defaults,
  ) => _inner.saveCarDefaults(date, driverId, defaults);

  @override
  Future<Person> createPerson(Person person) => _inner.createPerson(person);

  @override
  Future<void> updatePerson(Person person) => _inner.updatePerson(person);

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) => _inner.createTrip(date, participations, note: note);

  @override
  Future<void> updateTrip(Trip trip) => _inner.updateTrip(trip);

  @override
  Future<void> deleteTrip(String tripId) => _inner.deleteTrip(tripId);

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _inner.saveSettings(settings);

  @override
  Future<void> saveGroupDefaults(GroupDefaults defaults) =>
      _inner.saveGroupDefaults(defaults);

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) => _inner.setAvailability(date, personId, ride);

  @override
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds) =>
      _inner.setPlanDrivers(date, driverIds);

  @override
  Future<void> addNote(DateTime date, String personId, String body) =>
      _inner.addNote(date, personId, body);

  @override
  Future<void> deleteNote(String noteId) => _inner.deleteNote(noteId);
}
