/// dashboard_charts.dart – Die Auswertungs-Karten der Startseite.
///
/// Alle Werte werden hier aus Fahrten und Parametern berechnet, nie geladen.
/// Fehlen Daten, verschwindet die jeweilige Karte still – eine leere Achse
/// sagt weniger als gar keine Karte.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../core/chart_data.dart';
import '../../core/tokens.dart';
import '../../core/widgets/chart_card.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/savings_chart.dart';
import '../../data/providers.dart';
import '../../models/person.dart';

/// Gemeinsame Kennzahlen – drei Zahlen, für die ein Diagramm zu viel wäre.
class GroupAchievementsCard extends ConsumerWidget {
  const GroupAchievementsCard({super.key, required this.persons});

  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;
    final settings = ref.watch(settingsProvider).value;
    final trips = ref.watch(tripsProvider).value;
    if (stats == null || settings == null || trips == null) {
      return const SizedBox.shrink();
    }

    final euro = NumberFormat.currency(
      locale: 'de',
      symbol: '€',
      decimalDigits: 0,
    );
    final number = NumberFormat('#,##0', 'de');

    // Die Ersparnis kommt aus **derselben** Rechnung wie die Kurve darunter
    // (`weeklySavings`), nicht aus `savedCosts` über die Gesamtzahlen. Sonst
    // stünde hier eine Summe und im Diagramm eine andere — zwei Wahrheiten
    // über dieselbe Zahl, sichtbar nebeneinander auf einer Seite.
    final totalSaved = ref.watch(savingsChartProvider)?.total ?? 0;
    var totalKm = 0.0;
    for (final s in stats.values) {
      totalKm += s.kilometers(settings);
    }

    final byId = {for (final p in persons) p.id: p};
    final kmRanked = stats.values.toList()
      ..sort(
        (a, b) => b.kilometers(settings).compareTo(a.kilometers(settings)),
      );
    final heroes = kmRanked
        .take(2)
        .map((s) => byId[s.personId]?.name ?? s.personId)
        .join(' & ');

    // Uhr aus dem Provider, nicht von der Wand: In Tests steht sie auf einem
    // festen Tag, und eine Karte, die daran vorbei rechnet, zeigt am
    // Jahreswechsel etwas anderes als der Rest der App.
    final now = ref.watch(nowProvider)();
    final thisYear = trips.where((t) => t.date.year == now.year).length;

    return ChartCard(
      title: 'Gemeinsam erreicht',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatTile(
                label: 'Personen-km',
                value: number.format(totalKm),
                icon: Icons.route_outlined,
              ),
              _StatTile(
                label: 'Kraftstoff gespart',
                value: euro.format(totalSaved),
                icon: Icons.savings_outlined,
              ),
              _StatTile(
                label: 'Fahrten',
                value: number.format(trips.length),
                icon: Icons.event_repeat_outlined,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          _FootNote('$thisYear Fahrten in diesem Jahr'),
          if (heroes.isNotEmpty) _FootNote('Kilometerhelden: $heroes'),
        ],
      ),
    );
  }
}

/// Fahrten und Ersparnis über die Wochen — EINE Karte, EINE Zeitachse
/// (entschieden 02.08.2026, ersetzt „Fahrten pro Monat" + eine getrennte
/// Ersparnis-Karte). Die Fahrten liegen als blasse Säulen hinter den
/// Kurven; der ausgesprochene Preis: „20 Fahrten im Dezember" ist nicht
/// mehr exakt ablesbar, dafür zeigen Fahren und Sparen ein Bild.
///
/// **Jede Woche rechnet mit dem Preis dieser Woche** (Preisarchiv, seit
/// v0.53.0). Über dreieinhalb Jahre lag Diesel zwischen 1,46 € und 2,26 €;
/// eine einzige Konstante über den ganzen Zeitraum verteilte die Ersparnis
/// auf die falschen Wochen. Wo kein Preis vorliegt, trägt die Kurve die
/// Konstante aus den Parametern — und ist ab dort gestrichelt.
class SavingsCard extends ConsumerWidget {
  const SavingsCard({super.key, required this.persons});

  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chart = ref.watch(savingsChartProvider);
    // Ohne zwei Wochen gibt es keine Kurve; ganz ohne Fahrten keine Karte.
    if (chart == null || chart.weeks.length < 2) {
      return const SizedBox.shrink();
    }
    if (chart.tripCounts.every((count) => count == 0)) {
      return const SizedBox.shrink();
    }

    final range = DateFormat('MMM yyyy', 'de');
    final euro = NumberFormat.currency(
      locale: 'de',
      symbol: '€',
      decimalDigits: 0,
    );

    return ChartCard(
      title: 'Fahrten und Ersparnis',
      // Auch ohne Ersparnis (kein Fahrzeug trägt Verbrauch) bleibt die
      // Karte: Die Säulen beantworten weiterhin, wann gefahren wurde.
      subtitle: chart.total > 0
          ? '${euro.format(chart.total)} seit '
                '${range.format(chart.weeks.first.monday)} — '
                'Kraftstoff, den ihr durchs Mitfahren nicht gebraucht habt'
          : 'Fahrten je Woche seit '
                '${range.format(chart.weeks.first.monday)}. Die Ersparnis '
                'erscheint, sobald Fahrzeuge Antrieb und Verbrauch tragen.',
      child: SavingsTrendChart(
        chart: chart,
        names: {for (final person in persons) person.id: person.name},
        // Wer an diesem Gerät „ich" ist (#121). Das ist eine
        // Geräte-Einstellung und keine Zugriffskontrolle — sie hebt hier
        // nur eine Linie hervor, alle anderen bleiben sichtbar.
        highlightPersonId: ref.watch(myPersonProvider)?.id,
      ),
    );
  }
}

/// Teilnahme-Mix je Person: Länge = Beteiligung, Aufteilung = deren Art.
class ParticipationMixCard extends ConsumerWidget {
  const ParticipationMixCard({super.key, required this.persons});

  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider).value;
    if (stats == null) return const SizedBox.shrink();

    final rows = <ParticipationRow>[];
    for (final person in persons.where((p) => p.active)) {
      final s = stats[person.id];
      if (s == null || s.participationDays == 0) continue;
      rows.add(
        ParticipationRow(
          label: person.name,
          driven: s.driven,
          oneWay: s.oneWay,
          ridden: s.ridden,
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    rows.sort((a, b) => b.total.compareTo(a.total));
    return ChartCard(
      title: 'Wie ihr unterwegs seid',
      subtitle: 'Tage je Person, aufgeteilt nach Art der Teilnahme',
      child: ParticipationMixChart(rows: rows),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.xs),
          // Große Zahlen bekommen proportionale Ziffern; Tabellenziffern
          // lassen sie bei dieser Größe auseinandergezogen wirken.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.titleLarge),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FootNote extends StatelessWidget {
  const _FootNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
