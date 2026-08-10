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
///
/// **Seit v0.79.0 zuerst der Speicher, dann das Netz** (#232, gemeldet als
/// „Offline Start dauert super lang. Dabei muss ja nichts geladen werden").
/// Bis dahin fragte jeder Lesezugriff erst das Netz und ging erst im `catch`
/// an den Speicher — die Anzeige war damit per Konstruktion so langsam wie
/// das **Aufgeben** der Anfrage. Im Flugmodus scheitert die sofort, im echten
/// Funkloch (Balken da, kein Durchsatz) läuft sie in den Plattform-Timeout,
/// und das sind die zehn bis sechzig Sekunden aus der Meldung.
///
/// Drei Riegel gehören zu dieser Umkehr und dürfen nicht einzeln „aufgeräumt"
/// werden:
///
/// * **Nur beim ERSTEN Lesezugriff je Schlüssel und Lauf.** Genau das ist der
///   gemeldete Fall (der Start). Jeder spätere Lesezugriff fragt weiter das
///   Netz zuerst — sonst lieferte `refreshPlanning` nach einem Push-Tipp
///   („erst frische Daten, dann hinschauen", #200) und „Erneut versuchen"
///   auf dem Gate-Schirm genau den Stand zurück, den zu ersetzen ihr Zweck
///   ist.
/// * **Nach einem erfolgreichen Schreibzugriff gar nicht mehr.** Sonst zeigte
///   der nächste zum ersten Mal geöffnete Schirm kurz einen Stand, der die
///   eben gespeicherte Fahrt noch nicht kennt — die Nutzerin sähe ihre eigene
///   Eingabe zurückspringen.
/// * **Was im Hintergrund eintrifft, meldet sich** ([RefreshSignal]). Ohne
///   das bliebe der zuerst gezeigte Stand die ganze Sitzung stehen; online
///   wäre das ein veralteter Plan, und niemand wüsste es.
library;

import 'dart:async';

import '../core/log.dart';
import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/group_defaults.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
import '../models/seat_choice.dart';
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

/// Meldet, dass im Hintergrund frische Zeilen eingetroffen sind (#232).
///
/// Der Zwischenspeicher zeigt seit v0.79.0 zuerst und fragt danach; ohne
/// dieses Signal bliebe der zuerst gezeigte Stand die ganze Sitzung stehen.
///
/// **Ein Schwall wird gesammelt.** Personen, Fahrten, Parameter, Vorgaben,
/// Plan, Anmerkungen und die beiden Abweichungs-Ebenen landen im selben
/// Augenblick — acht Meldungen wären acht Neubauten für ein Ergebnis. Die
/// kurze Frist ist kein Feinschliff: Sie ist der Unterschied zwischen einer
/// Aktualisierung und einem Flackern.
class RefreshSignal {
  RefreshSignal({this.window = const Duration(milliseconds: 250)});

  /// Wie lange ein Schwall gesammelt wird, bevor die Zuhörer erfahren.
  final Duration window;

  final _listeners = <void Function()>[];
  Timer? _pending;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void ping() {
    _pending ??= Timer(window, () {
      _pending = null;
      for (final listener in List.of(_listeners)) {
        listener();
      }
    });
  }

  /// Für Tests und den Demo-Modus: einen offenen Sammler fallen lassen.
  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}

/// Gemeinsamer Ablauf: beim ersten Mal der Speicher, sonst erst das Netz.
class _CacheLayer {
  _CacheLayer(this.cache, this.status, this.signal, this.groupId);

  final OfflineCache cache;
  final OfflineStatus status;
  final RefreshSignal signal;

  /// Die angemeldete Gruppe. `null` heißt: kein Zwischenspeicher — ohne
  /// Gruppenkennung wüsste niemand, wessen Zeilen dort liegen.
  final String? Function() groupId;

  /// Zuletzt gesehene Gruppe — wechselt sie, fliegt alles Fremde raus.
  ///
  /// Bewusst hier und nicht beim Abmelden: Ein Abmelde-Haken liefe nicht,
  /// wenn jemand die App im angemeldeten Zustand schließt und die nächste
  /// Person sich anmeldet. Am Lesezugriff hängt es zwangsläufig.
  static String? _lastGroupId;

  /// Schlüssel, die in diesem Lauf schon einmal gelesen wurden. Nur der
  /// **erste** Zugriff darf aus dem Speicher heraus antworten (siehe Kopf).
  final _seen = <String>{};

  /// Schlüssel, deren Auffrischung gerade läuft — sonst startete jede
  /// Invalidierung eine zweite Anfrage auf dieselbe Zeile.
  final _running = <String>{};

  /// Schlüssel, deren frisch geholter Stand im Speicher liegt und noch von
  /// niemandem abgeholt wurde. Genau ein Lesezugriff darf ihn nehmen —
  /// das ist der, den [RefreshSignal] gerade ausgelöst hat. Ohne diese
  /// Abholung fragte er ein zweites Mal dieselbe Zeile beim Server ab.
  final _fresh = <String>{};

  /// Erfolgreiche Schreibzugriffe dieses Laufs. Ab dem ersten ist der
  /// abgelegte Stand möglicherweise überholt — ab da wird nur noch gezeigt,
  /// was wirklich vom Server kommt.
  int _writes = 0;

  /// Reicht einen Schreibzugriff durch und zählt ihn, wenn er geklappt hat.
  ///
  /// Ohne Netz scheitert er, und dann hat sich nichts geändert: Der
  /// gespeicherte Stand bleibt der beste, den es gibt.
  Future<T> wrote<T>(Future<T> pending) async {
    final value = await pending;
    _writes++;
    return value;
  }

  Future<T> read<T>(
    String key,
    Future<T> Function() fromNetwork,
    Object? Function(T value) encode,
    T Function(Object? raw) decode,
  ) async {
    final id = groupId();
    if (id != null && id != _lastGroupId) {
      _lastGroupId = id;
      _seen.clear();
      _fresh.clear();
      await cache.keepOnly(id);
    }

    if (id != null) {
      final pickup = _fresh.remove(key);
      final first = _seen.add(key);
      // Läuft die Auffrischung dieses Schlüssels noch, wird weiter der
      // Speicher gezeigt — auch wenn das hier nicht der erste Zugriff ist.
      // Ohne diese Zeile riss die Meldung eines **anderen** Schlüssels
      // (`RefreshSignal` invalidiert alle) jeden noch wartenden Schirm in
      // den Ladekreis zurück: erst Inhalt, dann Spinner, dann wieder Inhalt.
      final waiting = _running.contains(key);
      if (pickup || ((first || waiting) && _writes == 0)) {
        final stored = await cache.read(id, key);
        if (stored != null) {
          try {
            final value = decode(stored.value);
            if (pickup) {
              // Das ist die Antwort, die eben im Hintergrund eingetroffen
              // ist — sie kommt vom Server, nur eben schon vorhin.
              status.markFresh();
            } else {
              _refreshLater(id, key, fromNetwork, encode);
              status.markCached(stored.storedAt);
            }
            return value;
          } catch (error) {
            // Ein Eintrag, den diese Fassung nicht mehr lesen kann, ist wie
            // keiner. Ohne Fehlertext ins Log: Der Inhalt sind Fahrten und
            // Namen. Weiter geht es über das Netz — nicht mit einem Fehler,
            // den es ohne Zwischenspeicher gar nicht gäbe.
            log.w('cache decode failed: $key');
          }
        }
      }
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

  /// Holt im Hintergrund nach, was gerade aus dem Speicher gezeigt wurde.
  void _refreshLater<T>(
    String id,
    String key,
    Future<T> Function() fromNetwork,
    Object? Function(T value) encode,
  ) {
    if (!_running.add(key)) return;
    final writesAtStart = _writes;
    unawaited(() async {
      try {
        final value = await fromNetwork();
        // Ein Schreibzugriff hat den geholten Stand überholt: Ab hier ist er
        // die ältere Wahrheit und darf weder den Speicher überschreiben noch
        // eine Anzeige auslösen.
        if (writesAtStart != _writes) return;
        await cache.write(id, key, encode(value));
        _fresh.add(key);
        status.markFresh();
        signal.ping();
      } catch (error) {
        // Kein Netz. Die Leiste steht bereits auf dem gespeicherten
        // Zeitpunkt — mehr ist dazu nicht zu sagen.
      } finally {
        _running.remove(key);
      }
    }());
  }
}

class CachingGroupRepository implements GroupRepository {
  /// Ohne [refresh] meldet der Dekorierer an einen Signalgeber, den niemand
  /// hört — für Tests und den Demo-Modus richtig, in der App wird der
  /// gemeinsame gereicht (`refreshSignalProvider`).
  CachingGroupRepository(
    this._inner,
    OfflineCache cache,
    OfflineStatus status,
    String? Function() groupId, {
    RefreshSignal? refresh,
  }) : _layer = _CacheLayer(cache, status, refresh ?? RefreshSignal(), groupId);

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
  /// Zu [refresh] siehe [CachingGroupRepository].
  CachingCarpoolRepository(
    this._inner,
    OfflineCache cache,
    OfflineStatus status,
    String? Function() groupId, {
    RefreshSignal? refresh,
  }) : _layer = _CacheLayer(cache, status, refresh ?? RefreshSignal(), groupId);

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

  /// Wie [loadCarDefaults] — dieselbe Woche, dieselbe Ablageform.
  @override
  Future<Map<DateTime, List<SeatChoice>>> loadSeatChoices(
    DateTime from, {
    int days = 7,
  }) => _layer.read(
    'seatchoices.${from.toIso8601String().substring(0, 10)}.$days',
    () => _inner.loadSeatChoices(from, days: days),
    (byDay) => {
      for (final day in byDay.entries)
        day.key.toIso8601String().substring(0, 10): [
          for (final choice in day.value) choice.toJson(),
        ],
    },
    (raw) => {
      for (final day in (raw as Map).entries)
        DateTime.parse(day.key as String): [
          for (final choice in day.value as List)
            SeatChoice.fromJson(Map<String, Object?>.from(choice as Map)),
        ],
    },
  );

  // Ab hier: alles Schreibende geht unverändert durch. Ohne Netz scheitert
  // es, und die Oberfläche sagt das — siehe Kopf dieser Datei.
  //
  // Durch `wrote` läuft es trotzdem, und zwar ausnahmslos: Ab dem ersten
  // erfolgreichen Schreibzugriff darf kein Schirm mehr aus dem Speicher
  // heraus öffnen, sonst sieht die Nutzerin ihre eigene Eingabe
  // zurückspringen. Wer hier eine Methode ohne `wrote` ergänzt, baut genau
  // diesen Fall — und zwar nur für den Schirm, den man in dieser Sitzung
  // noch nicht offen hatte.

  @override
  Future<void> saveSeatChoice(SeatChoice choice) =>
      _layer.wrote(_inner.saveSeatChoice(choice));

  @override
  Future<void> deleteSeatChoice(
    DateTime date,
    String personId,
    String driverId,
  ) => _layer.wrote(_inner.deleteSeatChoice(date, personId, driverId));

  @override
  Future<void> savePlanDefaults(DateTime date, GroupDefaults defaults) =>
      _layer.wrote(_inner.savePlanDefaults(date, defaults));

  @override
  Future<void> saveCarDefaults(
    DateTime date,
    String driverId,
    GroupDefaults defaults,
  ) => _layer.wrote(_inner.saveCarDefaults(date, driverId, defaults));

  @override
  Future<Person> createPerson(Person person) =>
      _layer.wrote(_inner.createPerson(person));

  @override
  Future<void> updatePerson(Person person) =>
      _layer.wrote(_inner.updatePerson(person));

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) => _layer.wrote(_inner.createTrip(date, participations, note: note));

  @override
  Future<void> updateTrip(Trip trip) => _layer.wrote(_inner.updateTrip(trip));

  @override
  Future<void> deleteTrip(String tripId) =>
      _layer.wrote(_inner.deleteTrip(tripId));

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _layer.wrote(_inner.saveSettings(settings));

  @override
  Future<void> saveGroupDefaults(GroupDefaults defaults) =>
      _layer.wrote(_inner.saveGroupDefaults(defaults));

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) => _layer.wrote(_inner.setAvailability(date, personId, ride));

  @override
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds) =>
      _layer.wrote(_inner.setPlanDrivers(date, driverIds));

  @override
  Future<void> addNote(DateTime date, String personId, String body) =>
      _layer.wrote(_inner.addNote(date, personId, body));

  @override
  Future<void> deleteNote(String noteId) =>
      _layer.wrote(_inner.deleteNote(noteId));
}
