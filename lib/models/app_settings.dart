/// app_settings.dart – Gruppenweite Parameter (Excel-„Help"-Blatt).
library;

class AppSettings {
  const AppSettings({
    this.commuteKm = 30,
    this.oneWayFactor = 0.5,
    this.electricityPricePerKwh = 0.35,
    this.dieselPricePerLiter = 1.70,
    this.petrolPricePerLiter = 1.78,
    this.pointsWeight = 0.5,
  });

  /// Einfacher Arbeitsweg in km (überall ×2 für Hin/Rück).
  final double commuteKm;

  /// Gewicht einer 1-way-Mitfahrt gegenüber einer vollen Mitfahrt.
  final double oneWayFactor;

  final double electricityPricePerKwh;
  final double dieselPricePerLiter;
  final double petrolPricePerLiter;

  /// Gewichtung Punkte-Rang vs. Fahranteil-Rang in der Fairness-Regel
  /// (0.5 = 50/50; 1.0 = nur Punkte, 0.0 = nur Fahranteil).
  final double pointsWeight;

  factory AppSettings.fromMap(Map<String, double> map) => AppSettings(
        commuteKm: map['commute_km'] ?? 30,
        oneWayFactor: map['one_way_factor'] ?? 0.5,
        electricityPricePerKwh: map['electricity_price_per_kwh'] ?? 0.35,
        dieselPricePerLiter: map['diesel_price_per_liter'] ?? 1.70,
        petrolPricePerLiter: map['petrol_price_per_liter'] ?? 1.78,
        pointsWeight: map['points_weight'] ?? 0.5,
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
