/// stats_cards.dart – Die Diagramm-Karten der Statistik-Seite.
///
/// Alle Werte werden berechnet, nie geladen; fehlen Daten, verschwindet die
/// jeweilige Karte still (dieselbe Linie wie auf der Übersicht). Zwei Karten
/// hängen bewusst NICHT am Preisarchiv („Fahrten pro Woche", „CO₂
/// eingespart") — sie dürfen nicht mit dem Preisabruf verschwinden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../core/balance_label.dart';
import '../../core/chart_data.dart';
import '../../core/stats_data.dart';
import '../../core/tokens.dart';
import '../../core/widgets/chart_card.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/mini_savings_curve.dart';
import '../../core/widgets/ring_chart.dart';
import '../../core/widgets/weekly_bars.dart';
import '../../data/providers.dart';
import '../prices/price_history_charts.dart';

/// Dasselbe €-Format wie die Kachel „Kraftstoff gespart" auf der Übersicht:
/// Donut-Mitte, große Summe und Kachel müssen EINEN String zeigen.
NumberFormat _tileEuro() =>
    NumberFormat.currency(locale: 'de', symbol: '€', decimalDigits: 0);

const _weekdayShort = {
  DateTime.monday: 'Mo',
  DateTime.tuesday: 'Di',
  DateTime.wednesday: 'Mi',
  DateTime.thursday: 'Do',
  DateTime.friday: 'Fr',
  DateTime.saturday: 'Sa',
  DateTime.sunday: 'So',
};

const _weekdayAdverb = {
  DateTime.monday: 'montags',
  DateTime.tuesday: 'dienstags',
  DateTime.wednesday: 'mittwochs',
  DateTime.thursday: 'donnerstags',
  DateTime.friday: 'freitags',
  DateTime.saturday: 'samstags',
  DateTime.sunday: 'sonntags',
};

/// „Fahrten pro Woche" — die letzten zwölf Wochen als Balken.
class WeeklyTripsCard extends ConsumerWidget {
  const WeeklyTripsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bars = ref.watch(weeklyTripBarsProvider);
    if (bars == null) return const SizedBox.shrink();

    final average = NumberFormat('#,##0.0', 'de').format(bars.average);
    final record = weekShortLabel(bars.recordWeek, reference: bars.weeks.last);
    final outside = bars.recordIndex == null ? ' (vor diesem Ausschnitt)' : '';
    return ChartCard(
      title: 'Fahrten pro Woche',
      subtitle:
          'Ø $average je Woche · Rekord: $record mit '
          '${bars.recordCount} Fahrten$outside',
      child: WeeklyBarsChart(bars: bars),
    );
  }
}

/// „Gemeinsam gespart" — die fokussierte Gruppen-Kurve mit Meilenstein,
/// Tankfüllungs-Vergleich und Hochrechnung.
class GroupSavingsCard extends ConsumerWidget {
  const GroupSavingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chart = ref.watch(savingsChartProvider);
    final settings = ref.watch(settingsProvider).value;
    if (chart == null || settings == null || chart.weeks.length < 2) {
      return const SizedBox.shrink();
    }
    if (chart.total <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final euro = _tileEuro();
    final milestone = savingsMilestone(chart);
    final projection = yearEndProjection(chart, now: ref.watch(nowProvider)());
    final tanks = tankEquivalents(chart.total, settings);
    final footer = [
      if (tanks >= 1) 'Das sind $tanks Tankfüllung${tanks == 1 ? '' : 'en'}',
      if (projection != null)
        'bei eurem Tempo ≈ ${euro.format(projection)} bis Jahresende',
    ].join(' · ');
    final range = DateFormat('MMM yyyy', 'de');

    return ChartCard(
      title: 'Gemeinsam gespart',
      subtitle:
          'Seit ${range.format(chart.weeks.first.monday)}, mit dem '
          'Spritpreis der jeweiligen Woche',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            euro.format(chart.total),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppStatsColors.eco(theme.brightness),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          MiniSavingsCurve(
            chart: chart,
            color: AppStatsColors.eco(theme.brightness),
            milestoneIndex: milestone?.weekIndex,
          ),
          if (milestone != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '● ${milestone.amount} € geknackt in '
              '${weekShortLabel(chart.weeks[milestone.weekIndex], reference: chart.weeks.last)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (footer.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              footer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// „Wer hat wie viel erspart?" — der Ersparnis-Ring je Person.
class SavingsDonutCard extends ConsumerWidget {
  const SavingsDonutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chart = ref.watch(savingsChartProvider);
    final persons = ref.watch(personsProvider).value;
    if (chart == null || persons == null || chart.perPerson.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final names = {for (final person in persons) person.id: person.name};
    // Dieselbe Reihenfolge und dieselben Farben wie die Linien im
    // Ersparnis-Diagramm — eine Person trägt überall EINE Farbe.
    final order = savingsOrder(chart);
    final colors = {
      for (var i = 0; i < order.length; i++)
        order[i]: personLineColor(i, order.length, theme.brightness),
    };
    final euro = NumberFormat.currency(locale: 'de', symbol: '€');
    // Die Mitte zeigt `chart.total` — denselben Wert wie die Kachel auf der
    // Übersicht. Damit die Segmente sichtbar zur Mitte summieren, bekommt
    // ein Übertrag (Fahrten außerhalb des Fensters, z. B. ein Vertipper in
    // der Zukunft) ein eigenes neutrales Segment statt zu fehlen.
    final segments = [
      for (final id in order)
        (value: chart.perPerson[id]!.last, color: colors[id]!),
      if (chart.carriedOver > 0)
        (value: chart.carriedOver, color: theme.colorScheme.outline),
    ];

    return ChartCard(
      title: 'Wer hat wie viel erspart?',
      subtitle: 'Ersparnis der Mitfahrenden — zusammen die Zahl der Übersicht',
      child: Row(
        children: [
          SegmentRing(
            segments: segments,
            size: 150,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _tileEuro().format(chart.total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'zusammen',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in order)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: colors[id],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: Text(
                            names[id] ?? id,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          euro.format(chart.perPerson[id]!.last),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                if (chart.carriedOver > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: Text(
                            'Übertrag',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          euro.format(chart.carriedOver),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// „CO₂ eingespart" — aus Verbrauch und Spritart der eigenen Autos, ohne
/// Preisarchiv. E-Autos zählen 0 (entschieden 2026-08-03).
class Co2Card extends ConsumerWidget {
  const Co2Card({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;
    final persons = ref.watch(personsProvider).value;
    final settings = ref.watch(settingsProvider).value;
    if (stats == null || persons == null || settings == null) {
      return const SizedBox.shrink();
    }
    final kg = groupSavedCo2Kg(stats, persons, settings);
    if (kg <= 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final goal = nextCo2Milestone(kg);
    final trees = kg ~/ kCo2PerTreeYear;
    final km = avoidedSoloKm(stats, persons, settings);
    final number = NumberFormat('#,##0', 'de');

    return ChartCard(
      title: 'CO₂ eingespart',
      subtitle:
          'Aus Verbrauch und Spritart eurer Autos gerechnet — '
          'E-Autos zählen 0',
      child: Row(
        children: [
          ProgressRing(
            progress: kg / goal,
            color: AppStatsColors.eco(theme.brightness),
            trackColor: theme.colorScheme.surfaceContainerHighest,
            size: 150,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${number.format(kg)} kg',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppStatsColors.eco(theme.brightness),
                  ),
                ),
                Text(
                  'von ${number.format(goal)} kg',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (trees >= 1) ...[
                  _EquivalenceTile(
                    value: '≈ $trees ${trees == 1 ? 'Baum' : 'Bäume'}',
                    caption: trees == 1
                        ? 'bindet das in einem Jahr'
                        : 'binden das in einem Jahr',
                  ),
                  const SizedBox(height: AppSpacing.s),
                ],
                _EquivalenceTile(
                  value: '${number.format(km)} km',
                  caption: 'Solo-Fahrten vermieden',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquivalenceTile extends StatelessWidget {
  const _EquivalenceTile({required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            caption,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// „Wie ihr unterwegs seid" — die Balken der Übersicht, ergänzt um Fahrten,
/// Saldo und die „ist dran"-Marke.
class ParticipationDetailCard extends ConsumerWidget {
  const ParticipationDetailCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;
    final persons = ref.watch(personsProvider).value;
    if (stats == null || persons == null) return const SizedBox.shrink();
    // Wer als Nächstes fahren sollte — dieselbe Rechnung wie „Wer ist
    // dran?" auf der Übersicht, hier nur als Marke an der Zeile.
    final ranked = ref.watch(activeRankingProvider).value;
    final nextUp = ranked == null || ranked.isEmpty
        ? null
        : ranked.first.personId;

    final theme = Theme.of(context);
    final points = NumberFormat('#,##0.#', 'de');
    final rows = <({String id, ParticipationRow row, double saldo})>[];
    for (final person in persons.where((p) => p.active)) {
      final s = stats[person.id];
      if (s == null || s.participationDays == 0) continue;
      rows.add((
        id: person.id,
        row: ParticipationRow(
          label: person.name,
          driven: s.driven,
          oneWay: s.oneWay,
          ridden: s.ridden,
        ),
        saldo: s.points,
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    rows.sort((a, b) => b.row.total.compareTo(a.row.total));
    final maxTotal = rows.first.row.total.toDouble();

    return ChartCard(
      title: 'Wie ihr unterwegs seid',
      subtitle:
          'Tage je Person, mit Punkte-Saldo — wer im Minus ist, ist '
          'bald dran',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MixLegend(),
          const SizedBox(height: AppSpacing.m),
          for (final entry in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s),
              child: Semantics(
                label:
                    '${entry.row.label}: ${entry.row.total} Tage, Saldo '
                    '${signedPoints(entry.saldo, points)}'
                    '${entry.id == nextUp ? ', ist dran' : ''}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.row.label,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (entry.id == nextUp) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'ist dran',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                        ],
                        Text(
                          '${entry.row.total} Tage · Saldo ',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          signedPoints(entry.saldo, points),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: entry.saldo < 0
                                ? AppStatsColors.saldoNegative(theme.brightness)
                                : AppStatsColors.saldoPositive(
                                    theme.brightness,
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StackedMixBar(row: entry.row, maxTotal: maxTotal),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// „Euer Wochen-Muster" — die Wochentags-Heatmap als Widget-Raster
/// (dasselbe Muster wie der Kalender in `marked_date_picker.dart`): Zellen
/// und Beschriftungen sind Widgets, für Tests und Semantik erreichbar.
class WeekdayHeatmapCard extends ConsumerWidget {
  const WeekdayHeatmapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider).value;
    final persons = ref.watch(personsProvider).value;
    if (trips == null || persons == null) return const SizedBox.shrink();
    final matrix = weekdayDriveMatrix(trips);
    if (matrix == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final names = {for (final person in persons) person.id: person.name};
    final dominance = weekdayDominance(matrix);

    return ChartCard(
      title: 'Euer Wochen-Muster',
      subtitle: 'Wer fährt an welchem Wochentag am häufigsten?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 84 + AppSpacing.s),
              for (final weekday in matrix.weekdays)
                Expanded(
                  child: Text(
                    _weekdayShort[weekday]!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var row = 0; row < matrix.personIds.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      names[matrix.personIds[row]] ?? matrix.personIds[row],
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  for (var col = 0; col < matrix.weekdays.length; col++)
                    Expanded(
                      child: Semantics(
                        label:
                            '${names[matrix.personIds[row]] ?? ''}, '
                            '${_weekdayAdverb[matrix.weekdays[col]]} '
                            '${matrix.counts[row][col]}-mal gefahren',
                        child: Container(
                          height: 32,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            // Die Skala endet bei VOLLER Deckung: `primary`
                            // mit Restdeckung trüge auf der hellen Karte
                            // keine 3,0:1 mehr (gemessen, siehe
                            // stats_contrast_test).
                            color: matrix.counts[row][col] == 0
                                ? theme.colorScheme.surfaceContainerHighest
                                : theme.colorScheme.primary.withValues(
                                    alpha:
                                        0.12 +
                                        0.88 *
                                            matrix.counts[row][col] /
                                            matrix.max,
                                  ),
                            borderRadius: BorderRadius.circular(AppRadius.s),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (dominance != null) ...[
            const SizedBox(height: AppSpacing.s),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.m),
              ),
              child: Text(
                '💡 ${_capitalize(_weekdayAdverb[dominance.weekday]!)} fährt '
                'fast immer ${names[dominance.personId] ?? '—'} — Zeit, dass '
                'jemand übernimmt?',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _capitalize(String word) => word[0].toUpperCase() + word.substring(1);
}

/// Sektion „Spritpreise": dieselben Verläufe wie `/prices`, die Verwaltung
/// (Region, Abruf) bleibt dort — hier führt ein Knopf hin.
class PricesSectionCard extends ConsumerWidget {
  const PricesSectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeks = ref.watch(priceWeeksProvider).value;
    // Ohne Wochendaten sagt die Sektion nichts — eingerichtet wird unter
    // Einstellungen → Spritpreise, nicht hier.
    if (weeks == null || weeks.isEmpty) return const SizedBox.shrink();

    return ChartCard(
      title: 'Spritpreise',
      subtitle: 'Je Woche das 10. Perzentil eurer Region',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PriceHistoryCharts(),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/prices'),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Preis-Region & Abruf'),
            ),
          ),
        ],
      ),
    );
  }
}
