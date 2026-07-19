/// fake_repository.dart – In-Memory-Implementierung für Tests und
/// lokalen Start ohne Supabase-Konfiguration.
library;

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'carpool_repository.dart';

class FakeCarpoolRepository implements CarpoolRepository {
  FakeCarpoolRepository({
    List<Person>? persons,
    List<Trip>? trips,
    AppSettings? settings,
  })  : _persons = [...?persons],
        _trips = [...?trips],
        _settings = settings ?? const AppSettings();

  final List<Person> _persons;
  final List<Trip> _trips;
  AppSettings _settings;
  int _nextId = 1000;

  String _newId(String prefix) => '$prefix-${_nextId++}';

  @override
  Future<List<Person>> loadPersons() async => List.unmodifiable(_persons);

  @override
  Future<Person> createPerson(Person person) async {
    final created = Person(
      id: person.id.isEmpty ? _newId('person') : person.id,
      name: person.name,
      active: person.active,
      vehicle: person.vehicle,
      energyType: person.energyType,
      consumptionPer100km: person.consumptionPer100km,
    );
    _persons.add(created);
    return created;
  }

  @override
  Future<void> updatePerson(Person person) async {
    final index = _persons.indexWhere((p) => p.id == person.id);
    if (index >= 0) _persons[index] = person;
  }

  @override
  Future<List<Trip>> loadTrips() async {
    final sorted = [..._trips]..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(sorted);
  }

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) async {
    final created = Trip(
      id: _newId('trip'),
      date: DateTime(date.year, date.month, date.day),
      participations: Map.of(participations),
      note: note,
    );
    _trips.add(created);
    return created;
  }

  @override
  Future<void> updateTrip(Trip trip) async {
    final index = _trips.indexWhere((t) => t.id == trip.id);
    if (index >= 0) _trips[index] = trip;
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    _trips.removeWhere((t) => t.id == tripId);
  }

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

/// Demo-Daten für den Start ohne Backend (keine echten Namen).
FakeCarpoolRepository demoRepository() {
  const persons = [
    Person(
      id: 'p1',
      name: 'Anna',
      active: true,
      vehicle: 'Tesla',
      energyType: EnergyType.electric,
      consumptionPer100km: 16,
    ),
    Person(
      id: 'p2',
      name: 'Ben',
      active: true,
      vehicle: 'Dacia',
      energyType: EnergyType.diesel,
      consumptionPer100km: 6,
    ),
    Person(
      id: 'p3',
      name: 'Clara',
      active: true,
      vehicle: 'Astra',
      energyType: EnergyType.petrol,
      consumptionPer100km: 7,
    ),
    Person(
      id: 'p4',
      name: 'David',
      active: true,
      vehicle: 'BMW',
      energyType: EnergyType.diesel,
      consumptionPer100km: 5,
    ),
  ];
  final repo = FakeCarpoolRepository(persons: persons);
  final base = DateTime.now().subtract(const Duration(days: 14));
  final pattern = [
    {'p1': ParticipationStatus.driver, 'p2': ParticipationStatus.passenger, 'p3': ParticipationStatus.passenger},
    {'p2': ParticipationStatus.driver, 'p1': ParticipationStatus.passenger, 'p4': ParticipationStatus.oneWay},
    {'p3': ParticipationStatus.driver, 'p1': ParticipationStatus.passenger, 'p2': ParticipationStatus.passenger, 'p4': ParticipationStatus.passenger},
    {'p1': ParticipationStatus.driver, 'p4': ParticipationStatus.passenger},
  ];
  for (var i = 0; i < 10; i++) {
    final day = base.add(Duration(days: i));
    if (day.weekday >= DateTime.saturday) continue;
    repo._trips.add(Trip(
      id: 'demo-$i',
      date: DateTime(day.year, day.month, day.day),
      participations: pattern[i % pattern.length],
    ));
  }
  return repo;
}
