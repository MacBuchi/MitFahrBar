/// plan_screen.dart – Wochenplaner: wer kann wann, wer fährt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/mood.dart';
import '../../core/tokens.dart';
import '../../core/widgets/mood_face.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/plan_ride.dart';
import '../../models/trip.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(weekPlanProvider);
    final persons = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wochenplan')),
      body: switch ((plan, persons)) {
        (AsyncData(value: final days), AsyncData(value: final all)) => _Content(
          days: days,
          persons: [
            for (final p in all)
              if (p.active) p,
          ]..sort((a, b) => a.name.compareTo(b.name)),
        ),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          Center(child: Text('Fehler beim Laden: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.days, required this.persons});

  final List<PlannedDay> days;
  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (persons.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.l),
          child: Text('Erst Personen anlegen, dann lässt sich planen.'),
        ),
      );
    }

    final byId = {for (final p in persons) p.id: p};
    final celebratedId = mostCarryingDriver(days);
    final celebrated = celebratedId == null ? null : byId[celebratedId];
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Text(
            'Tippt an, wann ihr könnt. RideBuddy schlägt daraufhin vor, wer '
            'an welchem Tag fährt — so, dass Punkte und Fahranteil über die '
            'Woche ausgeglichen werden.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _AvailabilityGrid(
          days: days,
          persons: persons,
          celebratedId: celebratedId,
        ),
        if (celebrated != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.s,
              AppSpacing.m,
              0,
            ),
            child: Text(
              'Hajo, ${celebrated.name}! Nimmt diese Woche die meisten mit.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.m),
        for (final day in days) _DayRow(day: day, byId: byId),
      ],
    );
  }
}

/// Raster: eine Zeile je Person, eine Spalte je Wochentag. Alle sehen die
/// ganze Woche auf einen Blick — dafür ist ein Planer da.
class _AvailabilityGrid extends ConsumerWidget {
  const _AvailabilityGrid({
    required this.days,
    required this.persons,
    this.celebratedId,
  });

  final List<PlannedDay> days;
  final List<Person> persons;

  /// Wer diese Woche die meisten mitnimmt — `null`, wenn es niemanden gibt
  /// oder zwei gleichauf liegen.
  final String? celebratedId;

  /// Ein Tap schaltet weiter: kann nicht → dabei → nur eine Richtung →
  /// kann nicht. Dieselbe Abfolge wie die Kacheln im Fahrten-Editor, damit
  /// man sie nicht zweimal lernen muss.
  Future<void> _cycle(WidgetRef ref, PlannedDay day, String personId) async {
    final current = !day.availableIds.contains(personId)
        ? null
        : day.oneWayIds.contains(personId)
        ? PlanRide.oneWay
        : PlanRide.full;
    final next = switch (current) {
      null => PlanRide.full,
      PlanRide.full => PlanRide.oneWay,
      PlanRide.oneWay => null,
    };
    await ref
        .read(carpoolRepositoryProvider)
        .setAvailability(day.date, personId, next);
    ref.invalidate(weekPlanProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekday = DateFormat('E', 'de');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(flex: 3, child: SizedBox.shrink()),
                for (final day in days)
                  Expanded(
                    child: Center(
                      child: Text(
                        weekday.format(day.date),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: AppSpacing.m),
            for (final person in persons)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (person.id == celebratedId) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const MoodFace(
                            mood: Mood.celebrating,
                            size: 18,
                            semanticLabel:
                                'Hajo! Nimmt diese Woche die meisten mit',
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final day in days)
                    Expanded(
                      child: _Cell(
                        // Ein reines Icon-Raster sagt einem Screenreader
                        // nichts — erst die Beschriftung macht die Zelle
                        // unterscheidbar. Der Zustand gehört mit hinein:
                        // Bei drei Möglichkeiten reicht „angehakt" nicht.
                        label: '${person.name}, ${weekday.format(day.date)}',
                        available: day.availableIds.contains(person.id),
                        oneWay: day.oneWayIds.contains(person.id),
                        isDriver: day.driverId == person.id,
                        // Bereits eingetragene Tage sind Geschichte, keine
                        // Planung mehr.
                        enabled: !day.confirmed,
                        onTap: () => _cycle(ref, day, person.id),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.label,
    required this.available,
    required this.oneWay,
    required this.isDriver,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool available;
  final bool oneWay;
  final bool isDriver;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, state) = switch ((isDriver, available, oneWay)) {
      (true, _, _) => (Icons.directions_car, AppColors.driver, 'fährt'),
      // Halbvoller Pfeil: eine Richtung. Farbe wie im Fahrten-Editor, damit
      // 1-way überall gleich aussieht.
      (_, true, true) => (
        Icons.call_made,
        AppColors.oneWay,
        'nur eine Richtung',
      ),
      (_, true, false) => (Icons.check_circle, scheme.primary, 'dabei'),
      _ => (Icons.circle_outlined, scheme.outlineVariant, 'kann nicht'),
    };
    return Semantics(
      label: '$label, $state',
      enabled: enabled,
      button: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}

/// Je Tag: Vorschlag, Übersteuern, Bestätigen.
class _DayRow extends ConsumerWidget {
  const _DayRow({required this.day, required this.byId});

  final PlannedDay day;
  final Map<String, Person> byId;

  bool get _confirmable => canConfirmPlan(day.date, DateTime.now());

  Future<void> _pickDriver(BuildContext context, WidgetRef ref) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Wer fährt?'),
        children: [
          for (final id in day.availableIds)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, id),
              child: Text(byId[id]?.name ?? id),
            ),
          if (day.isOverridden)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Zurück zum Vorschlag'),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref
        .read(carpoolRepositoryProvider)
        .setPlanDriver(day.date, chosen.isEmpty ? null : chosen);
    ref.invalidate(weekPlanProvider);
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final driverId = day.driverId;
    if (driverId == null) return;
    final names = [
      for (final id in day.availableIds)
        day.oneWayIds.contains(id)
            ? '${byId[id]?.name ?? id} (1-way)'
            : byId[id]?.name ?? id,
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fahrt eintragen?'),
        content: Text(
          '${DateFormat('EEEE, d. MMMM', 'de').format(day.date)}\n\n'
          'Fahrer: ${byId[driverId]?.name ?? driverId}\n'
          'Dabei: ${names.join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eintragen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(carpoolRepositoryProvider).createTrip(day.date, {
      for (final id in day.availableIds)
        id: id == driverId
            ? ParticipationStatus.driver
            // Der geplante Status muss in die Fahrt übernommen werden, sonst
            // rechnet die Statistik 1-way als volle Mitfahrt.
            : day.oneWayIds.contains(id)
            ? ParticipationStatus.oneWay
            : ParticipationStatus.passenger,
    });
    ref
      ..invalidate(tripsProvider)
      ..invalidate(weekPlanProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = DateFormat('EEEE, d.M.', 'de').format(day.date);
    final driver = day.driverId == null ? null : byId[day.driverId];

    return ListTile(
      title: Text(label),
      subtitle: Text(switch ((day.confirmed, driver)) {
        (true, final d?) => 'Eingetragen · ${d.name} ist gefahren',
        (true, _) => 'Eingetragen',
        // Zwei verschiedene Gründe für „kein Fahrer": Entweder hat noch
        // niemand angetippt, oder es können alle nur eine Richtung — dann
        // stellt niemand ein Auto. „Noch niemand verfügbar" wäre im zweiten
        // Fall schlicht falsch und die Nutzerin sucht den Fehler bei sich.
        (false, null) when day.availableIds.isEmpty => 'Noch niemand verfügbar',
        (false, null) => 'Kein Fahrer möglich — alle nur eine Richtung',
        (false, final d?) =>
          day.isOverridden
              ? '${d.name} fährt · von Hand gesetzt'
              : '${d.name} fährt · Vorschlag',
      }),
      leading: Icon(
        day.confirmed ? Icons.check_circle : Icons.event_available_outlined,
        color: day.confirmed ? AppColors.driver : null,
      ),
      trailing: day.confirmed || driver == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Fahrer ändern',
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => _pickDriver(context, ref),
                ),
                FilledButton(
                  onPressed: _confirmable ? () => _confirm(context, ref) : null,
                  child: const Text('Eintragen'),
                ),
              ],
            ),
    );
  }
}
