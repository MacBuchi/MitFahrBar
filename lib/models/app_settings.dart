/// app_settings.dart – Gruppenweite Parameter (Excel-„Help"-Blatt).
library;

class AppSettings {
  const AppSettings({
    this.commuteKm = 30,
    this.oneWayFactor = 0.5,
    this.electricityPricePerKwh = 0.35,
    this.dieselPricePerLiter = 1.70,
    this.petrolPricePerLiter = 1.78,
    this.pointsWeight = 1.0,
  });

  /// Einfacher Arbeitsweg in km (überall ×2 für Hin/Rück).
  final double commuteKm;

  /// Gewicht einer 1-way-Mitfahrt gegenüber einer vollen Mitfahrt.
  final double oneWayFactor;

  final double electricityPricePerKwh;
  final double dieselPricePerLiter;
  final double petrolPricePerLiter;

  /// Gewichtung Punkte-Rang vs. Fahranteil-Rang in der Fairness-Regel
  /// (1.0 = nur Punkte, 0.5 = 50/50, 0.0 = nur Fahranteil).
  ///
  /// Steht seit 2026-07-21 auf 1.0: Die Gruppe hat entschieden, dass allein
  /// die Punkte über die Reihenfolge bestimmen (Issue #38). Der Fahranteil
  /// bleibt als Kennzahl sichtbar, steuert aber nichts mehr. Der Parameter
  /// bleibt bestehen — er ist der Weg zurück, ohne die Formel anzufassen.
  final double pointsWeight;

  /// Kopie mit geänderten Kosten-Parametern.
  ///
  /// Bewusst **ohne** `oneWayFactor` und `pointsWeight`: Die beiden ändern
  /// rückwirkend die Punkte aller — sie gehören nicht in einen Screen, den
  /// jedes Gruppenmitglied öffnen kann, sondern in eine Migration
  /// (siehe CLAUDE.md). Der Parameter-Screen reicht sie unverändert durch.
  AppSettings copyWith({
    double? commuteKm,
    double? electricityPricePerKwh,
    double? dieselPricePerLiter,
    double? petrolPricePerLiter,
  }) => AppSettings(
    commuteKm: commuteKm ?? this.commuteKm,
    oneWayFactor: oneWayFactor,
    electricityPricePerKwh:
        electricityPricePerKwh ?? this.electricityPricePerKwh,
    dieselPricePerLiter: dieselPricePerLiter ?? this.dieselPricePerLiter,
    petrolPricePerLiter: petrolPricePerLiter ?? this.petrolPricePerLiter,
    pointsWeight: pointsWeight,
  );

  factory AppSettings.fromMap(Map<String, double> map) => AppSettings(
    commuteKm: map['commute_km'] ?? 30,
    oneWayFactor: map['one_way_factor'] ?? 0.5,
    electricityPricePerKwh: map['electricity_price_per_kwh'] ?? 0.35,
    dieselPricePerLiter: map['diesel_price_per_liter'] ?? 1.70,
    petrolPricePerLiter: map['petrol_price_per_liter'] ?? 1.78,
    pointsWeight: map['points_weight'] ?? 1.0,
  );

  Map<String, double> toMap() => {
    'commute_km': commuteKm,
    'one_way_factor': oneWayFactor,
    'electricity_price_per_kwh': electricityPricePerKwh,
    'diesel_price_per_liter': dieselPricePerLiter,
    'petrol_price_per_liter': petrolPricePerLiter,
    'points_weight': pointsWeight,
  };
}
