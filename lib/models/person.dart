/// person.dart – Person der Fahrgemeinschaft inkl. Fahrzeugdaten.
library;

enum EnergyType { electric, diesel, petrol }

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.active,
    this.vehicle,
    this.energyType,
    this.consumptionPer100km,
    this.seats,
  });

  final String id;
  final String name;

  /// Inaktive Personen bleiben in der Historie, sind aber aus dem Ranking raus.
  final bool active;
  final String? vehicle;
  final EnergyType? energyType;
  final double? consumptionPer100km;

  /// Sitzplätze **inklusive Fahrer** — die Zahl aus dem Fahrzeugschein, die
  /// man von seinem Auto kennt („Fünfsitzer"). Mitfahrer-Plätze zu speichern
  /// hieße, bei jeder Eingabe eins abzuziehen, und erzeugt genau die
  /// Off-by-one-Fehler, die man später nicht mehr erklären kann.
  ///
  /// `null` heißt „unbekannt" und darf nie zu einer Warnung oder zu einem
  /// Ausschluss führen — sonst bestraft die App Gruppen, die das Feld nicht
  /// pflegen.
  final int? seats;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String,
    active: json['active'] as bool,
    vehicle: json['vehicle'] as String?,
    energyType: json['energy_type'] == null
        ? null
        : EnergyType.values.byName(json['energy_type'] as String),
    consumptionPer100km: (json['consumption_per_100km'] as num?)?.toDouble(),
    seats: (json['seats'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'active': active,
    'vehicle': vehicle,
    'energy_type': energyType?.name,
    'consumption_per_100km': consumptionPer100km,
    'seats': seats,
  };

  Person copyWith({
    String? name,
    bool? active,
    String? vehicle,
    EnergyType? energyType,
    double? consumptionPer100km,
    int? seats,
  }) => Person(
    id: id,
    name: name ?? this.name,
    active: active ?? this.active,
    vehicle: vehicle ?? this.vehicle,
    energyType: energyType ?? this.energyType,
    consumptionPer100km: consumptionPer100km ?? this.consumptionPer100km,
    seats: seats ?? this.seats,
  );
}
