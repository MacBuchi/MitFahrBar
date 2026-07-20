/// history_screen.dart – Fahrtenliste mit Bearbeiten/Löschen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
        final passengers = [
          for (final e in trip.participations.entries)
            if (e.value == ParticipationStatus.passenger) nameOf(e.key),
          for (final e in trip.participations.entries)
            if (e.value == ParticipationStatus.oneWay)
              '${nameOf(e.key)} (1-way)',
        ];
        return ListTile(
          title: Text(dateFormat.format(trip.date)),
          subtitle: Text(
            '${driver == null ? 'Kein Fahrer' : 'Fahrer: ${nameOf(driver)}'}'
            '${passengers.isEmpty ? '' : ' · Mit: ${passengers.join(', ')}'}',
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
