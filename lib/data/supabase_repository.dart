/// supabase_repository.dart – CarpoolRepository gegen Supabase/PostgREST.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'carpool_repository.dart';

class SupabaseCarpoolRepository implements CarpoolRepository {
  SupabaseCarpoolRepository(this._client);

  final SupabaseClient _client;

  static String _statusToDb(ParticipationStatus status) => switch (status) {
    ParticipationStatus.driver => 'driver',
    ParticipationStatus.passenger => 'passenger',
    ParticipationStatus.oneWay => 'one_way',
  };

  static ParticipationStatus _statusFromDb(String value) => switch (value) {
    'driver' => ParticipationStatus.driver,
    'passenger' => ParticipationStatus.passenger,
    'one_way' => ParticipationStatus.oneWay,
    _ => throw ArgumentError('Unbekannter Status: $value'),
  };

  static String _dateOnly(DateTime date) =>
      date.toIso8601String().substring(0, 10);

  @override
  Future<List<Person>> loadPersons() async {
    final rows = await _client.from('persons').select().order('name');
    return rows.map(Person.fromJson).toList();
  }

  @override
  Future<Person> createPerson(Person person) async {
    final row = await _client
        .from('persons')
        .insert({
          'name': person.name,
          'active': person.active,
          'vehicle': person.vehicle,
          'energy_type': person.energyType?.name,
          'consumption_per_100km': person.consumptionPer100km,
        })
        .select()
        .single();
    return Person.fromJson(row);
  }

  @override
  Future<void> updatePerson(Person person) async {
    await _client
        .from('persons')
        .update({
          'name': person.name,
          'active': person.active,
          'vehicle': person.vehicle,
          'energy_type': person.energyType?.name,
          'consumption_per_100km': person.consumptionPer100km,
        })
        .eq('id', person.id);
  }

  @override
  Future<List<Trip>> loadTrips() async {
    final rows = await _client
        .from('trips')
        .select('id, trip_date, note, trip_participations(person_id, status)')
        .order('trip_date', ascending: false);
    return [
      for (final row in rows)
        Trip(
          id: row['id'] as String,
          date: DateTime.parse(row['trip_date'] as String),
          note: row['note'] as String?,
          participations: {
            for (final p in (row['trip_participations'] as List))
              (p as Map<String, dynamic>)['person_id'] as String: _statusFromDb(
                p['status'] as String,
              ),
          },
        ),
    ];
  }

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) async {
    final row = await _client
        .from('trips')
        .insert({'trip_date': _dateOnly(date), 'note': note})
        .select('id')
        .single();
    final tripId = row['id'] as String;
    await _insertParticipations(tripId, participations);
    return Trip(
      id: tripId,
      date: date,
      participations: Map.of(participations),
      note: note,
    );
  }

  @override
  Future<void> updateTrip(Trip trip) async {
    await _client
        .from('trips')
        .update({'trip_date': _dateOnly(trip.date), 'note': trip.note})
        .eq('id', trip.id);
    await _client.from('trip_participations').delete().eq('trip_id', trip.id);
    await _insertParticipations(trip.id, trip.participations);
  }

  Future<void> _insertParticipations(
    String tripId,
    Map<String, ParticipationStatus> participations,
  ) async {
    if (participations.isEmpty) return;
    await _client.from('trip_participations').insert([
      for (final e in participations.entries)
        {'trip_id': tripId, 'person_id': e.key, 'status': _statusToDb(e.value)},
    ]);
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    await _client.from('trips').delete().eq('id', tripId);
  }

  @override
  Future<AppSettings> loadSettings() async {
    final rows = await _client.from('settings').select('key, value');
    return AppSettings.fromMap({
      for (final row in rows)
        row['key'] as String: (row['value'] as num).toDouble(),
    });
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final groupId = _client.auth.currentUser?.id;
    await _client.from('settings').upsert([
      for (final e in settings.toMap().entries)
        {'group_id': groupId, 'key': e.key, 'value': e.value},
    ], onConflict: 'group_id,key');
  }
}
