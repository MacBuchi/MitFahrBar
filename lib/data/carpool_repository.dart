/// carpool_repository.dart – Schnittstelle des Data-Layers.
library;

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/plan_ride.dart';
import '../models/trip.dart';

abstract class CarpoolRepository {
  Future<List<Person>> loadPersons();
  Future<Person> createPerson(Person person);
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

  /// Wochenplan ab [from] für [days] Tage: wer kann wann, und wo wurde der
  /// Fahrer-Vorschlag von Hand übersteuert. Der Vorschlag selbst wird nicht
  /// gespeichert — er entsteht in `planWeek`.
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7});

  /// Setzt oder entfernt die Verfügbarkeit einer Person an einem Tag.
  /// [ride] `null` heißt „kann nicht" und löscht den Eintrag.
  Future<void> setAvailability(DateTime date, String personId, PlanRide? ride);

  /// Übersteuert den Fahrer-Vorschlag; [driverId] `null` nimmt das
  /// Übersteuern zurück und lässt wieder den Vorschlag gelten.
  Future<void> setPlanDriver(DateTime date, String? driverId);
}

/// Rohdaten des Wochenplans, wie sie in der Datenbank stehen.
class WeekPlan {
  const WeekPlan({required this.availability, required this.overrides});

  const WeekPlan.empty() : availability = const {}, overrides = const {};

  /// Tag → Person → wie sie mitfährt. Wer fehlt, kann an dem Tag nicht.
  final Map<DateTime, Map<String, PlanRide>> availability;

  /// Tag → von Hand gesetzter Fahrer.
  final Map<DateTime, String> overrides;
}
