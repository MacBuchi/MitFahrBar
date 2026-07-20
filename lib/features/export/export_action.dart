/// export_action.dart – „Daten exportieren" aus dem Zugangs-Menü.
///
/// Der Export ist die einzige Sicherung, die die Gruppe selbst in der Hand
/// hat: Alles seit dem Erst-Import lebt nur in Supabase.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/csv_export.dart';
import '../../core/log.dart';
import '../../data/providers.dart';

/// Baut die CSV aus dem geladenen Stand und übergibt sie der Plattform.
///
/// Meldet über [context] zurück, was passiert ist — deshalb wird der
/// Messenger vor dem ersten `await` gegriffen.
Future<void> exportTripsCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final persons = await ref.read(personsProvider.future);
    final trips = await ref.read(tripsProvider.future);
    final csv = buildTripCsv(persons: persons, trips: trips);

    await ref.read(fileSaverProvider)(
      name: csvFileName(DateTime.now()),
      content: csv,
    );

    // Nur Anzahlen, keine Namen: Die Log-Zeilen können per Rückmeldung in
    // einem öffentlichen Issue landen.
    log.i('csv export: ${trips.length} trips, ${persons.length} persons');

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          trips.isEmpty
              // Ohne Fahrten ist die Datei genau das, wonach im Issue
              // gefragt wurde: eine leere Vorlage mit den echten Spalten.
              ? 'Leere Vorlage mit allen Personen-Spalten erstellt.'
              : 'CSV mit ${trips.length} Fahrten erstellt.',
        ),
      ),
    );
  } catch (error) {
    log.e('csv export failed: $error');
    messenger.showSnackBar(
      const SnackBar(content: Text('Export fehlgeschlagen.')),
    );
  }
}
