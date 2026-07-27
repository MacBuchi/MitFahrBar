/// plan_screen.dart – Wochenplaner: wer kann wann, wer fährt.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/balance_label.dart';
import '../../core/fairness.dart';
import '../../core/mood.dart';
import '../../core/tokens.dart';
import '../../core/widgets/mood_face.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';
import '../../models/person.dart';
import '../../models/plan_ride.dart';
import '../../models/trip.dart';
import '../trip_editor/trip_editor_seed.dart';

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
    // 1-way wiegt im Hajo wie in den Punkten (Issue #59) — der Faktor kommt
    // aus den Gruppen-Settings; bis sie geladen sind, gilt die Vorgabe.
    final oneWayFactor = ref
        .watch(settingsProvider)
        .maybeWhen(data: (s) => s.oneWayFactor, orElse: () => null);
    final celebratedIds = celebratedDrivers(
      days,
      oneWayFactor: oneWayFactor ?? const AppSettings().oneWayFactor,
    );
    final celebratedNames = [
      for (final p in persons)
        if (celebratedIds.contains(p.id)) p.name,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Text(
            // Punkte zuerst (Issue #38), dazu der begrenzte
            // Fahrraten-Ausgleich aus `suggestPlanDriver` — der Text soll
            // beides sagen, sonst wundert man sich über den Vorschlag.
            'Tippt an, wann ihr könnt. MitFahrBar schlägt daraufhin vor, wer '
            'an welchem Tag fährt — nach den Punkten, die ganze Woche '
            'vorausgedacht. Steht es fast gleich, bekommt, wer selten '
            'fährt, eher die kleinen Tage und, wer oft fährt, die vollen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _AvailabilityGrid(
          days: days,
          persons: persons,
          celebratedIds: celebratedIds,
        ),
        if (celebratedNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.s,
              AppSpacing.m,
              0,
            ),
            child: Text(
              celebratedNames.length == 1
                  ? 'Hajo, ${celebratedNames.single}! '
                        'Das vollste Auto der Woche.'
                  : 'Hajo, ${celebratedNames.join(' & ')}! '
                        'Die vollsten Autos der Woche.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        _WeekDeltas(days: days, persons: persons),
        const SizedBox(height: AppSpacing.m),
        for (final day in days) _DayRow(day: day, byId: byId),
      ],
    );
  }
}

/// Was die geplante Woche ändern würde — je Person als Punktediff oder als
/// Fahrraten-Änderung in Promille, umschaltbar (Issue #60). Reine Vorschau
/// aus [statsWithPlannedWeek]: berechnet, nie gespeichert.
class _WeekDeltas extends ConsumerStatefulWidget {
  const _WeekDeltas({required this.days, required this.persons});

  final List<PlannedDay> days;
  final List<Person> persons;

  @override
  ConsumerState<_WeekDeltas> createState() => _WeekDeltasState();
}

class _WeekDeltasState extends ConsumerState<_WeekDeltas> {
  bool _showRate = false;

  @override
  Widget build(BuildContext context) {
    final trips = ref.watch(tripsProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (trips == null || settings == null) return const SizedBox.shrink();

    final before = computeStats(trips, settings);
    final after = statsWithPlannedWeek(widget.days, trips, settings);

    final entries = <(String, String)>[];
    for (final person in widget.persons) {
      final b = before[person.id];
      final a = after[person.id];
      final pointsDelta = (a?.points ?? 0) - (b?.points ?? 0);
      final rateDelta = (a?.driveShare ?? 0) - (b?.driveShare ?? 0);
      // Wen die Woche gar nicht berührt, den zeigt die Zeile auch nicht.
      if (pointsDelta.abs() < 0.05 && rateDelta.abs() < 0.0005) continue;
      final format = NumberFormat('0.#', 'de');
      entries.add((
        person.name,
        _showRate
            ? signedPerMille(rateDelta)
            : signedPoints(pointsDelta, format),
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Was diese Woche ändert:',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Punkte')),
                  ButtonSegment(value: true, label: Text('Fahrrate')),
                ],
                selected: {_showRate},
                onSelectionChanged: (selection) =>
                    setState(() => _showRate = selection.single),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (name, delta) in entries)
                Text(
                  '$name $delta',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Raster: eine Zeile je Person, eine Spalte je Wochentag. Alle sehen die
/// ganze Woche auf einen Blick — dafür ist ein Planer da.
class _AvailabilityGrid extends ConsumerWidget {
  const _AvailabilityGrid({
    required this.days,
    required this.persons,
    this.celebratedIds = const {},
  });

  final List<PlannedDay> days;
  final List<Person> persons;

  /// Wer das vollste Auto der Woche fährt — bei Gleichstand mehrere.
  final Set<String> celebratedIds;

  /// Ein Tap schaltet weiter: kann nicht → dabei → nur eine Richtung →
  /// kann nicht. Dieselbe Abfolge wie die Kacheln im Fahrten-Editor, damit
  /// man sie nicht zweimal lernen muss.
  ///
  /// Der Notifier zeigt die Änderung sofort und schreibt im Hintergrund —
  /// hier wird nur noch der Fehlerfall gemeldet.
  Future<void> _cycle(
    BuildContext context,
    WidgetRef ref,
    PlannedDay day,
    String personId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(weekPlanProvider.notifier).cycleRide(day.date, personId);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Speichern fehlgeschlagen.')),
      );
    }
  }

  /// Bei einer fremden Zeile wird gefragt, statt weiterzuschalten (#121).
  ///
  /// **Eine Vertipper-Bremse, keine Sperre**: Wer bewusst für jemand anderen
  /// einträgt — Pärchen tun das —, kommt in zwei Tipps durch, oft schneller
  /// als das Durchschalten der eigenen Zeile. Wer daraus je ein „geht nicht"
  /// macht, nimmt der Gruppe genau den Fall, für den sie das wollte.
  Future<void> _ask(
    BuildContext context,
    WidgetRef ref,
    PlannedDay day,
    Person person,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = !day.availableIds.contains(person.id)
        ? null
        : day.oneWayIds.contains(person.id)
        ? PlanRide.oneWay
        : PlanRide.full;

    final picked = await showDialog<_RideChoice>(
      context: context,
      builder: (_) =>
          _RidePickerDialog(person: person, date: day.date, current: current),
    );
    if (picked == null) return;

    try {
      await ref
          .read(weekPlanProvider.notifier)
          .setRide(day.date, person.id, picked.ride);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Speichern fehlgeschlagen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekday = DateFormat('E', 'de');
    // Aktueller Stand aus echten Fahrten (ohne Simulation der Woche): Die
    // kleine Zahl vor dem Namen macht den Vorschlag nachvollziehbar — wer
    // im Minus steht, ist als Nächstes dran (zugesagt in Issue #38).
    final stats = ref.watch(statsProvider).value;
    final pointsFormat = NumberFormat('#,##0.#', 'de');
    // Wer an diesem Gerät sitzt (#121) — `null`, solange niemand gewählt ist.
    final me = ref.watch(myPersonProvider);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  // Kalenderwoche und Zeitraum zur Orientierung (#84) — die
                  // Spaltenköpfe sagen nur „Mo–Fr", nicht welche Woche.
                  child: days.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          'KW ${isoWeekNumber(days.first.date)}\n'
                          '${DateFormat('d.M.', 'de').format(days.first.date)}'
                          ' – '
                          '${DateFormat('d.M.', 'de').format(days.last.date)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                ),
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
                        if (stats != null) ...[
                          SizedBox(
                            // Feste Breite, rechtsbündig: Die Zahlen stehen
                            // wie in einer Tabelle, die Namen fluchten.
                            width: 34,
                            child: Text(
                              signedPoints(
                                stats[person.id]?.points ?? 0,
                                pointsFormat,
                              ),
                              textAlign: TextAlign.right,
                              // Der Screenreader liest die Richtung, nicht
                              // das Vorzeichen: „schuldet 2" statt „minus 2".
                              semanticsLabel: balanceLabel(
                                stats[person.id]?.points ?? 0,
                                pointsFormat,
                              ),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                        ],
                        Flexible(
                          child: Text(
                            person.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (celebratedIds.contains(person.id)) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const MoodFace(
                            mood: Mood.celebrating,
                            size: 18,
                            semanticLabel:
                                'Hajo! Fährt das vollste Auto der Woche',
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
                        // Ein Tag kann mehrere Autos haben (Issue #62) —
                        // jeder Fahrer bekommt sein Auto-Symbol.
                        isDriver: day.driverIds.contains(person.id),
                        // Bereits eingetragene Tage sind Geschichte, keine
                        // Planung mehr.
                        enabled: !day.confirmed,
                        // Die eigene Zeile schaltet weiter wie immer; bei
                        // einer fremden wird gefragt (#121). Ohne gewählte
                        // Person bleibt alles wie vorher — wer die
                        // Startabfrage überspringt, soll nicht schlechter
                        // dastehen als vor dem Release.
                        onTap: () => unawaited(
                          me == null || person.id == me.id
                              ? _cycle(context, ref, day, person.id)
                              : _ask(context, ref, day, person),
                        ),
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

/// Die drei Zustände einer Zelle, wie sie `_Cell` zeichnet — Wortlaut, Symbol
/// und Farbe an EINER Stelle. Zwei Stellen, die dasselbe verschieden benennen,
/// sind eine zu viel.
enum _RideChoice {
  full(PlanRide.full, 'dabei', Icons.check_circle),
  oneWay(PlanRide.oneWay, 'nur eine Richtung', Icons.call_made),
  none(null, 'kann nicht', Icons.circle_outlined);

  const _RideChoice(this.ride, this.label, this.icon);

  final PlanRide? ride;
  final String label;
  final IconData icon;

  Color color(ColorScheme scheme) => switch (this) {
    _RideChoice.full => scheme.primary,
    _RideChoice.oneWay => AppColors.oneWay,
    _RideChoice.none => scheme.outlineVariant,
  };
}

/// „Für jemand anderen eintragen?" — die Rückfrage aus #121.
///
/// Sie fragt nicht nur, sie erledigt es gleich: Ein Tipp öffnet, ein zweiter
/// setzt. Eine reine Ja/Nein-Rückfrage hätte bei jedem Weiterschalten noch
/// einmal gefragt.
class _RidePickerDialog extends StatelessWidget {
  const _RidePickerDialog({
    required this.person,
    required this.date,
    required this.current,
  });

  final Person person;
  final DateTime date;
  final PlanRide? current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        '${person.name} · ${DateFormat('EEEE, d.M.', 'de').format(date)}',
      ),
      contentPadding: const EdgeInsets.only(top: AppSpacing.s),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in _RideChoice.values)
            ListTile(
              leading: Icon(choice.icon, color: choice.color(scheme)),
              title: Text(choice.label),
              selected: choice.ride == current,
              trailing: choice.ride == current
                  ? Icon(Icons.done, color: scheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(choice),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
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
      label: enabled ? '$label, $state' : '$label, $state, bereits eingetragen',
      enabled: enabled,
      button: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.s),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          // Eingetragene Tage sind Geschichte: blass statt anfassbar, damit
          // niemand hier versehentlich an einer gefahrenen Fahrt dreht.
          child: Opacity(
            opacity: enabled ? 1 : 0.38,
            child: Center(child: Icon(icon, size: 20, color: color)),
          ),
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

  // Über nowProvider statt DateTime.now(): Am Wochenende zeigt der Planer
  // die kommende Woche, deren Tage (noch) nicht bestätigbar sind — Tests
  // stellen die Uhr fest, sonst prüfen sie samstags etwas anderes.
  bool _confirmable(WidgetRef ref) =>
      canConfirmPlan(day.date, ref.read(nowProvider)());

  Future<void> _pickDrivers(BuildContext context, WidgetRef ref) async {
    // 1-way-Personen stellen kein Auto — sie stehen gar nicht erst zur Wahl.
    // (Bisher standen sie im Dialog und die Auswahl verfiel still in
    // planWeek — eine Falle, die mit dem Mehrfach-Wählen verschwindet.)
    final candidates = [
      for (final id in day.availableIds)
        if (!day.oneWayIds.contains(id)) id,
    ];
    final selected = {...day.driverIds};
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final seatSum = selected.fold(
            0,
            (sum, id) => sum + (byId[id]?.seats ?? defaultSeats),
          );
          final headcount = day.availableIds.length;
          return AlertDialog(
            title: const Text('Wer fährt?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final id in candidates)
                  CheckboxListTile(
                    value: selected.contains(id),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
                      }
                    }),
                    title: Text(byId[id]?.name ?? id),
                    subtitle: Text('${byId[id]?.seats ?? defaultSeats} Plätze'),
                  ),
                const SizedBox(height: AppSpacing.s),
                // Live-Rechnung statt Sperre: Zu klein wählen bleibt
                // erlaubt — eine Menschenentscheidung, wie bisher beim
                // einzelnen Fahrer.
                Text(
                  selected.isEmpty
                      ? 'Noch niemand gewählt.'
                      : seatSum >= headcount
                      ? 'Reicht für alle $headcount.'
                      : 'Reicht für $seatSum von $headcount.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              if (day.isOverridden)
                TextButton(
                  onPressed: () => Navigator.pop(context, const <String>{}),
                  child: const Text('Zurück zum Vorschlag'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected),
                child: const Text('Übernehmen'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || !context.mounted) return;
    // Optimistisch über den Notifier — die Zeile springt sofort um.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(weekPlanProvider.notifier).setDrivers(day.date, chosen);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Speichern fehlgeschlagen.')),
      );
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    // Ein-Auto-Tag: Ein-Tipp-Eintrag wie immer. Mehr-Auto-Tage laufen über
    // [_confirmSplit].
    if (day.cars.length != 1) return;
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

  /// Eintragen am Mehr-Auto-Tag (Issue #62): Der Fahrten-Editor öffnet sich
  /// für jedes Auto nacheinander, fertig vorbelegt — gebucht wird erst mit
  /// jedem Speichern, nie still im Hintergrund.
  Future<void> _confirmSplit(BuildContext context, WidgetRef ref) async {
    // Die Autos VOR dem ersten Editor einfrieren und nie neu ableiten:
    // Sobald Auto 1 gespeichert ist, gilt der Tag als bestätigt, und
    // `day.cars` beschreibt die echte Fahrt statt der noch offenen Autos.
    final cars = List.of(day.cars);
    final date = day.date;
    final names = [
      for (final car in cars) byId[car.driverId]?.name ?? car.driverId,
    ].join(' + ');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${cars.length} Fahrten eintragen?'),
        content: Text(
          '${DateFormat('EEEE, d. MMMM', 'de').format(date)}\n\n'
          'An diesem Tag fahren ${cars.length} Autos ($names). MitFahrBar '
          'öffnet den Editor für jedes Auto nacheinander, fertig vorbelegt '
          '— gebucht wird erst mit jedem Speichern, nichts ohne euch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Los geht's"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // Kalibriert die „Weitere Fahrt?"-Rückfrage des Editors: So viele
    // Fahrten gibt es am Tag schon, bevor das jeweilige Auto aufgeht.
    var expected = (ref.read(tripsProvider).value ?? const <Trip>[])
        .where((t) => _sameDay(t.date, date))
        .length;

    for (final (i, car) in cars.indexed) {
      if (!context.mounted) return;
      final saved = await context.push<bool>(
        '/trip/new',
        extra: TripEditorSeed(
          date: date,
          // `PlannedCar.fullIds` sind die Mitfahrer OHNE Fahrer — der Editor
          // führt den Fahrer dagegen als vollen Teilnehmer.
          fullIds: {car.driverId, ...car.fullIds},
          oneWayIds: {...car.oneWayIds},
          driverId: car.driverId,
          carNumber: i + 1,
          carCount: cars.length,
          expectedSameDayTrips: expected,
        ),
      );
      // Abbruch heißt: Der Rest bleibt bewusst ungebucht. Der Tag steht
      // dann ehrlich mit den Fahrten da, die es gibt — das fehlende Auto
      // wird von Hand nachgetragen (so erklärt es auch die Hilfe).
      if (saved != true) return;
      expected += 1;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Zusatz am Tag, wenn die Autos der Fahrer zusammen nicht für alle
  /// reichen. Leer, solange es passt — bei einem Auto wortgleich wie früher.
  String _seatHint() {
    if (day.cars.isEmpty) return '';
    final sum = day.cars.fold(
      0,
      (total, car) => total + (byId[car.driverId]?.seats ?? defaultSeats),
    );
    if (day.availableIds.length <= sum) return '';
    return ' · nur $sum Plätze für ${day.availableIds.length}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = DateFormat('EEEE, d.M.', 'de').format(day.date);
    final joined = [
      for (final id in day.driverIds) byId[id]?.name ?? id,
    ].join(' + ');

    return ListTile(
      title: Text(label),
      subtitle: Text(switch ((day.confirmed, day.cars.length)) {
        (true, 0) => 'Eingetragen',
        (true, 1) => 'Eingetragen · $joined ist gefahren',
        (true, _) => 'Eingetragen · $joined sind gefahren',
        // Zwei verschiedene Gründe für „kein Fahrer": Entweder hat noch
        // niemand angetippt, oder es können alle nur eine Richtung — dann
        // stellt niemand ein Auto. „Noch niemand verfügbar" wäre im zweiten
        // Fall schlicht falsch und die Nutzerin sucht den Fehler bei sich.
        (false, 0) when day.availableIds.isEmpty => 'Noch niemand verfügbar',
        (false, 0) => 'Kein Fahrer möglich — alle nur eine Richtung',
        (false, 1) =>
          '$joined fährt · '
              '${day.isOverridden ? 'von Hand gesetzt' : 'Vorschlag'}'
              // Der Planer bevorzugt Autos mit genug Plätzen; reicht es an
              // dem Tag trotzdem nicht, sagt er das, statt still zu wenige
              // Sitze vorzuschlagen.
              '${_seatHint()}',
        (false, final k) =>
          '$joined fahren · $k Autos · '
              '${day.isOverridden ? 'von Hand gesetzt' : 'Vorschlag'}'
              '${_seatHint()}',
      }),
      leading: Icon(
        day.confirmed ? Icons.check_circle : Icons.event_available_outlined,
        color: day.confirmed ? AppColors.driver : null,
      ),
      trailing: switch ((day.confirmed, day.cars)) {
        (true, []) => null,
        // Eingetragen: kein „Eintragen" mehr, sondern der Weg zum Bearbeiten
        // — deutlich anders eingefärbt, damit man die beiden Zustände nicht
        // verwechselt und nicht aus Gewohnheit weiterklickt.
        (true, [final only]) => OutlinedButton.icon(
          onPressed: () => unawaited(context.push('/trip/${only.tripId}')),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Bearbeiten'),
        ),
        // Mehrere Fahrten am Tag: erst wählen, welche — ein Knopf, der
        // stillschweigend irgendeine öffnet, wäre eine Falle.
        (true, final cars) => PopupMenuButton<String>(
          tooltip: 'Fahrt zum Bearbeiten wählen',
          icon: const Icon(Icons.edit_outlined),
          onSelected: (tripId) => unawaited(context.push('/trip/$tripId')),
          itemBuilder: (context) => [
            for (final (i, car) in cars.indexed)
              if (car.tripId case final tripId?)
                PopupMenuItem(
                  value: tripId,
                  child: Text(
                    'Auto ${i + 1} · ${byId[car.driverId]?.name ?? ''}',
                  ),
                ),
          ],
        ),
        (false, []) => null,
        (false, final cars) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Fahrer ändern',
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => _pickDrivers(context, ref),
            ),
            FilledButton(
              onPressed: !_confirmable(ref)
                  ? null
                  : cars.length == 1
                  ? () => _confirm(context, ref)
                  : () => _confirmSplit(context, ref),
              child: const Text('Eintragen'),
            ),
          ],
        ),
      },
    );
  }
}
