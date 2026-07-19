/// stats_screen.dart – Kennzahlen pro Person (Punkte, Quote, km, Ersparnis).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';
import '../../models/person.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final persons = ref.watch(personsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistik')),
      body: switch ((stats, persons, settings)) {
        (
          AsyncData(value: final statMap),
          AsyncData(value: final personList),
          AsyncData(value: final settingsValue),
        ) =>
          _StatsList(
            stats: statMap,
            persons: personList,
            settings: settingsValue,
          ),
        (AsyncError(:final error), _, _) =>
          Center(child: Text('Fehler beim Laden: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({
    required this.stats,
    required this.persons,
    required this.settings,
  });

  final Map<String, PersonStats> stats;
  final List<Person> persons;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final points = NumberFormat('#,##0.#', 'de');
    final km = NumberFormat('#,##0', 'de');
    final euro = NumberFormat.currency(locale: 'de', symbol: '€');
    final percent = NumberFormat.percentPattern('de');
    final quote = NumberFormat('#,##0.00', 'de');

    // Aktive zuerst (nach Punkten aufsteigend), dann Inaktive.
    final sorted = [...persons]..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        final pa = stats[a.id]?.points ?? 0;
        final pb = stats[b.id]?.points ?? 0;
        return pa.compareTo(pb);
      });

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.l),
      children: [
        for (final person in sorted)
          if (stats[person.id] case final PersonStats s) _PersonCard(
              person: person,
              stats: s,
              settings: settings,
              points: points,
              km: km,
              euro: euro,
              percent: percent,
              quote: quote),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.stats,
    required this.settings,
    required this.points,
    required this.km,
    required this.euro,
    required this.percent,
    required this.quote,
  });

  final Person person;
  final PersonStats stats;
  final AppSettings settings;
  final NumberFormat points;
  final NumberFormat km;
  final NumberFormat euro;
  final NumberFormat percent;
  final NumberFormat quote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!person.active)
                  Chip(
                    label: const Text('inaktiv'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.xs,
              children: [
                _kv(context, 'Punkte', points.format(stats.points),
                    emphasized: true),
                _kv(context, 'gefahren', '${stats.driven}×'),
                _kv(context, 'mitgefahren', '${stats.ridden}×'),
                _kv(context, '1-way', '${stats.oneWay}×'),
                _kv(context, 'Fahranteil', percent.format(stats.driveShare)),
                if (stats.quote case final double q)
                  _kv(context, 'Ø mitgenommen', quote.format(q)),
                _kv(context, 'Kilometer',
                    '${km.format(stats.kilometers(settings))} km'),
                _kv(context, 'gespart',
                    euro.format(stats.savedCosts(settings, person))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value,
      {bool emphasized = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.bold : FontWeight.normal,
            color: emphasized ? scheme.primary : null,
          ),
        ),
      ],
    );
  }
}
