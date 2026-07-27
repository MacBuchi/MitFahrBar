/// supabase_repository.dart – CarpoolRepository gegen Supabase/PostgREST.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
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

  /// Der einzige Unique auf `persons` ist `persons_group_name_key`
  /// (Issue #109) — eine 23505 von dieser Tabelle kann also nur der Name
  /// sein. Übersetzt in einen fachlichen Typ, damit die Oberfläche keinen
  /// Postgres-Fehlercode auswerten muss.
  static Never _translate(PostgrestException error, Person person) {
    if (error.code == '23505') throw DuplicatePersonName(person.name);
    throw error;
  }

  @override
  Future<Person> createPerson(Person person) async {
    try {
      final row = await _client
          .from('persons')
          .insert({
            'name': person.name,
            'active': person.active,
            'vehicle': person.vehicle,
            'energy_type': person.energyType?.name,
            'consumption_per_100km': person.consumptionPer100km,
            'seats': person.seats,
          })
          .select()
          .single();
      return Person.fromJson(row);
    } on PostgrestException catch (error) {
      _translate(error, person);
    }
  }

  @override
  Future<void> updatePerson(Person person) async {
    try {
      await _client
          .from('persons')
          .update({
            'name': person.name,
            'active': person.active,
            'vehicle': person.vehicle,
            'energy_type': person.energyType?.name,
            'consumption_per_100km': person.consumptionPer100km,
            'seats': person.seats,
          })
          .eq('id', person.id);
    } on PostgrestException catch (error) {
      _translate(error, person);
    }
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

  @override
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7}) async {
    final start = _isoDay(from);
    final end = _isoDay(from.add(Duration(days: days - 1)));

    final availabilityRows = await _client
        .from('plan_availability')
        .select('plan_date, person_id, one_way')
        .gte('plan_date', start)
        .lte('plan_date', end);
    final overrideRows = await _client
        .from('plan_overrides')
        .select('plan_date, driver_id')
        .gte('plan_date', start)
        .lte('plan_date', end);

    final availability = <DateTime, Map<String, PlanRide>>{};
    for (final row in availabilityRows) {
      final date = DateTime.parse(row['plan_date'] as String);
      (availability[date] ??= <String, PlanRide>{})[row['person_id']
          as String] = (row['one_way'] as bool? ?? false)
          ? PlanRide.oneWay
          : PlanRide.full;
    }

    final overrides = <DateTime, Set<String>>{};
    for (final row in overrideRows) {
      final date = DateTime.parse(row['plan_date'] as String);
      (overrides[date] ??= <String>{}).add(row['driver_id'] as String);
    }
    return WeekPlan(availability: availability, overrides: overrides);
  }

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) async {
    if (ride != null) {
      // `group_id` steht im Schlüssel (sonst wäre er über alle Gruppen
      // eindeutig) und muss deshalb auch das Konfliktziel benennen. Den Wert
      // liefert der Spalten-Default `auth.uid()`; er gehört nicht in die
      // Nutzlast, sonst könnte der Client ihn setzen.
      await _client.from('plan_availability').upsert({
        'plan_date': _isoDay(date),
        'person_id': personId,
        'one_way': ride == PlanRide.oneWay,
      }, onConflict: 'group_id,plan_date,person_id');
    } else {
      await _client
          .from('plan_availability')
          .delete()
          .eq('plan_date', _isoDay(date))
          .eq('person_id', personId);
    }
  }

  @override
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds) async {
    // Erst den Tag räumen, dann die Menge schreiben — PostgREST kennt keine
    // Transaktion. Scheitert der zweite Schritt, bleibt „kein Übersteuern"
    // zurück: Der Planer zeigt dann sichtbar wieder den Vorschlag, und der
    // Notifier holt per invalidateSelf die Server-Wahrheit.
    await _client
        .from('plan_overrides')
        .delete()
        .eq('plan_date', _isoDay(date));
    if (driverIds.isEmpty) return;
    // Upsert auf dem vollen Schlüssel statt Insert: macht Doppel-Taps
    // idempotent und hält das Konfliktziel deckungsgleich mit dem PK
    // (test/schema_test.dart prüft genau diese Kopplung).
    await _client.from('plan_overrides').upsert([
      for (final id in driverIds) {'plan_date': _isoDay(date), 'driver_id': id},
    ], onConflict: 'group_id,plan_date,driver_id');
  }

  @override
  Future<List<PlanNote>> loadNotes(DateTime from, {int days = 7}) async {
    // `order` ist Pflicht, nicht Geschmack: PostgREST sichert ohne ihn keine
    // Reihenfolge zu. Die Anzeige braucht sie ohnehin — und der Versand-Job
    // mischt die Anmerkungen in den Tages-Digest, wo eine wechselnde
    // Reihenfolge endlos „Änderung"-Meldungen auslöste (der Digest sortiert
    // deshalb zusätzlich selbst, siehe core/push_digest.dart).
    final rows = await _client
        .from('plan_notes')
        .select('id, plan_date, person_id, body, created_at')
        .gte('plan_date', _isoDay(from))
        .lte('plan_date', _isoDay(from.add(Duration(days: days - 1))))
        .order('created_at');
    return rows.map(PlanNote.fromJson).toList();
  }

  @override
  Future<void> addNote(DateTime date, String personId, String body) async {
    // Insert, kein Upsert: Eine Anmerkung hat keinen fachlichen Schlüssel,
    // mehrere je Tag und Person sind der Normalfall.
    await _client.from('plan_notes').insert({
      'plan_date': _isoDay(date),
      'person_id': personId,
      'body': body.trim(),
    });
  }

  @override
  Future<void> deleteNote(String noteId) async {
    await _client.from('plan_notes').delete().eq('id', noteId);
  }

  /// `date`-Spalten wollen reines yyyy-MM-dd; ein voller Zeitstempel würde
  /// je nach Zeitzone auf dem Nachbartag landen.
  static String _isoDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
