/// carpool_repository.dart – Schnittstelle des Data-Layers.
library;

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';

abstract class CarpoolRepository {
  Future<List<Person>> loadPersons();
  Future<Person> createPerson(Person person);
  Future<void> updatePerson(Person person);

  /// Fahrten absteigend nach Datum.
  Future<List<Trip>> loadTrips();

  /// Legt eine Fahrt an. Wirft [DuplicateTripException], wenn für das
  /// Datum bereits eine Fahrt existiert.
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  });
  Future<void> updateTrip(Trip trip);
  Future<void> deleteTrip(String tripId);

  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
}

class DuplicateTripException implements Exception {
  DuplicateTripException(this.date, this.existingTripId);

  final DateTime date;
  final String existingTripId;
}
