/// price_repository.dart – Preisarchiv: Bereich, Wochenwerte, Ortssuche.
///
/// Der Client liest hier **nur**. Geschrieben werden Stichproben und
/// Wochenwerte allein vom Abtast- und Verdichtungslauf mit dem
/// service_role-Key; die Rohschicht sieht er nie. Einzige Ausnahme ist der
/// eigene Bereich (`price_area`) — den richtet die Gruppe ein.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/price_series.dart';
import '../models/price_area.dart';
import 'read_retry.dart';

abstract class PriceRepository {
  /// Der Bereich dieser Gruppe, oder `null` — dann ist das Feature aus.
  Future<PriceArea?> loadArea();

  Future<void> saveArea(PriceArea area);

  /// Alle bekannten Wochenwerte der Gruppe, aufsteigend.
  ///
  /// Bewusst ohne Zeitfenster im Repository: Es sind drei Zeilen je Woche,
  /// also gut 150 im Jahr. Ein Filter über (iso_year, iso_week) müsste den
  /// Jahreswechsel zusammensetzen — dafür ist die Menge zu klein.
  Future<List<PricePoint>> loadWeeks();

  /// Ortssuche für die Einrichtung.
  Future<List<GeoPlace>> searchPlace(String query);
}

class SupabasePriceRepository implements PriceRepository {
  SupabasePriceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PriceArea?> loadArea() => readTolerant(() async {
    final row = await _client
        .from('price_area')
        .select('label, lat, lng, radius_km')
        .maybeSingle();
    return row == null ? null : PriceArea.fromMap(row);
  });

  @override
  Future<void> saveArea(PriceArea area) async {
    final groupId = _client.auth.currentUser?.id;
    await _client.from('price_area').upsert({
      'group_id': groupId,
      ...area.toMap(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'group_id');
  }

  @override
  Future<List<PricePoint>> loadWeeks() => readTolerant(() async {
    final rows = await _client
        .from('price_week')
        .select(
          'iso_year, iso_week, series, value, sample_count, '
          'station_count, origin',
        )
        .order('iso_year')
        .order('iso_week');

    final points = <PricePoint>[];
    for (final row in rows) {
      final series = PriceSeries.fromKey(row['series'] as String);
      // Unbekannte Reihe wird übersprungen statt zu werfen — dieselbe
      // Linie wie `Group.statusFrom`: Ein künftiger Wert in der Datenbank
      // darf keinen Screen sprengen.
      if (series == null) continue;
      points.add(
        PricePoint(
          week: IsoWeek(row['iso_year'] as int, row['iso_week'] as int),
          series: series,
          value: (row['value'] as num).toDouble(),
          origin: _originFrom(row['origin'] as String?),
          sampleCount: (row['sample_count'] as num?)?.toInt() ?? 0,
          stationCount: (row['station_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return points;
  });

  static PriceOrigin _originFrom(String? value) => switch (value) {
    'imported' => PriceOrigin.imported,
    'mixed' => PriceOrigin.mixed,
    _ => PriceOrigin.measured,
  };

  @override
  Future<List<GeoPlace>> searchPlace(String query) async {
    final response = await _client.functions.invoke(
      'geocode-place',
      body: {'query': query},
    );
    final data = response.data;
    if (data is! Map || data['places'] is! List) return const [];
    return [
      for (final place in data['places'] as List)
        if (place is Map) GeoPlace.fromMap(Map<String, dynamic>.from(place)),
    ];
  }
}

/// Demo-Modus: kein Backend, also kein Preisarchiv.
class NoopPriceRepository implements PriceRepository {
  const NoopPriceRepository();

  @override
  Future<PriceArea?> loadArea() async => null;

  @override
  Future<void> saveArea(PriceArea area) async {}

  @override
  Future<List<PricePoint>> loadWeeks() async => const [];

  @override
  Future<List<GeoPlace>> searchPlace(String query) async => const [];
}
