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

/// Was ein „Jetzt aktualisieren" ergeben hat.
///
/// Der Knopf wertet das aus, statt einen Erfolg zu melden, den er nicht
/// geprüft hat: Die Function antwortet auch bei gescheitertem Abruf mit 200
/// und nennt den Ausgang im Rumpf. Dieselbe Fehlerklasse wie der tote
/// Update-Knopf in 0.37.0.
class SampleResult {
  const SampleResult({required this.stored, required this.failed});

  /// Wie viele Stationen abgelegt wurden.
  final int stored;

  /// Ob mindestens eine Region gescheitert ist.
  final bool failed;

  bool get ok => !failed && stored > 0;
}

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

  /// Tastet den eigenen Bereich sofort ab (Nutzeraktion).
  Future<SampleResult> sampleNow();
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

  @override
  Future<SampleResult> sampleNow() async {
    final response = await _client.functions.invoke('fuel-sample', body: {});
    final data = response.data;
    if (data is! Map || data['results'] is! List) {
      return const SampleResult(stored: 0, failed: true);
    }

    var stored = 0;
    var failed = false;
    for (final entry in data['results'] as List) {
      if (entry is! Map) continue;
      if (entry['error'] != null) {
        failed = true;
        continue;
      }
      stored += (entry['stored'] as num?)?.toInt() ?? 0;
    }
    return SampleResult(stored: stored, failed: failed);
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

  @override
  Future<SampleResult> sampleNow() async =>
      const SampleResult(stored: 0, failed: true);
}
