/// carpool_repository.dart – Schnittstelle des Data-Layers.
library;

import '../models/app_settings.dart';
import '../models/group_defaults.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
import '../models/seat_choice.dart';
import '../models/trip.dart';

/// Der Name gehört in dieser Gruppe schon jemandem (Issue #109).
///
/// Ein eigener Typ statt eines Postgres-Fehlercodes in der Oberfläche: Die
/// Regel ist fachlich („ein Name = eine Person"), und der Screen soll sie
/// melden können, ohne PostgREST zu kennen. Das Fake-Backend wirft dieselbe
/// Ausnahme — dadurch prüft der Flow-Test wirklich diesen Pfad und nicht
/// einen nachgebauten.
class DuplicatePersonName implements Exception {
  const DuplicatePersonName(this.name);

  final String name;

  @override
  String toString() => 'DuplicatePersonName($name)';
}

abstract class CarpoolRepository {
  Future<List<Person>> loadPersons();

  /// Wirft [DuplicatePersonName], wenn der Name in dieser Gruppe schon
  /// vergeben ist — verglichen ohne Groß-/Kleinschreibung und ohne
  /// Rand-Leerzeichen, wie der Unique-Index in der Datenbank.
  Future<Person> createPerson(Person person);

  /// Wirft [DuplicatePersonName] wie [createPerson] — Umbenennen kann
  /// genauso kollidieren wie Anlegen.
  Future<void> updatePerson(Person person);

  /// Fahrten absteigend nach Datum.
  Future<List<Trip>> loadTrips();

  /// Legt eine Fahrt an. Pro Tag sind mehrere Fahrten erlaubt (z. B. zwei
  /// getrennte Autos); die UI fragt bei einem bereits belegten Tag nach.
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  });
  Future<void> updateTrip(Trip trip);
  Future<void> deleteTrip(String tripId);

  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);

  /// Abfahrtszeiten und Treffpunkt der Gruppe (#139). Keine Zeile heißt
  /// „nicht gepflegt" und ergibt `const GroupDefaults()`.
  ///
  /// Steht neben [loadSettings], weil beides dieselbe Sorte ist: Werte, die
  /// die Gruppe im Parameter-Screen pflegt und die die Punkte nie berühren.
  /// Eine eigene Tabelle brauchen sie trotzdem — `settings` trägt nur Zahlen.
  Future<GroupDefaults> loadGroupDefaults();

  /// Schreibt die Vorgaben **vollständig**: Ein leeres Feld löscht den alten
  /// Wert, statt ihn stehen zu lassen. Anders wäre eine einmal gesetzte
  /// Uhrzeit nie wieder loszuwerden.
  Future<void> saveGroupDefaults(GroupDefaults defaults);

  /// Wochenplan ab [from] für [days] Tage: wer kann wann, und wo wurde der
  /// Fahrer-Vorschlag von Hand übersteuert. Der Vorschlag selbst wird nicht
  /// gespeichert — er entsteht in `planWeek`.
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7});

  /// Setzt oder entfernt die Verfügbarkeit einer Person an einem Tag.
  /// [ride] `null` heißt „kann nicht" und löscht den Eintrag.
  Future<void> setAvailability(DateTime date, String personId, PlanRide? ride);

  /// Übersteuert den Fahrer-Vorschlag mit einer MENGE von Fahrern (Issue
  /// #62: ein Tag kann mehrere Autos haben). Eine leere Menge nimmt das
  /// Übersteuern zurück und lässt wieder den Vorschlag gelten.
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds);

  /// Abweichende Zeiten und Treffpunkt einzelner Tage (#183), ab [from] für
  /// [days] Tage — Schlüssel auf Tagesbeginn normiert.
  ///
  /// Was ein Tag nicht setzt, kommt weiter aus [loadGroupDefaults]; aufgelöst
  /// wird feldweise in `effectiveDefaults`. Ein Tag ohne Zeile fehlt in der
  /// Map, statt als leerer Eintrag darin zu stehen — „keine Abweichung" und
  /// „Abweichung ohne Inhalt" sind dasselbe, und zwei Schreibweisen dafür
  /// wären zwei Fälle im Digest.
  Future<Map<DateTime, GroupDefaults>> loadPlanDefaults(
    DateTime from, {
    int days = 7,
  });

  /// Schreibt die Abweichung EINES Tages, vollständig wie
  /// [saveGroupDefaults]: Ein leeres Feld löscht den alten Wert. Ist gar
  /// nichts mehr gesetzt, verschwindet die Zeile — sonst bliebe ein leerer
  /// Eintrag stehen, der im Digest anders zählt als keiner.
  Future<void> savePlanDefaults(DateTime date, GroupDefaults defaults);

  /// Abweichungen einzelner **Autos** (#183, Stufe B): Tag → Fahrer →
  /// Abweichung. Die dritte Ebene über [loadPlanDefaults] und
  /// [loadGroupDefaults]; aufgelöst wird `Auto → Tag → Gruppe`, feldweise.
  ///
  /// Geschlüsselt am Fahrer, weil ein Auto in der Datenbank nur als „diese
  /// Person fährt an diesem Tag" existiert — die Autos selbst rechnet
  /// `planWeek` und speichert sie nie.
  Future<Map<DateTime, Map<String, GroupDefaults>>> loadCarDefaults(
    DateTime from, {
    int days = 7,
  });

  /// Schreibt die Abweichung EINES Autos, vollständig wie
  /// [savePlanDefaults]: leer heißt, die Zeile verschwindet.
  ///
  /// **Der Aufrufer schreibt den Fahrer zusätzlich fest** (siehe
  /// [setPlanDrivers]). Ohne das hinge die Zeit morgen an einer Person, die
  /// an dem Tag gar nicht mehr fährt — der Vorschlag kippt, sobald jemand
  /// seine Verfügbarkeit ändert.
  Future<void> saveCarDefaults(
    DateTime date,
    String driverId,
    GroupDefaults defaults,
  );

  /// Sitz-Entscheidungen (#189, Stufe B2): Tag → Zusagen und Absagen der
  /// Mitfahrer zu einzelnen Autos. `planWeek` beachtet sie beim Verteilen —
  /// gültig ist nur, was zu den aktuellen Bedingungen des Autos passt
  /// (`SeatChoice.terms`).
  Future<Map<DateTime, List<SeatChoice>>> loadSeatChoices(
    DateTime from, {
    int days = 7,
  });

  /// Schreibt eine Entscheidung — Upsert auf
  /// `(plan_date, person_id, driver_id)`: Wer umentscheidet, ersetzt seine
  /// Zeile. `decided_at` kommt vom Aufrufer und bleibt beim Umschreiben
  /// derselben Entscheidung erhalten (es entscheidet bei Überfüllung, wer
  /// zuerst gepinnt hat).
  Future<void> saveSeatChoice(SeatChoice choice);

  /// Nimmt eine Entscheidung zurück — die Person ist wieder ungefragt und
  /// wird automatisch verteilt.
  Future<void> deleteSeatChoice(
    DateTime date,
    String personId,
    String driverId,
  );

  /// Anmerkungen ab [from] für [days] Tage, älteste zuerst (Issue #127).
  ///
  /// Dieselbe Spanne wie [loadPlan] und aus demselben Grund: Der Planer
  /// zeigt eine Woche und holt sie in EINER Anfrage. Der Tagesschirm ruft
  /// mit `days: 1`.
  Future<List<PlanNote>> loadNotes(DateTime from, {int days = 7});

  /// Legt eine Anmerkung an. [personId] ist der Verfasser — kein
  /// Identitätsnachweis, jeder darf für jeden schreiben.
  Future<void> addNote(DateTime date, String personId, String body);

  /// Löscht eine Anmerkung. Gruppenweit möglich: Ein Löschknopf nur beim
  /// eigenen Autor wäre Vertipper-Schutz, keine Zugriffskontrolle.
  Future<void> deleteNote(String noteId);
}

/// Rohdaten des Wochenplans, wie sie in der Datenbank stehen.
class WeekPlan {
  const WeekPlan({required this.availability, required this.overrides});

  const WeekPlan.empty() : availability = const {}, overrides = const {};

  /// Tag → Person → wie sie mitfährt. Wer fehlt, kann an dem Tag nicht.
  final Map<DateTime, Map<String, PlanRide>> availability;

  /// Tag → von Hand gesetzte Fahrer (eine Zeile je Fahrer in
  /// `plan_overrides`).
  final Map<DateTime, Set<String>> overrides;

  /// Für den Zwischenspeicher (#169). Die Tage werden als ISO-Kalendertag
  /// abgelegt, nicht als Zeitstempel: Der Plan kennt keine Uhrzeit, und ein
  /// mitgeschriebener Zeitzonen-Anteil käme beim Lesen als anderer Tag
  /// zurück, sobald das Gerät die Zone wechselt.
  Map<String, dynamic> toJson() => {
    'availability': {
      for (final day in availability.entries)
        _dayKey(day.key): {
          for (final person in day.value.entries) person.key: person.value.name,
        },
    },
    'overrides': {
      for (final day in overrides.entries) _dayKey(day.key): day.value.toList(),
    },
  };

  factory WeekPlan.fromJson(Map<String, dynamic> json) => WeekPlan(
    availability: {
      for (final day in (json['availability'] as Map).entries)
        DateTime.parse(day.key as String): {
          for (final person in (day.value as Map).entries)
            person.key as String: PlanRide.values.firstWhere(
              (r) => r.name == person.value,
              // Ein unbekannter Wert gilt als „kann ganz" — dieselbe Linie
              // wie `Group.statusFrom`: tolerant lesen statt werfen, denn
              // ein Wurf hier machte den Zwischenspeicher unbrauchbar.
              orElse: () => PlanRide.full,
            ),
        },
    },
    overrides: {
      for (final day in (json['overrides'] as Map).entries)
        DateTime.parse(day.key as String): {
          for (final id in day.value as List) id as String,
        },
    },
  );

  static String _dayKey(DateTime day) => day.toIso8601String().substring(0, 10);
}
