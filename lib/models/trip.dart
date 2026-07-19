/// trip.dart – Ein Fahrtag mit den Teilnahme-Status aller Beteiligten.
library;

enum ParticipationStatus {
  /// Hat das Auto gestellt und ist gefahren.
  driver,

  /// Hin- und Rückweg mitgefahren (zählt 1,0).
  passenger,

  /// Nur eine Richtung mitgefahren (zählt mit OneWay-Faktor 0,5).
  oneWay,
}

class Trip {
  const Trip({
    required this.id,
    required this.date,
    required this.participations,
    this.note,
  });

  final String id;

  /// Kalendertag der Fahrt (Zeitanteil ist immer 00:00 lokal).
  final DateTime date;

  /// personId -> Status. Personen ohne Eintrag waren nicht dabei.
  final Map<String, ParticipationStatus> participations;
  final String? note;

  String? get driverId => participations.entries
      .where((e) => e.value == ParticipationStatus.driver)
      .map((e) => e.key)
      .firstOrNull;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        date: DateTime.parse(json['trip_date'] as String),
        note: json['note'] as String?,
        participations: {
          for (final p in (json['participations'] as List))
            (p as Map<String, dynamic>)['person_id'] as String:
                ParticipationStatus.values.byName(p['status'] as String),
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_date': date.toIso8601String().substring(0, 10),
        'note': note,
        'participations': [
          for (final e in participations.entries)
            {'person_id': e.key, 'status': e.value.name},
        ],
      };

  Trip copyWith({
    DateTime? date,
    Map<String, ParticipationStatus>? participations,
    String? note,
  }) =>
      Trip(
        id: id,
        date: date ?? this.date,
        participations: participations ?? this.participations,
        note: note ?? this.note,
      );
}
