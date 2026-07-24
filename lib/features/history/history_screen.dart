/// history_screen.dart – Fahrtenliste mit Bearbeiten/Löschen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/trip.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider);
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historie')),
      body: switch ((trips, persons)) {
        (AsyncData(value: final tripList), AsyncData(value: final personList))
            when tripList.isNotEmpty =>
          _TripList(trips: tripList, persons: personList),
        (AsyncData(), AsyncData()) => const Center(
          child: Text('Noch keine Fahrten eingetragen.'),
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

class _TripList extends ConsumerWidget {
  const _TripList({required this.trips, required this.persons});

  final List<Trip> trips;
  final List<Person> persons;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final p in persons) p.id: p};
    final dateFormat = DateFormat('EE, dd.MM.yyyy', 'de');

    String nameOf(String id) => byId[id]?.name ?? id;

    return ListView.builder(
      itemCount: trips.length,
      itemBuilder: (context, index) {
        final trip = trips[index];
        final driver = trip.driverId;
        // Solo-Fahrten zählen in keiner Kennzahl (Issue #61) — die Liste
        // zeigt sie blass und sagt dazu, warum.
        final solo = isSoloTrip(trip);
        // Mehrere Fahrten am selben Tag (Issue #62): Die Liste ist nach
        // Datum sortiert, gleiche Tage stehen also beieinander — ab der
        // zweiten bekommt jede einen „2. Auto"-Chip. Die Nummer ist die
        // Position in der Liste, keine Aussage über die Abfahrtsfolge.
        var carNumber = 1;
        for (
          var i = index - 1;
          i >= 0 && _sameDay(trips[i].date, trip.date);
          i--
        ) {
          carNumber++;
        }
        final passengers = [
          for (final e in trip.participations.entries)
            if (e.value == ParticipationStatus.passenger) nameOf(e.key),
          for (final e in trip.participations.entries)
            if (e.value == ParticipationStatus.oneWay)
              '${nameOf(e.key)} (1-way)',
        ];
        return ListTile(
          // Blass, aber weiter antipp-/bearbeitbar — vielleicht fehlt ja
          // nur ein vergessener Mitfahrer.
          textColor: solo ? Theme.of(context).disabledColor : null,
          title: Row(
            children: [
              Text(dateFormat.format(trip.date)),
              if (carNumber > 1) ...[
                const SizedBox(width: AppSpacing.s),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.s),
                  ),
                  child: Text(
                    '$carNumber. Auto',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            '${driver == null ? 'Kein Fahrer' : 'Fahrer: ${nameOf(driver)}'}'
            '${passengers.isEmpty ? '' : ' · Mit: ${passengers.join(', ')}'}'
            '${solo ? ' · allein gefahren, zählt nicht' : ''}',
          ),
          onTap: () => context.push('/trip/${trip.id}'),
          trailing: PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'edit') {
                // Bewusst nicht abgewartet: Der Rückgabewert der Navigation
                // interessiert hier nicht, und ein await würde das Menü bis
                // zur Rückkehr offen halten.
                unawaited(context.push('/trip/${trip.id}'));
              } else if (action == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Fahrt löschen?'),
                    content: Text(
                      'Fahrt vom ${dateFormat.format(trip.date)} wirklich '
                      'löschen? Punkte werden neu berechnet.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Abbrechen'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Löschen'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(carpoolRepositoryProvider).deleteTrip(trip.id);
                  ref.invalidate(tripsProvider);
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Bearbeiten')),
              PopupMenuItem(value: 'delete', child: Text('Löschen')),
            ],
          ),
        );
      },
    );
  }
}
