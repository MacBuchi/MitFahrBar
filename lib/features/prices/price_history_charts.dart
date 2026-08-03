/// price_history_charts.dart – Die beiden Preis-Verläufe (Kraftstoff, Strom)
/// samt Quellenangabe.
///
/// EIN Widget für zwei Flächen: den Preis-Screen (`/prices`, dort mit
/// Verwaltung drumherum) und die Sektion „Spritpreise" der Statistik-Seite.
/// Zwei Kopien zeigten beim nächsten Feinschliff verschiedene Verläufe für
/// dieselben Daten.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/price_series.dart';
import '../../core/tokens.dart';
import '../../core/widgets/price_chart.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';

/// Kleinstes Fenster des Diagramms. Nach hinten wächst es bis zur
/// ältesten Woche, für die es Werte gibt — ein Nachfüll-Lauf
/// (`tool/import_fuel_history.py`) trägt Jahre ein, und ein festes
/// Fenster hätte sie unsichtbar gemacht: Der Import wäre gelaufen und
/// man hätte nichts davon gesehen. Nach unten bleibt die Grenze stehen,
/// damit eine frisch eingerichtete Gruppe eine Kurve sieht und nicht
/// einen Punkt.
const priceChartMinWeeks = 26;

class PriceHistoryCharts extends ConsumerWidget {
  const PriceHistoryCharts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final weeks = ref.watch(priceWeeksProvider);
    final settings = ref.watch(settingsProvider);

    if (weeks.hasError || settings.hasError) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Text(
          'Die Wochenwerte konnten nicht geladen werden.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    if (weeks.isLoading || settings.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._charts(
          context,
          ref,
          stored: weeks.value ?? const [],
          settingsValue: settings.value!,
        ),
        const SizedBox(height: 24),
        // Pflichtangabe der Quelle, nicht Höflichkeit: Die Daten stehen unter
        // CC BY 4.0 und stammen aus der Markttransparenzstelle für
        // Kraftstoffe. Sie reist mit den Diagrammen, egal auf welcher Seite
        // sie stehen.
        Text(
          'Preise: Tankerkönig-Spritpreis-API (CC BY 4.0), Daten der '
          'Markttransparenzstelle für Kraftstoffe. Strompreise kommen aus '
          'euren Parametern, nicht aus dem Netz.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _charts(
    BuildContext context,
    WidgetRef ref, {
    required List<PricePoint> stored,
    required AppSettings settingsValue,
  }) {
    final theme = Theme.of(context);
    // Beide Enden richten sich nach den Daten — Begründung steht bei
    // `chartWindow`, und dort ist sie auch geprüft. Die Uhr kommt aus dem
    // Provider, nicht von der Wand: In Tests steht sie auf einem festen Tag.
    final (from, to) = chartWindow(
      stored: stored,
      now: ref.read(nowProvider)(),
      minWeeks: priceChartMinWeeks,
    );

    Map<PriceSeries, List<PricePoint>> build(List<PriceSeries> series) => {
      for (final entry in series)
        entry: weeklySeries(
          series: entry,
          from: from,
          to: to,
          stored: stored,
          settings: settingsValue,
        ),
    };

    return [
      Text('Kraftstoff', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      PriceTrendChart(
        lines: build(const [
          PriceSeries.diesel,
          PriceSeries.e5,
          PriceSeries.e10,
        ]),
        unit: '€/l',
      ),
      const SizedBox(height: 24),
      Text('Strom', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      PriceTrendChart(
        lines: build(const [PriceSeries.housePower, PriceSeries.chargingPower]),
        unit: '€/kWh',
      ),
    ];
  }
}
