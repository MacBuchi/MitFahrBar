/// app_settings.dart – Gruppenweite Parameter (Excel-„Help"-Blatt).
library;

class AppSettings {
  const AppSettings({
    this.commuteKm = 30,
    this.oneWayFactor = 0.5,
    this.electricityPricePerKwh = 0.35,
    this.chargingPricePerKwh = 0.59,
    this.dieselPricePerLiter = 1.70,
    this.petrolPricePerLiter = 1.78,
    this.e10PricePerLiter = 1.68,
    this.pointsWeight = 1.0,
    this.carAssignmentEnabled = false,
  });

  /// Einfacher Arbeitsweg in km (überall ×2 für Hin/Rück).
  final double commuteKm;

  /// Gewicht einer 1-way-Mitfahrt gegenüber einer vollen Mitfahrt.
  final double oneWayFactor;

  /// Hausstrom — was eine kWh an der eigenen Steckdose kostet.
  final double electricityPricePerKwh;

  /// Tankstellenstrom — öffentliches Laden, deutlich teurer als Hausstrom.
  final double chargingPricePerKwh;

  final double dieselPricePerLiter;

  /// Super E5. Der Schlüssel heißt in der DB weiter `petrol_price_per_liter`:
  /// Umbenennen hieße, dass ein noch nicht aktualisierter Client den Wert
  /// nicht mehr findet und still auf die Vorgabe zurückfiele — falsche
  /// Zahlen ohne jede Fehlermeldung.
  final double petrolPricePerLiter;

  /// Super E10, typischerweise rund 10 ct unter E5. Eigener Wert statt
  /// eines Aufschlags auf E5: Der Abstand schwankt, und als Fallback für
  /// die Preisreihe soll dastehen, was die Gruppe wirklich zahlt.
  final double e10PricePerLiter;

  /// Gewichtung Punkte-Rang vs. Fahranteil-Rang in der Fairness-Regel
  /// (1.0 = nur Punkte, 0.5 = 50/50, 0.0 = nur Fahranteil).
  ///
  /// Steht seit 2026-07-21 auf 1.0: Die Gruppe hat entschieden, dass allein
  /// die Punkte über die Reihenfolge bestimmen (Issue #38). Der Fahranteil
  /// bleibt als Kennzahl sichtbar, steuert aber nichts mehr. Der Parameter
  /// bleibt bestehen — er ist der Weg zurück, ohne die Formel anzufassen.
  final double pointsWeight;

  /// Ordnet die Gruppe ihre Leute einzelnen Autos zu? (#213)
  ///
  /// Aus heißt: keine Abfahrt je Auto, keine Zusage, keine Auto-Wahl — und
  /// im Push stehen ausschließlich die Zeiten aus `group_defaults`. Der
  /// Schalter existiert, weil es **keinen Stable-/Latest-Kanal** gibt: Ein
  /// Merge mit Versions-Bump *ist* die Veröffentlichung und erreicht alle
  /// Gruppen zugleich, also ist ein Wert, den die Gruppe selbst umlegen
  /// kann, der einzige Rückweg ohne neues Release.
  ///
  /// **Vorgabe aus, und das ist die Vorgabe für NEUE Gruppen.** Fehlt die
  /// Zeile, gilt aus; bestehende Gruppen hat die Migration auf 1 gesetzt,
  /// damit ihnen nichts weggenommen wird, was sie schon benutzen.
  ///
  /// Aus wirkt in [planWeek] und im Ausgangskorb — die abgelegten Zeilen in
  /// `plan_car_defaults` und `plan_seat_choices` werden dabei **inert**, nicht
  /// gelöscht. Ein Schalter, der Daten wegwirft, wäre kein Rückweg: Beim
  /// Wiedereinschalten gilt wieder, was dastand. Dieselbe Linie wie bei den
  /// verwaisten Zeilen.
  final bool carAssignmentEnabled;

  /// Kopie mit geänderten Kosten-Parametern.
  ///
  /// Bewusst **ohne** `oneWayFactor` und `pointsWeight`: Die beiden ändern
  /// rückwirkend die Punkte aller — sie gehören nicht in einen Screen, den
  /// jedes Gruppenmitglied öffnen kann, sondern in eine Migration
  /// (siehe CLAUDE.md). Der Parameter-Screen reicht sie unverändert durch.
  AppSettings copyWith({
    double? commuteKm,
    double? electricityPricePerKwh,
    double? chargingPricePerKwh,
    double? dieselPricePerLiter,
    double? petrolPricePerLiter,
    double? e10PricePerLiter,
    bool? carAssignmentEnabled,
  }) => AppSettings(
    commuteKm: commuteKm ?? this.commuteKm,
    oneWayFactor: oneWayFactor,
    electricityPricePerKwh:
        electricityPricePerKwh ?? this.electricityPricePerKwh,
    chargingPricePerKwh: chargingPricePerKwh ?? this.chargingPricePerKwh,
    dieselPricePerLiter: dieselPricePerLiter ?? this.dieselPricePerLiter,
    petrolPricePerLiter: petrolPricePerLiter ?? this.petrolPricePerLiter,
    e10PricePerLiter: e10PricePerLiter ?? this.e10PricePerLiter,
    pointsWeight: pointsWeight,
    carAssignmentEnabled: carAssignmentEnabled ?? this.carAssignmentEnabled,
  );

  factory AppSettings.fromMap(Map<String, double> map) => AppSettings(
    commuteKm: map['commute_km'] ?? 30,
    oneWayFactor: map['one_way_factor'] ?? 0.5,
    electricityPricePerKwh: map['electricity_price_per_kwh'] ?? 0.35,
    chargingPricePerKwh: map['charging_price_per_kwh'] ?? 0.59,
    dieselPricePerLiter: map['diesel_price_per_liter'] ?? 1.70,
    petrolPricePerLiter: map['petrol_price_per_liter'] ?? 1.78,
    e10PricePerLiter: map['e10_price_per_liter'] ?? 1.68,
    pointsWeight: map['points_weight'] ?? 1.0,
    // `settings.value` ist numeric — der Schalter reist als 0/1. Fehlt die
    // Zeile, ist er aus: Das ist der Zustand einer neuen Gruppe.
    carAssignmentEnabled: (map['car_assignment_enabled'] ?? 0) != 0,
  );

  Map<String, double> toMap() => {
    'commute_km': commuteKm,
    'one_way_factor': oneWayFactor,
    'electricity_price_per_kwh': electricityPricePerKwh,
    'charging_price_per_kwh': chargingPricePerKwh,
    'diesel_price_per_liter': dieselPricePerLiter,
    'petrol_price_per_liter': petrolPricePerLiter,
    'e10_price_per_liter': e10PricePerLiter,
    'points_weight': pointsWeight,
    'car_assignment_enabled': carAssignmentEnabled ? 1 : 0,
  };
}
