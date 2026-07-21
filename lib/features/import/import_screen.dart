/// import_screen.dart – Fahrten aus einer CSV übernehmen.
///
/// Der Ablauf ist bewusst zweistufig: erst lesen und **zeigen, was passieren
/// würde**, dann schreiben. Grund ist nicht Bequemlichkeit — `persons.name`
/// hat in der Datenbank keine Eindeutigkeit. Würde der Import Personen still
/// anlegen, entstünden aus „Marcus" und „Marcus " zwei Personen, und das
/// verschiebt rückwirkend die Punkte *aller anderen* (Issue #34).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/csv_import.dart';
import '../../core/log.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/trip.dart';

/// Auswahlwerte, die keine Personen-Id sind. Ids sind UUIDs, eine Kollision
/// ist also ausgeschlossen.
const _createNew = '__neu__';
const _skipPerson = '__weglassen__';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  ImportResult? _result;

  /// Name aus der Datei → `_createNew`, `_skipPerson` oder eine Personen-Id.
  final Map<String, String> _choice = {};
  bool _busy = false;
  String? _done;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final text = await ref.read(filePickerProvider)();
      if (text == null) return; // abgebrochen ist kein Fehler
      final persons = await ref.read(personsProvider.future);
      final result = parseTripCsv(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _done = null;
        _choice
          ..clear()
          ..addEntries(
            result.names.map(
              (name) => MapEntry(name, _matchOrNew(name, persons)),
            ),
          );
      });
      log.i(
        'csv import parsed: ${result.trips.length} trips, '
        '${result.names.length} names, ${result.problems.length} problems',
      );
    } catch (error) {
      log.e('csv import failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datei konnte nicht gelesen werden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wer schon existiert, wird von allein zugeordnet — Groß-/Kleinschreibung
  /// und Leerzeichen am Rand sind dabei egal, denn genau daran scheitert es
  /// beim Abtippen.
  static String _matchOrNew(String name, List<Person> persons) {
    final needle = name.trim().toLowerCase();
    for (final person in persons) {
      if (person.name.trim().toLowerCase() == needle) return person.id;
    }
    return _createNew;
  }

  Future<void> _import(List<Person> persons, List<Trip> existing) async {
    final result = _result;
    if (result == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(carpoolRepositoryProvider);

    try {
      // 1. Personen anlegen, die angelegt werden sollen.
      final idByName = <String, String>{};
      var created = 0;
      for (final entry in _choice.entries) {
        if (entry.value == _skipPerson) continue;
        if (entry.value == _createNew) {
          final person = await repository.createPerson(
            Person(id: '', name: entry.key.trim(), active: true),
          );
          idByName[entry.key] = person.id;
          created++;
        } else {
          idByName[entry.key] = entry.value;
        }
      }

      // 2. Fahrten schreiben. Tage, die es schon gibt, bleiben liegen: Ein
      //    zweiter Eintrag wäre ein zweites Auto, und das lässt sich beim
      //    Import nicht von einem Doppelimport unterscheiden.
      final takenDays = {for (final t in existing) _dayKey(t.date)};
      var imported = 0;
      var skippedExisting = 0;
      var skippedPerson = 0;
      for (final trip in result.trips) {
        if (takenDays.contains(_dayKey(trip.date))) {
          skippedExisting++;
          continue;
        }
        // Eine Fahrt, an der jemand Weggelassenes beteiligt war, wird ganz
        // ausgelassen. Sie ohne diese Person anzulegen, änderte still die
        // Punkte aller übrigen an diesem Tag.
        if (trip.participations.keys.any((n) => !idByName.containsKey(n))) {
          skippedPerson++;
          continue;
        }
        await repository.createTrip(trip.date, {
          for (final e in trip.participations.entries)
            idByName[e.key]!: e.value,
        }, note: trip.note);
        takenDays.add(_dayKey(trip.date));
        imported++;
      }

      ref
        ..invalidate(personsProvider)
        ..invalidate(tripsProvider)
        ..invalidate(weekPlanProvider);
      log.i(
        'csv import done: $imported trips, $created persons, '
        'skipped $skippedExisting existing / $skippedPerson incomplete',
      );

      if (!mounted) return;
      setState(() {
        _result = null;
        _done = [
          '$imported ${imported == 1 ? 'Fahrt' : 'Fahrten'} übernommen',
          if (created > 0)
            '$created ${created == 1 ? 'Person' : 'Personen'} angelegt',
          if (skippedExisting > 0)
            '$skippedExisting übersprungen (Tag war schon eingetragen)',
          if (skippedPerson > 0)
            '$skippedPerson übersprungen (jemand war weggelassen)',
        ].join(' · ');
      });
    } catch (error) {
      log.e('csv import write failed: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Übernehmen fehlgeschlagen.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  @override
  Widget build(BuildContext context) {
    final persons = ref.watch(personsProvider).value ?? const <Person>[];
    final trips = ref.watch(tripsProvider).value ?? const <Trip>[];
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Fahrten importieren')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          Text(
            'Nimm eine Datei aus dem Export — sie hat genau das richtige '
            'Format. Gebraucht werden nur Datum und wer gefahren bzw. '
            'mitgefahren ist; Fahrzeug und Verbrauch pflegt ihr in der App.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.m),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: const Text('CSV-Datei wählen'),
          ),
          if (_done case final done?) ...[
            const SizedBox(height: AppSpacing.m),
            _Notice(text: done, tone: _Tone.good),
          ],
          if (result != null) ...[
            const SizedBox(height: AppSpacing.l),
            _Summary(result: result),
            if (result.problems.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              _Problems(problems: result.problems),
            ],
            if (result.trips.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.l),
              Text(
                'Wer ist wer?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Bekannte Namen sind schon zugeordnet. Prüfe die neuen — ein '
                'Tippfehler legt sonst eine zweite Person an und verschiebt '
                'die Punkte aller anderen.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.s),
              for (final name in result.names)
                _NameRow(
                  name: name,
                  persons: persons,
                  value: _choice[name] ?? _createNew,
                  onChanged: (value) => setState(() => _choice[name] = value),
                ),
              const SizedBox(height: AppSpacing.l),
              FilledButton.icon(
                onPressed: _busy ? null : () => _import(persons, trips),
                icon: const Icon(Icons.check),
                label: Text(
                  _busy
                      ? 'Übernehme …'
                      : '${result.trips.length} Fahrten übernehmen',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    if (result.trips.isEmpty) {
      return const _Notice(
        text: 'Aus dieser Datei lässt sich keine Fahrt lesen.',
        tone: _Tone.bad,
      );
    }
    final format = DateFormat('dd.MM.yyyy', 'de');
    final first = format.format(result.trips.first.date);
    final last = format.format(result.trips.last.date);
    return _Notice(
      text:
          '${result.trips.length} Fahrten gefunden, $first bis $last, '
          '${result.names.length} Personen in der Kopfzeile.',
      tone: _Tone.good,
    );
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      tone: _Tone.warn,
      text: [
        problems.length == 1
            ? 'Eine Zeile stimmt nicht:'
            : '${problems.length} Zeilen stimmen nicht:',
        ...problems,
      ].join('\n'),
    );
  }
}

class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.name,
    required this.persons,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final List<Person> persons;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isNew = value == _createNew;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                if (isNew) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.fiber_new_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem(
                  value: _createNew,
                  child: Text('neu anlegen'),
                ),
                for (final person in persons)
                  DropdownMenuItem(
                    value: person.id,
                    child: Text(
                      'ist ${person.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: _skipPerson,
                  child: Text('weglassen'),
                ),
              ],
              onChanged: (v) => v == null ? null : onChanged(v),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { good, warn, bad }

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _Tone.good => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tone.warn => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tone.bad => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.s),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: foreground),
      ),
    );
  }
}
