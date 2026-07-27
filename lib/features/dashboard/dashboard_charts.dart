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
import '../../core/widgets/charts.dart';
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

    final byId = {for (final p in persons) p.id: p};
    final euro = NumberFormat.currency(
      locale: 'de',
      symbol: '€',
      decimalDigits: 0,
    );
    final number = NumberFormat('#,##0', 'de');

    var totalSaved = 0.0;
    var totalKm = 0.0;
    for (final s in stats.values) {
      final person = byId[s.personId];
      if (person != null) totalSaved += s.savedCosts(settings, person);
      totalKm += s.kilometers(settings);
    }

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

    return _ChartCard(
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

/// Fahrten je Monat – zeigt den Rhythmus der Gruppe über ein Jahr.
class MonthlyTripsCard extends ConsumerWidget {
  const MonthlyTripsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider).value;
    if (trips == null || trips.isEmpty) return const SizedBox.shrink();

    // Das Fenster reicht bis zur ersten Fahrt (#119) — eine Gruppe, die seit
    // Jahren fährt, sah vorher nur ihr letztes Jahr. Passt das nicht in die
    // Breite, scrollt das Diagramm.
    final now = ref.watch(nowProvider)();
    final buckets = tripsPerMonth(
      trips,
      months: monthsToCover(trips, now),
      now: now,
    );
    if (buckets.every((b) => b.trips == 0)) return const SizedBox.shrink();

    final range = DateFormat('MMM yyyy', 'de');
    return _ChartCard(
      title: 'Fahrten pro Monat',
      subtitle:
          '${range.format(buckets.first.date)} – '
          '${range.format(buckets.last.date)}',
      child: MonthlyTripsChart(data: buckets),
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
    return _ChartCard(
      title: 'Wie ihr unterwegs seid',
      subtitle: 'Tage je Person, aufgeteilt nach Art der Teilnahme',
      child: ParticipationMixChart(rows: rows),
    );
  }
}

/// Gemeinsamer Rahmen: Überschrift, optionale Erläuterung, Inhalt.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle case final String text) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            child,
          ],
        ),
      ),
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
