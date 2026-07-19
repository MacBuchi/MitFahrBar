/// dashboard_screen.dart – „Wer ist dran" + Mini-Statistik.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/supabase_config.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/person.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(activeRankingProvider);
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fahrgemeinschaft'),
        actions: [
          if (SupabaseConfig.isConfigured)
            IconButton(
              tooltip: 'Abmelden',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trip/new'),
        icon: const Icon(Icons.add),
        label: const Text('Fahrt eintragen'),
      ),
      body: switch ((ranking, persons)) {
        (AsyncData(value: final ranked), AsyncData(value: final personList))
            when ranked.isNotEmpty =>
          _Content(ranked: ranked, persons: personList),
        (AsyncData(), AsyncData()) => const Center(
            child: Text('Noch keine Personen angelegt.'),
          ),
        (AsyncError(:final error), _) => Center(
            child: Text('Fehler beim Laden: $error'),
          ),
        (_, AsyncError(:final error)) => Center(
            child: Text('Fehler beim Laden: $error'),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.ranked, required this.persons});

  final List<RankedCandidate> ranked;
  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final p in persons) p.id: p};
    final points = NumberFormat('#,##0.#', 'de');
    final percent = NumberFormat.percentPattern('de');

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.m, AppSpacing.m, AppSpacing.m, AppSpacing.xs),
          child: Text('Wer ist dran?',
              style: Theme.of(context).textTheme.titleLarge),
        ),
        Card(
          child: Column(
            children: [
              for (final (index, candidate) in ranked.indexed)
                ListTile(
                  leading: _RankBadge(rank: index + 1),
                  title: Text(
                    byId[candidate.personId]?.name ?? candidate.personId,
                    style: index == 0
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  subtitle: Text(
                    '${points.format(candidate.stats.points)} Punkte · '
                    'Fahranteil ${percent.format(candidate.stats.driveShare)}',
                  ),
                  trailing: index == 0
                      ? const Icon(Icons.directions_car,
                          color: AppColors.driver)
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        _MiniStats(persons: persons),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = rank <= 2;
    return CircleAvatar(
      radius: 16,
      backgroundColor:
          highlighted ? scheme.primary : scheme.surfaceContainerHighest,
      foregroundColor:
          highlighted ? scheme.onPrimary : scheme.onSurfaceVariant,
      child: Text('$rank'),
    );
  }
}

class _MiniStats extends ConsumerWidget {
  const _MiniStats({required this.persons});

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
    final euro = NumberFormat.currency(locale: 'de', symbol: '€');

    var totalSaved = 0.0;
    for (final s in stats.values) {
      final person = byId[s.personId];
      if (person != null) totalSaved += s.savedCosts(settings, person);
    }

    final kmRanked = stats.values.toList()
      ..sort((a, b) =>
          b.kilometers(settings).compareTo(a.kilometers(settings)));
    final heroes = kmRanked
        .take(2)
        .map((s) => byId[s.personId]?.name ?? s.personId)
        .join(' & ');

    final thisYear =
        trips.where((t) => t.date.year == DateTime.now().year).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gemeinsam erreicht',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s),
            _statRow(context, Icons.savings_outlined,
                '${euro.format(totalSaved)} Kraftstoff gespart'),
            _statRow(context, Icons.event_repeat_outlined,
                '$thisYear Fahrten dieses Jahr · ${trips.length} insgesamt'),
            if (heroes.isNotEmpty)
              _statRow(
                  context, Icons.emoji_events_outlined, 'Kilometerhelden: $heroes'),
          ],
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
