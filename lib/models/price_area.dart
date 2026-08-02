/// price_area.dart – Wo eine Gruppe tankt, und was die Ortssuche liefert.
library;

/// Standardradius der Umkreissuche.
///
/// An der Zielregion gemessen (Bad Rappenau, 02.08.2026): 93 Tankstellen im
/// 20-km-Kreis. Der Wert entscheidet vor allem über die Datenmenge, kaum
/// über die Zahl — das 10. Perzentil lag bei 10 und 20 km auf den
/// Zehntel-Cent gleich, während das Minimum um 11 ct wanderte.
const double defaultRadiusKm = 20;

/// Tankerkönig deckelt die Umkreissuche hier; darüber antwortet die API mit
/// einem Fehler statt mit weniger Ergebnissen.
const double maxRadiusKm = 25;

class PriceArea {
  const PriceArea({
    required this.label,
    required this.lat,
    required this.lng,
    this.radiusKm = defaultRadiusKm,
  });

  /// Anzeigename aus der Ortssuche. Mitgespeichert, damit im Screen steht,
  /// worauf sich die Reihe bezieht — eine nackte Koordinate sagt niemandem
  /// etwas.
  final String label;
  final double lat;
  final double lng;
  final double radiusKm;

  PriceArea copyWith({
    String? label,
    double? lat,
    double? lng,
    double? radiusKm,
  }) => PriceArea(
    label: label ?? this.label,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radiusKm: radiusKm ?? this.radiusKm,
  );

  factory PriceArea.fromMap(Map<String, dynamic> map) => PriceArea(
    label: map['label'] as String,
    lat: (map['lat'] as num).toDouble(),
    lng: (map['lng'] as num).toDouble(),
    radiusKm: (map['radius_km'] as num?)?.toDouble() ?? defaultRadiusKm,
  );

  /// Ohne `region_key`: Die Spalte ist in der Datenbank generiert. Sie
  /// mitzuschicken scheiterte mit „cannot insert into generated column".
  Map<String, dynamic> toMap() => {
    'label': label,
    'lat': lat,
    'lng': lng,
    'radius_km': radiusKm,
  };
}

/// Ein Treffer der Ortssuche.
class GeoPlace {
  const GeoPlace({required this.label, required this.lat, required this.lng});

  final String label;
  final double lat;
  final double lng;

  factory GeoPlace.fromMap(Map<String, dynamic> map) => GeoPlace(
    label: map['label'] as String,
    lat: (map['lat'] as num).toDouble(),
    lng: (map['lng'] as num).toDouble(),
  );
}
