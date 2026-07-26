/// persons_screen.dart – Personen der Gruppe anlegen und pflegen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/carpool_repository.dart';
import '../../data/providers.dart';
import '../../models/person.dart';

class PersonsScreen extends ConsumerWidget {
  const PersonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Personen')),
      // Bewusst kein schwebender Knopf: Der überdeckte die unterste Person
      // in der Liste (Marcus' Handy-Fund, 2026-07-22). „Person anlegen"
      // steht stattdessen unter dem letzten Eintrag und scrollt mit.
      body: switch (persons) {
        AsyncData(value: final list) => ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.l),
                child: Text('Noch niemand angelegt.'),
              )
            else ...[
              const _DeactivateHint(),
              for (final person in _sorted(list))
                _PersonTile(
                  person: person,
                  onEdit: () => _edit(context, ref, person, list),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                AppSpacing.m,
                AppSpacing.m,
                0,
              ),
              child: FilledButton.tonalIcon(
                onPressed: () => _edit(context, ref, null, list),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Person anlegen'),
              ),
            ),
          ],
        ),
        AsyncError(:final error) => Center(
          child: Text('Fehler beim Laden: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  /// Aktive zuerst, darin alphabetisch — inaktive rutschen ans Ende, statt
  /// zwischen den Stammgästen zu stehen.
  static List<Person> _sorted(List<Person> persons) {
    return [...persons]..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  }
}

/// Legt an oder aktualisiert; `null` bedeutet „neu".
///
/// [existing] ist die geladene Liste — sie trägt die Vorprüfung auf einen
/// schon vergebenen Namen, damit die Meldung ohne Roundtrip kommt.
Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  Person? person,
  List<Person> existing,
) async {
  final result = await showDialog<Person>(
    context: context,
    builder: (context) => _PersonDialog(person: person),
  );
  if (result == null || !context.mounted) return;

  // Ein Name gehört in der Gruppe genau einer Person (Issue #109) —
  // verglichen wie der Unique-Index in der Datenbank und wie der CSV-Import
  // Namen zuordnet: getrimmt, ohne Groß-/Kleinschreibung. Inaktive zählen
  // mit: Wer zurückkommt, wird reaktiviert. Eine zweite Zeile spaltete seine
  // Punkte-Historie und verschöbe rückwirkend die Quote aller anderen.
  //
  // Diese Prüfung ist der Komfort, nicht der Riegel — der steht in der
  // Datenbank, weil zwei Geräte gleichzeitig anlegen können. Deshalb fängt
  // der catch unten denselben Fall noch einmal.
  final needle = result.name.trim().toLowerCase();
  if (existing.any(
    (p) => p.id != result.id && p.name.trim().toLowerCase() == needle,
  )) {
    _report(context, result.name);
    return;
  }

  final repository = ref.read(carpoolRepositoryProvider);
  try {
    if (person == null) {
      await repository.createPerson(result);
    } else {
      await repository.updatePerson(result);
    }
  } on DuplicatePersonName catch (error) {
    if (context.mounted) _report(context, error.name);
    return;
  } catch (_) {
    // Ohne diesen Zweig verschwand JEDER Fehlschlag still in der
    // async-Funktion: Der Dialog schloss sich, als hätte es geklappt, und die
    // Person fehlte einfach. Dieselbe Klasse wie der tote Update-Knopf in
    // 0.37.0 — sichtbar wurde es erst, als der Unique-Constraint aus #109
    // regelmäßig zuschlug. Bewusst ohne den Fehlertext: Der trüge Details aus
    // der Datenbank in die Oberfläche.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte nicht gespeichert werden.')),
      );
    }
    return;
  }
  // Ohne die Invalidierung bliebe die Liste auf dem Stand vom Login —
  // personsProvider lädt sonst nur bei Wechsel des Benutzers neu.
  ref.invalidate(personsProvider);
}

void _report(BuildContext context, String name) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('„$name" gibt es in der Gruppe schon.')),
  );
}

class _DeactivateHint extends StatelessWidget {
  const _DeactivateHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.m,
        AppSpacing.m,
        0,
      ),
      child: Text(
        'Wer nicht mehr mitfährt, wird inaktiv gesetzt statt gelöscht: '
        'Löschen würde die vergangenen Fahrten mitnehmen und damit die '
        'Punkte aller anderen verändern.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.person, required this.onEdit});

  final Person person;
  final VoidCallback onEdit;

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    try {
      await ref
          .read(carpoolRepositoryProvider)
          .updatePerson(person.copyWith(active: active));
    } catch (_) {
      // Der Schalter zeigt den Wert aus dem Provider, nicht einen eigenen
      // Zustand: Scheitert das Schreiben, tippt man ihn an und es passiert
      // schlicht nichts. Ohne Meldung sieht das wie ein toter Schalter aus.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konnte nicht gespeichert werden.')),
        );
      }
      return;
    }
    ref.invalidate(personsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = person.vehicle;
    final energy = person.energyType;
    final consumption = person.consumptionPer100km;
    final details = <String>[
      if (vehicle != null && vehicle.isNotEmpty) vehicle,
      if (energy != null) _energyLabel(energy),
      if (consumption != null) '$consumption / 100 km',
      '${person.seats} Sitze',
    ];

    return ListTile(
      title: Text(person.name),
      subtitle: Text(
        details.isEmpty ? 'Kein Fahrzeug hinterlegt' : details.join(' · '),
      ),
      onTap: onEdit,
      trailing: Switch(
        value: person.active,
        onChanged: (value) => _setActive(context, ref, value),
      ),
    );
  }
}

String _energyLabel(EnergyType energy) => switch (energy) {
  EnergyType.electric => 'Strom',
  EnergyType.diesel => 'Diesel',
  EnergyType.petrol => 'Benzin',
};

class _PersonDialog extends StatefulWidget {
  const _PersonDialog({this.person});

  final Person? person;

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.person?.name ?? '',
  );
  late final TextEditingController _vehicle = TextEditingController(
    text: widget.person?.vehicle ?? '',
  );
  late final TextEditingController _consumption = TextEditingController(
    text: widget.person?.consumptionPer100km?.toString() ?? '',
  );
  // Neue Personen starten mit der Vorgabe im Feld, statt es leer zu lassen:
  // Sonst wüsste niemand, dass 5 gilt, wenn man nichts einträgt.
  late final TextEditingController _seats = TextEditingController(
    text: (widget.person?.seats ?? defaultSeats).toString(),
  );
  late EnergyType? _energy = widget.person?.energyType;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _vehicle.dispose();
    _consumption.dispose();
    _seats.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ein Name wird gebraucht.');
      return;
    }
    final consumptionText = _consumption.text.trim().replaceAll(',', '.');
    final consumption = consumptionText.isEmpty
        ? null
        : double.tryParse(consumptionText);
    if (consumptionText.isNotEmpty &&
        (consumption == null || consumption <= 0)) {
      setState(() => _error = 'Verbrauch bitte als Zahl größer 0.');
      return;
    }

    // Sitzplätze inklusive Fahrer. Eine 1 wäre fast immer ein Vertipper —
    // ein Einsitzer kann keine Fahrgemeinschaft fahren. Ein leeres Feld
    // heißt „normaler PKW", nicht „unbekannt".
    final seatsText = _seats.text.trim();
    final seats = seatsText.isEmpty ? defaultSeats : int.tryParse(seatsText);
    if (seats == null || seats < 2) {
      setState(() => _error = 'Sitzplätze bitte als ganze Zahl ab 2.');
      return;
    }

    final vehicle = _vehicle.text.trim();
    Navigator.of(context).pop(
      Person(
        id: widget.person?.id ?? '',
        name: name,
        active: widget.person?.active ?? true,
        vehicle: vehicle.isEmpty ? null : vehicle,
        energyType: _energy,
        consumptionPer100km: consumption,
        seats: seats,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.person == null ? 'Person anlegen' : 'Person ändern'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _vehicle,
              decoration: const InputDecoration(
                labelText: 'Fahrzeug (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            DropdownButtonFormField<EnergyType?>(
              initialValue: _energy,
              decoration: const InputDecoration(
                labelText: 'Antrieb (optional)',
              ),
              items: [
                const DropdownMenuItem<EnergyType?>(
                  child: Text('Keine Angabe'),
                ),
                for (final energy in EnergyType.values)
                  DropdownMenuItem<EnergyType?>(
                    value: energy,
                    child: Text(_energyLabel(energy)),
                  ),
              ],
              onChanged: (value) => setState(() => _energy = value),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _consumption,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Verbrauch je 100 km (optional)',
                helperText: 'Nur damit die Ersparnis berechnet werden kann.',
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: _seats,
              keyboardType: TextInputType.number,
              // „inkl. Fahrer" muss dranstehen: Sonst trägt der eine die
              // Zahl aus dem Fahrzeugschein ein und der andere zieht sich
              // selbst ab — und keine der beiden Zahlen stimmt später.
              decoration: const InputDecoration(
                labelText: 'Sitzplätze inkl. Fahrer',
                helperText: 'Damit auffällt, wenn ihr mehr seid als passen.',
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.person == null ? 'Anlegen' : 'Speichern'),
        ),
      ],
    );
  }
}
