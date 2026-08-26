/// export_action.dart – „Daten exportieren" aus dem Zugangs-Menü.
///
/// Der Export ist die einzige Sicherung, die die Gruppe selbst in der Hand
/// hat: Alles seit dem Erst-Import lebt nur in Supabase.
///
/// Seit #272 sind es **zwei** Dateien statt einer: Fahrten und Parameter.
/// Getrennt statt in Abschnitten einer Datei, weil jede für sich eine Tabelle
/// bleibt, die deutsches Excel per Doppelklick aufmacht; Blöcke mit
/// verschiedener Spaltenzahl kann es nicht.
///
/// **Die Wochenpreise des Archivs bleiben draußen** — sie stehen unter
/// CC BY-NC-SA, und eine weiterreichbare Datei wäre die Weitergabe, die die
/// ShareAlike-Klausel auslöst (siehe csv_export.dart). Der Wunsch aus #272
/// ist damit nicht erfüllbar; die Historie geht trotzdem nicht verloren, der
/// nächtliche Nachfüll-Lauf holt fehlende Wochen aus dem Archiv zurück.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/csv_export.dart';
import '../../core/export_file.dart';
import '../../core/log.dart';
import '../../data/providers.dart';

/// Baut die Sicherung aus dem geladenen Stand und übergibt sie der Plattform.
///
/// Meldet über [context] zurück, was passiert ist — deshalb wird der
/// Messenger vor dem ersten `await` gegriffen.
Future<void> exportTripsCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final persons = await ref.read(personsProvider.future);
    final trips = await ref.read(tripsProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final defaults = await ref.read(groupDefaultsProvider.future);

    final today = DateTime.now();
    final files = <ExportFile>[
      ExportFile(
        name: csvFileName(today),
        content: buildTripCsv(persons: persons, trips: trips),
      ),
      ExportFile(
        name: settingsCsvFileName(today),
        content: buildSettingsCsv(settings: settings, defaults: defaults),
      ),
    ];

    await ref.read(fileSaverProvider)(files);

    // Nur Anzahlen, keine Namen: Die Log-Zeilen können per Rückmeldung in
    // einem öffentlichen Issue landen.
    log.i(
      'csv export: ${trips.length} trips, ${persons.length} persons, '
      '${files.length} files',
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          trips.isEmpty
              // Ohne Fahrten ist die Datei genau das, wonach im Issue
              // gefragt wurde: eine leere Vorlage mit den echten Spalten.
              ? 'Leere Vorlage mit allen Personen-Spalten erstellt.'
              : '${files.length} Dateien erstellt: '
                    '${trips.length} Fahrten und die Parameter.',
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
