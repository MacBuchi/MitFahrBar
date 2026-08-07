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
import '../../models/group_defaults.dart';
import '../../models/notification_prefs.dart';
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

  /// Die Abweichung, die an der Zelle von [personId] erscheint (#183):
  /// die seines Autos, und **nur am Fahrer**.
  ///
  /// Nicht am Mitfahrer — der sähe ein Glyph, das er nicht gesetzt hat und
  /// über das Menü seiner Zelle auch nicht erreicht (der Schirm bearbeitet
  /// dort SEIN Auto, also dasselbe, aber die Marke gehört zur Quelle). Und
  /// nicht für Verwaiste: Wer nicht fährt, dessen Zeile wirkt nicht.
  GroupDefaults? _cellDeviation(
    Map<DateTime, Map<String, GroupDefaults>> byDay,
    PlannedDay day,
    String personId,
  ) {
    if (!day.driverIds.contains(personId)) return null;
    final dev = byDay[day.date]?[personId];
    return dev == null || dev.isEmpty ? null : dev;
  }

  /// In welchem Auto [personId] an [day] sitzt, 1-basiert — oder `null`.
  ///
  /// **Erst ab zwei Autos.** Bei einem sitzen alle darin; eine Marke daran
  /// wäre Dekoration in einem Raster, das ohnehin dicht ist. Wer an dem Tag
  /// gar nicht mitfährt, bekommt ebenfalls keine.
  int? _carNumberOf(PlannedDay day, String personId) {
    if (day.cars.length < 2) return null;
    final index = carIndexOf(day, personId);
    return index == null ? null : index + 1;
  }

  /// Entscheidet zwischen „ein Klick trägt ein" und „Menü" (#183).
  ///
  /// Die Regel steht an der aufrufenden Stelle ausführlich; hier ist sie eine
  /// Zeile, damit sie nicht an zwei Orten verschieden gelesen werden kann.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    PlannedDay day,
    Person person, {
    required bool mine,
  }) {
    final entered = day.availableIds.contains(person.id);
    if (mine && !entered) return _cycle(context, ref, day, person.id);
    return _ask(context, ref, day, person);
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

    final picked = await showDialog<_MenuAction>(
      context: context,
      builder: (_) => _RidePickerDialog(
        person: person,
        date: day.date,
        current: current,
        // „Ich möchte fahren" nur, wenn es etwas zu ändern gibt: Wer schon
        // fährt, hat keinen Grund dafür — und an einem eingetragenen Tag ist
        // nichts mehr zu planen.
        canOfferDrive: !day.confirmed && !day.driverIds.contains(person.id),
        deviates: ref.read(weekPlanDefaultsProvider).value?[day.date] != null,
      ),
    );
    if (picked == null) return;

    if (!context.mounted) return;
    switch (picked) {
      case _PickRide(:final choice):
        try {
          await ref
              .read(weekPlanProvider.notifier)
              .setRide(day.date, person.id, choice.ride);
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Speichern fehlgeschlagen.')),
          );
        }
      case _WantToDrive():
        try {
          // **Wer fahren will, ist dabei — beide Richtungen.** Ohne diesen
          // Schritt verfällt der Pin in `planWeek` als tote Auswahl (das
          // Übersteuern wirkt nur auf Verfügbare, 1-way schließt Fahren
          // aus), und sichtbar passiert gar nichts — der gemeldete Fall
          // vom 07.08.: leere Zelle, „Ich möchte fahren", nichts.
          if (!day.availableIds.contains(person.id) ||
              day.oneWayIds.contains(person.id)) {
            await ref
                .read(weekPlanProvider.notifier)
                .setRide(day.date, person.id, PlanRide.full);
          }
          // **Ein Vorschlag wird ersetzt, eine Menschenentscheidung bekommt
          // Gesellschaft.** Steht der Tag auf Vorschlag, heißt der Tipp „ich
          // fahre statt dessen" — ein Auto. Ist er von Hand gesetzt, käme
          // ein Ersetzen einer stillen Löschung fremder Entscheidungen
          // gleich (Reise nach Jerusalem beim zweiten Freiwilligen);
          // stattdessen entsteht das zweite Auto — der Fall, für den es
          // die Zeiten je Auto gibt. Ohne Sitzprüfung wie jedes
          // Übersteuern; reichen die Plätze nicht, sagt es der Hinweis am
          // Tag. Zwei Solo-Fahrer sind dann ehrlich zwei Autos ohne
          // Mitfahrer — und zählen nichts (#61).
          await ref.read(weekPlanProvider.notifier).setDrivers(day.date, {
            if (day.isOverridden) ...day.driverIds,
            person.id,
          });
        } catch (_) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Speichern fehlgeschlagen.')),
          );
        }
      case _EditDay():
        await _editDay(context, ref, day, person.id);
    }
  }

  /// Abweichende Zeiten und Treffpunkt — für den Tag oder für EIN Auto (#183).
  ///
  /// Eigener Schirm statt dreier Felder im Auswahlmenü: Der häufige Weg ist
  /// „dabei" antippen, und drei Eingabefelder darüber machten genau den laut.
  ///
  /// **Ein Schirm mit Geltungsbereich, nicht zwei Einträge im Menü.** Sobald
  /// der Tag zwei Autos hat, steht oben ein Umschalter „Ganzer Tag / Auto N";
  /// das macht die Schichtung sichtbar, statt sie auf zwei Wege zu verteilen,
  /// zwischen denen man raten müsste.
  Future<void> _editDay(
    BuildContext context,
    WidgetRef ref,
    PlannedDay day,
    String personId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final date = day.date;
    final group =
        ref.read(groupDefaultsProvider).value ?? const GroupDefaults();
    // Nur, wenn es überhaupt etwas zu unterscheiden gibt: Bei einem Auto ist
    // „dieses Auto" dasselbe wie „der Tag", und zwei Wege zum selben Ziel
    // sind einer zu viel.
    final carIndex = day.cars.length < 2 ? null : carIndexOf(day, personId);
    final driverId = carIndex == null ? null : day.cars[carIndex].driverId;

    final result = await showDialog<_DefaultsEdit>(
      context: context,
      builder: (_) => _DayDefaultsDialog(
        date: date,
        group: group,
        day: ref.read(weekPlanDefaultsProvider).value?[date],
        car: driverId == null
            ? null
            : ref.read(weekCarDefaultsProvider).value?[date]?[driverId],
        carNumber: carIndex == null ? null : carIndex + 1,
      ),
    );
    if (result == null) return;

    try {
      final repository = ref.read(carpoolRepositoryProvider);
      if (result.forCar && driverId != null) {
        await repository.saveCarDefaults(date, driverId, result.defaults);
        // **Die Zeit zu setzen schreibt den Fahrer fest.** Der Vorschlag
        // kippt, sobald jemand seine Verfügbarkeit ändert — die Zeile hinge
        // dann an einer Person, die an dem Tag gar nicht mehr fährt. Fixiert
        // wird der GANZE Satz Fahrer des Tages: Wer nur einen festhielte,
        // ließe die Wahl der übrigen weiterlaufen, und die verschiebt auch
        // dieses Auto.
        await ref
            .read(weekPlanProvider.notifier)
            .setDrivers(date, day.driverIds.toSet());
        ref.invalidate(weekCarDefaultsProvider);
      } else {
        await repository.savePlanDefaults(date, result.defaults);
        ref.invalidate(weekPlanDefaultsProvider);
      }
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
    // Die Auto-Abweichungen der Woche (#183) — fürs Glyph am Fahrer.
    final carDeviations =
        ref.watch(weekCarDefaultsProvider).value ??
        const <DateTime, Map<String, GroupDefaults>>{};
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
              DecoratedBox(
                // Die eigene Zeile dezent unterlegen (#121-Nachtrag): Im
                // Raster sucht man zuerst sich selbst. Sehr blass, damit die
                // Zeilenstruktur nicht zerfällt — und aus der Markenfamilie,
                // nicht aus einer neuen Farbe.
                //
                // Ohne gewählte Person passiert gar nichts: Wer die
                // Startabfrage überspringt, sieht das Raster wie vorher.
                decoration: BoxDecoration(
                  color: me != null && person.id == me.id
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.s),
                ),
                child: Row(
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
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: me != null && person.id == me.id
                                        ? FontWeight.w600
                                        : null,
                                  ),
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
                          carNumber: _carNumberOf(day, person.id),
                          // Die Abweichung des eigenen Autos, NUR am Fahrer
                          // (#183): Sein Glyph war der ursprüngliche Wunsch —
                          // „auf den ersten Blick sehen". Tages-Abweichungen
                          // stehen an der Tageszeile; an jeder Zelle wären
                          // sie Rauschen, sie gelten ja allen.
                          deviation: _cellDeviation(
                            carDeviations,
                            day,
                            person.id,
                          ),
                          // Bereits eingetragene Tage sind Geschichte, keine
                          // Planung mehr.
                          enabled: !day.confirmed,
                          // **Ein Tap auf die leere eigene Zelle trägt ein,
                          // jeder andere öffnet das Menü** (#183).
                          //
                          // Der Alltagsfall — sich für einen Tag eintragen —
                          // bleibt damit ein Klick. Alles Weitere (nur eine
                          // Richtung, fahren wollen, abweichende Zeit) steht
                          // im Menü, statt den Zyklus auf vier Stufen zu
                          // verlängern; bei dreien war er schon lästig.
                          //
                          // Eine **fremde** Zelle öffnet das Menü auch dann,
                          // wenn sie leer ist: Sonst träfe ein Fehltipp
                          // jemand anderen mit einem Klick, und genau das
                          // verhindert die Rückfrage aus #121.
                          //
                          // Ohne gewählte Person zählt jede Zeile als eigene
                          // — nicht als fremde. Wer die Startabfrage
                          // übersprungen hat, hatte diese Bremse noch nie,
                          // und sie ihm jetzt zu geben hieße, ihn für das
                          // Überspringen zu bestrafen. Im Demo-Modus ist die
                          // Zuordnung ohnehin aus.
                          onTap: () => unawaited(
                            _open(
                              context,
                              ref,
                              day,
                              person,
                              mine: me == null || person.id == me.id,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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

/// Was aus dem Zell-Menü zurückkommt (#183).
///
/// Ein Ergebnistyp statt dreier Rückgabewege: Der Dialog entscheidet nur, der
/// Aufrufer führt aus. Ein Dialog, der selbst schreibt, müsste den Fehlerfall
/// ein zweites Mal beantworten.
sealed class _MenuAction {
  const _MenuAction();
}

class _PickRide extends _MenuAction {
  const _PickRide(this.choice);
  final _RideChoice choice;
}

class _WantToDrive extends _MenuAction {
  const _WantToDrive();
}

class _EditDay extends _MenuAction {
  const _EditDay();
}

/// Das Menü einer Zelle (#183, vorher die Rückfrage aus #121).
///
/// Es fragt nicht nur, es erledigt es gleich: Ein Tipp öffnet, ein zweiter
/// setzt. Eine reine Ja/Nein-Rückfrage hätte bei jedem Weiterschalten noch
/// einmal gefragt.
///
/// **Hier liegt alles außer dem Alltagsfall.** Sich eintragen ist ein Tap auf
/// die leere eigene Zelle; nur eine Richtung, fahren wollen und eine
/// abweichende Zeit stehen hier. Den Zyklus stattdessen zu verlängern hätte
/// den häufigen Weg für den seltenen bezahlt.
class _RidePickerDialog extends StatelessWidget {
  const _RidePickerDialog({
    required this.person,
    required this.date,
    required this.current,
    required this.canOfferDrive,
    required this.deviates,
  });

  final Person person;
  final DateTime date;
  final PlanRide? current;

  /// Ob „Ich möchte fahren" überhaupt etwas ändern würde.
  final bool canOfferDrive;

  /// Ob für diesen Tag schon eine Abweichung gespeichert ist — nur für den
  /// Wortlaut des Eintrags, die Werte holt der Editor selbst.
  final bool deviates;

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
              onTap: () => Navigator.of(context).pop(_PickRide(choice)),
            ),
          if (canOfferDrive)
            ListTile(
              leading: Icon(Icons.directions_car, color: scheme.primary),
              title: const Text('Ich möchte fahren'),
              onTap: () => Navigator.of(context).pop(const _WantToDrive()),
            ),
          const Divider(height: AppSpacing.s),
          ListTile(
            leading: Icon(Icons.schedule, color: scheme.onSurfaceVariant),
            title: const Text('Zeiten & Treffpunkt'),
            subtitle: Text(
              deviates ? 'weicht an diesem Tag ab' : 'gilt nur für diesen Tag',
            ),
            onTap: () => Navigator.of(context).pop(const _EditDay()),
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

/// Abweichende Zeiten und Treffpunkt für einen Tag (#183).
///
/// Was nicht gesetzt wird, bleibt bei der Vorgabe der Gruppe — deshalb zeigen
/// die Felder deren Werte als Platzhalter und nicht als Inhalt. Ein Feld zu
/// leeren heißt „wieder wie immer", nicht „gar keine Zeit": Aufgelöst wird
/// feldweise.
/// Was der Schirm zurückgibt: die Werte **und** wofür sie gelten.
class _DefaultsEdit {
  const _DefaultsEdit({required this.forCar, required this.defaults});

  final bool forCar;
  final GroupDefaults defaults;
}

class _DayDefaultsDialog extends StatefulWidget {
  const _DayDefaultsDialog({
    required this.date,
    required this.group,
    required this.day,
    required this.car,
    required this.carNumber,
  });

  final DateTime date;

  /// Die Vorgabe der Gruppe — nur zur Anzeige als Platzhalter.
  final GroupDefaults group;

  /// Die gespeicherte Abweichung dieses Tages, `null` wenn es keine gibt.
  final GroupDefaults? day;

  /// Die des eigenen Autos, `null` wenn es keine gibt.
  final GroupDefaults? car;

  /// Nummer des eigenen Autos — `null` heißt: Es gibt nichts zu
  /// unterscheiden, der Umschalter bleibt weg.
  final int? carNumber;

  @override
  State<_DayDefaultsDialog> createState() => _DayDefaultsDialogState();
}

class _DayDefaultsDialogState extends State<_DayDefaultsDialog> {
  /// Beginnt beim Auto, sobald es eines gibt: Wer bei zwei Autos die Zeit
  /// ändert, meint fast immer seines. Der ganze Tag ist einen Tipp entfernt.
  late bool _forCar = widget.carNumber != null;

  late DayTime? _out = _source?.outboundTime;
  late DayTime? _back = _source?.returnTime;
  late final TextEditingController _point = TextEditingController(
    text: _source?.meetingPoint ?? '',
  );

  GroupDefaults? get _source => _forCar ? widget.car : widget.day;

  /// Der Umschalter wechselt die BEARBEITETE Ebene, also auch die Werte im
  /// Formular — sonst schriebe man die Zeit des Tages versehentlich als die
  /// des Autos fort.
  void _switchScope(bool forCar) => setState(() {
    _forCar = forCar;
    _out = _source?.outboundTime;
    _back = _source?.returnTime;
    _point.text = _source?.meetingPoint ?? '';
  });

  @override
  void dispose() {
    _point.dispose();
    super.dispose();
  }

  /// Was gälte, wenn dieses Feld leer bliebe: die nächsttiefere Ebene.
  /// Beim Auto also der Tag, sonst die Gruppe — dieselbe Kette wie im
  /// Ausgangskorb, nur zur Anzeige.
  GroupDefaults get _fallback =>
      _forCar ? effectiveDefaults(widget.group, widget.day) : widget.group;

  Future<void> _pick(bool outbound) async {
    final start = outbound ? _out : _back;
    final fallback = outbound ? _fallback.outboundTime : _fallback.returnTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (start ?? fallback)?.hour ?? 7,
        minute: (start ?? fallback)?.minute ?? 30,
      ),
    );
    if (picked == null) return;
    setState(() {
      final value = DayTime(picked.hour, picked.minute);
      if (outbound) {
        _out = value;
      } else {
        _back = value;
      }
    });
  }

  String _hint(DayTime? own, DayTime? group) =>
      own?.format() ?? (group == null ? 'nicht gesetzt' : group.format());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(DateFormat('EEEE, d.M.', 'de').format(widget.date)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.carNumber case final number?) ...[
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(value: false, label: Text('Ganzer Tag')),
                ButtonSegment(value: true, label: Text('Auto $number')),
              ],
              selected: {_forCar},
              onSelectionChanged: (selection) => _switchScope(selection.single),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            _forCar
                ? 'Gilt nur für dein Auto an diesem Tag. Was hier leer '
                      'bleibt, kommt vom Tag — und sonst aus den festen '
                      'Vorgaben. Damit die Zeit nicht an einem anderen Auto '
                      'landet, wird der Fahrer des Tages festgehalten.'
                : 'Gilt für alle an diesem Tag. Was hier leer bleibt, kommt '
                      'weiter aus den festen Vorgaben.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s),
          for (final (label, own, group, outbound) in [
            ('Abfahrt hin', _out, _fallback.outboundTime, true),
            ('Abfahrt zurück', _back, _fallback.returnTime, false),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.schedule,
                color: own == null ? scheme.onSurfaceVariant : scheme.primary,
              ),
              title: Text(label),
              subtitle: Text(_hint(own, group)),
              trailing: own == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Wieder wie immer',
                      onPressed: () => setState(() {
                        if (outbound) {
                          _out = null;
                        } else {
                          _back = null;
                        }
                      }),
                    ),
              onTap: () => unawaited(_pick(outbound)),
            ),
          TextField(
            controller: _point,
            decoration: InputDecoration(
              labelText: 'Treffpunkt',
              hintText: _fallback.meetingPoint ?? 'wie immer',
            ),
            maxLength: 120,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final point = _point.text.trim();
            Navigator.of(context).pop(
              _DefaultsEdit(
                forCar: _forCar,
                defaults: GroupDefaults(
                  outboundTime: _out,
                  returnTime: _back,
                  meetingPoint: point.isEmpty ? null : point,
                ),
              ),
            );
          },
          child: const Text('Speichern'),
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
    this.carNumber,
    this.deviation,
  });

  final String label;
  final bool available;
  final bool oneWay;
  final bool isDriver;
  final bool enabled;
  final VoidCallback onTap;

  /// In welchem Auto diese Person an diesem Tag sitzt, 1-basiert (#183).
  ///
  /// `null` heißt: nicht zeigen. Das ist der Normalfall — bei EINEM Auto
  /// sitzen ohnehin alle darin, und eine Marke daran wäre reine Dekoration,
  /// die das ohnehin dichte Raster verstellt.
  final int? carNumber;

  /// Die Abweichung des eigenen Autos — nur am Fahrer gesetzt (#183).
  /// `null` heißt: nichts zu zeigen.
  final GroupDefaults? deviation;

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
    // Uhr, sobald eine Zeit abweicht; nur der Treffpunkt → Marker. Dieselbe
    // Regel wie am Tages-Titel, ein Glyph-Platz statt zweier.
    final dev = deviation;
    final devTime =
        dev != null && (dev.outboundTime != null || dev.returnTime != null);
    final devIcon = dev == null
        ? null
        : devTime
        ? Icons.schedule
        : Icons.place_outlined;
    // Alles gehört in die Vorlesung: „Anna, Mo, fährt" sagt weder, mit wem,
    // noch dass ihr Auto abweicht — und genau dafür gibt es die Marken.
    final spoken = [
      state,
      if (carNumber case final n?) 'Auto $n',
      if (devIcon != null) devTime ? 'andere Zeiten' : 'anderer Treffpunkt',
    ].join(', ');
    // Das Glyph erbt die Farbe seines Autos; bei einem Auto (keine Nummer)
    // bleibt es neutral — dort gibt es nichts zu unterscheiden.
    final devColor = carNumber == null
        ? scheme.onSurfaceVariant
        : AppCarTones.byIndex(
                carNumber! - 1,
                Theme.of(context).brightness,
              )?.surface ??
              scheme.onSurfaceVariant;
    return Semantics(
      label: enabled
          ? '$label, $spoken'
          : '$label, $spoken, bereits eingetragen',
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
            child: Center(
              child: carNumber == null && devIcon == null
                  ? Icon(icon, size: 20, color: color)
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(icon, size: 20, color: color),
                        if (carNumber case final n?)
                          Positioned(
                            right: -6,
                            bottom: -4,
                            child: _CarBadge(number: n),
                          ),
                        if (devIcon != null)
                          Positioned(
                            right: -7,
                            top: -5,
                            child: ExcludeSemantics(
                              child: Icon(devIcon, size: 11, color: devColor),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Auto-Marke an einer Zelle: Farbe **und** Nummer (#183).
///
/// Beides zusammen, nie eines allein — die Farbe für den Blick übers Raster,
/// die Nummer für alle, die sie nicht unterscheiden können, und für den
/// fünften Wagen, für den es keine Farbe mehr gibt.
class _CarBadge extends StatelessWidget {
  const _CarBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = AppCarTones.byIndex(number - 1, Theme.of(context).brightness);
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Jenseits der Palette ein neutraler Grund: Eine fünfte Farbe zu
        // erfinden hieße, sie ungemessen einzuführen.
        color: tone?.surface ?? scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      // Die Marke steht schon in der Zellen-Beschriftung; hier spräche der
      // Screenreader dieselbe Zahl ein zweites Mal.
      child: ExcludeSemantics(
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w700,
            color: tone?.foreground ?? scheme.onSurface,
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

  /// Zusatz am Tag, wenn jemand etwas angemerkt hat (#127).
  ///
  /// Hängt am `subtitle` und nicht am `trailing`: Dort stehen je nach Zustand
  /// schon bis zu zwei Knöpfe, und ein dritter müsste in alle fünf Zweige.
  /// Dasselbe Muster wie [_seatHint].
  static String _notesHint(int count) => switch (count) {
    0 => '',
    1 => ' · 1 Anmerkung',
    _ => ' · $count Anmerkungen',
  };

  /// Der Tag als ISO-Kalendertag für die Adresse `/notes/:date`.
  String get _isoDay =>
      '${day.date.year.toString().padLeft(4, '0')}-'
      '${day.date.month.toString().padLeft(2, '0')}-'
      '${day.date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = DateFormat('EEEE, d.M.', 'de').format(day.date);
    final joined = [
      for (final id in day.driverIds) byId[id]?.name ?? id,
    ].join(' + ');
    final notes = _notesHint(
      ref.watch(weekNotesProvider).value?[day.date]?.length ?? 0,
    );
    // Was an diesem Tag abweicht (#183) — im Text UND als Symbol. Ein Symbol
    // allein sagte „hier ist etwas anders", ohne zu sagen was; ein Text ohne
    // Symbol fiele im Raster nicht auf.
    //
    // Angezeigt wird das **Wirksame**, nicht die Ablage: Bei einem Auto ist
    // dessen Abweichung praktisch die des Tages und erscheint ohne
    // „Auto 1:"-Präfix; bei mehreren steht die Tageszeit vorn und jedes
    // abweichende Auto dahinter. **Verwaiste Auto-Zeilen erscheinen nicht**
    // — sie wirken beim Auflösen nicht, und eine Zeit anzuzeigen, zu der
    // niemand geweckt wird, wäre die Rückkehr des gemeldeten Fehlers mit
    // umgekehrtem Vorzeichen.
    final dayDeviation = ref.watch(weekPlanDefaultsProvider).value?[day.date];
    final carDeviations =
        ref.watch(weekCarDefaultsProvider).value?[day.date] ??
        const <String, GroupDefaults>{};
    String devText(GroupDefaults d) => [
      if (d.outboundTime case final t?) 'hin ${t.format()}',
      if (d.returnTime case final t?) 'zurück ${t.format()}',
      ?d.meetingPoint,
    ].join(', ');
    final effectiveDay = day.cars.length == 1
        ? effectiveDefaults(
            dayDeviation ?? const GroupDefaults(),
            carDeviations[day.cars.single.driverId],
          )
        : (dayDeviation ?? const GroupDefaults());
    final shownDeviations = <GroupDefaults>[
      if (!effectiveDay.isEmpty) effectiveDay,
      if (day.cars.length > 1)
        for (final car in day.cars)
          if (carDeviations[car.driverId] case final dev? when !dev.isEmpty)
            dev,
    ];
    final deviationHint = [
      if (!effectiveDay.isEmpty) devText(effectiveDay),
      if (day.cars.length > 1)
        for (final (i, car) in day.cars.indexed)
          if (carDeviations[car.driverId] case final dev? when !dev.isEmpty)
            'Auto ${i + 1}: ${devText(dev)}',
    ].join(' · ');
    // Uhr, sobald irgendwo eine Zeit abweicht; nur der Ort → Marker.
    final deviationIcon =
        shownDeviations.any(
          (d) => d.outboundTime != null || d.returnTime != null,
        )
        ? Icons.schedule
        : Icons.place_outlined;

    return ListTile(
      // Die Anmerkungen stehen JEDEM Tag offen, auch einem eingetragenen.
      // Das weicht die Sperre oben nicht auf: Sie schützt die Punkte vor
      // einer versehentlichen Planänderung, und eine Anmerkung berührt sie
      // nicht.
      onTap: () => unawaited(context.push('/notes/$_isoDay')),
      title: deviationHint.isEmpty
          ? Text(label)
          : Row(
              children: [
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  deviationIcon,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: deviationIcon == Icons.schedule
                      ? 'Abweichende Zeiten'
                      : 'Abweichender Treffpunkt',
                ),
              ],
            ),
      subtitle: Text(
        '${switch ((day.confirmed, day.cars.length)) {
          (true, 0) => 'Eingetragen',
          (true, 1) => 'Eingetragen · $joined ist gefahren',
          (true, _) => 'Eingetragen · $joined sind gefahren',
          // Zwei verschiedene Gründe für „kein Fahrer": Entweder hat noch
          // niemand angetippt, oder es können alle nur eine Richtung — dann
          // stellt niemand ein Auto. „Noch niemand verfügbar" wäre im zweiten
          // Fall schlicht falsch und die Nutzerin sucht den Fehler bei sich.
          (false, 0) when day.availableIds.isEmpty => 'Noch niemand verfügbar',
          (false, 0) => 'Kein Fahrer möglich — alle nur eine Richtung',
          (false, 1) => '$joined fährt · '
              '${day.isOverridden ? 'von Hand gesetzt' : 'Vorschlag'}'
              // Der Planer bevorzugt Autos mit genug Plätzen; reicht es an
              // dem Tag trotzdem nicht, sagt er das, statt still zu wenige
              // Sitze vorzuschlagen.
              '${_seatHint()}',
          (false, final k) => '$joined fahren · $k Autos · '
              '${day.isOverridden ? 'von Hand gesetzt' : 'Vorschlag'}'
              '${_seatHint()}',
        }}$notes'
        '${deviationHint.isEmpty ? '' : ' · $deviationHint'}',
      ),
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
