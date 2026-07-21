/// fairness.dart – Punkte-/Statistikberechnung und Fahrer-Vorschlag.
///
/// Punktesystem (identisch zur Excel-Vorlage):
///   Punkte = Σ mitgenommen (an eigenen Fahrtagen)
///            − eigene Mitfahrten − OneWayFaktor × eigene 1-way-Fahrten.
/// „Wer ist dran" kombiniert Punkte-Rang und Fahranteil-Rang unter den
/// an einem Tag Anwesenden (siehe KONZEPT.md 3.2).
library;

import 'dart:math' as math;

import '../models/app_settings.dart';
import '../models/plan_ride.dart';
import '../models/person.dart';
import '../models/trip.dart';

class PersonStats {
  const PersonStats({
    required this.personId,
    required this.driven,
    required this.ridden,
    required this.oneWay,
    required this.carried,
    required this.points,
    this.lastDrive,
    this.lastParticipation,
  });

  final String personId;

  /// Anzahl Tage selbst gefahren.
  final int driven;

  /// Anzahl Tage voll mitgefahren.
  final int ridden;

  /// Anzahl Tage nur eine Richtung mitgefahren.
  final int oneWay;

  /// Σ mitgenommen an eigenen Fahrtagen (Mitfahrer + Faktor × 1-way).
  final double carried;

  final double points;

  /// Letzter Tag, an dem diese Person selbst gefahren ist.
  final DateTime? lastDrive;

  /// Letzter Tag, an dem diese Person überhaupt dabei war — egal in welcher
  /// Rolle. Bewusst getrennt von [lastDrive]: Wer oft mitfährt, aber nie
  /// fährt, ist ein Stammgast und trotzdem ohne [lastDrive].
  final DateTime? lastParticipation;

  int get participationDays => driven + ridden + oneWay;

  /// War die Person in den letzten [days] Tagen vor [reference] dabei?
  /// Grundlage für die Reihenfolge im Fahrten-Editor: Stammgäste zuerst.
  bool participatedRecently(DateTime reference, {int days = 60}) {
    final last = lastParticipation;
    if (last == null) return false;
    return !last.isBefore(reference.subtract(Duration(days: days)));
  }

  /// Wie oft gefahren, relativ zur eigenen Anwesenheit (0..1).
  double get driveShare =>
      participationDays == 0 ? 0 : driven / participationDays;

  /// Ø mitgenommene Personen pro eigener Fahrt (Excel-„Quote").
  double? get quote => driven == 0 ? null : carried / driven;

  double kilometers(AppSettings s) => participationDays * s.commuteKm * 2;

  /// Gesparte Kraftstoffkosten: eigene Fahrzeugkosten für die Tage,
  /// an denen man mitgefahren ist statt selbst zu fahren.
  double savedCosts(AppSettings s, Person person) {
    final consumption = person.consumptionPer100km;
    final energy = person.energyType;
    if (consumption == null || energy == null) return 0;
    final pricePerUnit = switch (energy) {
      EnergyType.electric => s.electricityPricePerKwh,
      EnergyType.diesel => s.dieselPricePerLiter,
      EnergyType.petrol => s.petrolPricePerLiter,
    };
    final costPer100km = consumption * pricePerUnit;
    return costPer100km * (ridden + oneWay) * s.commuteKm * 2 / 100;
  }
}

/// „Mitgenommen" einer einzelnen Fahrt: volle Mitfahrer + Faktor × 1-way.
double carriedOfTrip(Trip trip, AppSettings settings) {
  var carried = 0.0;
  for (final status in trip.participations.values) {
    carried += switch (status) {
      ParticipationStatus.driver => 0,
      ParticipationStatus.passenger => 1,
      ParticipationStatus.oneWay => settings.oneWayFactor,
    };
  }
  return carried;
}

/// Statistik für alle Personen, die in [trips] vorkommen.
Map<String, PersonStats> computeStats(List<Trip> trips, AppSettings settings) {
  final driven = <String, int>{};
  final ridden = <String, int>{};
  final oneWay = <String, int>{};
  final carried = <String, double>{};
  final lastDrive = <String, DateTime>{};
  final lastParticipation = <String, DateTime>{};

  for (final trip in trips) {
    final tripCarried = carriedOfTrip(trip, settings);
    for (final entry in trip.participations.entries) {
      final id = entry.key;
      final seen = lastParticipation[id];
      if (seen == null || trip.date.isAfter(seen)) {
        lastParticipation[id] = trip.date;
      }
      switch (entry.value) {
        case ParticipationStatus.driver:
          driven[id] = (driven[id] ?? 0) + 1;
          carried[id] = (carried[id] ?? 0) + tripCarried;
          final prev = lastDrive[id];
          if (prev == null || trip.date.isAfter(prev)) {
            lastDrive[id] = trip.date;
          }
        case ParticipationStatus.passenger:
          ridden[id] = (ridden[id] ?? 0) + 1;
        case ParticipationStatus.oneWay:
          oneWay[id] = (oneWay[id] ?? 0) + 1;
      }
    }
  }

  final ids = {...driven.keys, ...ridden.keys, ...oneWay.keys};
  return {
    for (final id in ids)
      id: PersonStats(
        personId: id,
        driven: driven[id] ?? 0,
        ridden: ridden[id] ?? 0,
        oneWay: oneWay[id] ?? 0,
        carried: carried[id] ?? 0,
        points:
            (carried[id] ?? 0) -
            (ridden[id] ?? 0) -
            settings.oneWayFactor * (oneWay[id] ?? 0),
        lastDrive: lastDrive[id],
        lastParticipation: lastParticipation[id],
      ),
  };
}

class RankedCandidate {
  const RankedCandidate({
    required this.personId,
    required this.score,
    required this.pointsRank,
    required this.shareRank,
    required this.stats,
  });

  final String personId;
  final double score;
  final int pointsRank;
  final int shareRank;
  final PersonStats stats;
}

/// Fairness-Ranking unter den [presentIds] (heute Anwesende).
///
/// Rang 1 in beiden Teilrängen = „am ehesten dran". Kombinierter Score =
/// pointsWeight × Punkte-Rang + (1 − pointsWeight) × Fahranteil-Rang.
/// Gleichstand: Wessen letzte Fahrt am längsten her ist (nie gefahren
/// zuerst), dann alphabetisch nach personId für Determinismus.
///
/// **`pointsWeight` steht seit 2026-07-21 auf 1.0** — es zählen allein die
/// Punkte (Issue #38). Der Fahranteil wird weiter berechnet und als
/// [RankedCandidate.shareRank] mitgeliefert, weil die Startseite ihn anzeigt;
/// auf die Reihenfolge wirkt er beim Standardgewicht nicht mehr.
///
/// Das kehrt die ursprüngliche Begründung aus KONZEPT.md 3.2 um: Punkte
/// messen, *wie viel* jemand transportiert hat, nicht *wie oft* er gefahren
/// ist. Wer selten, aber mit vollem Auto fährt, sammelt ein Polster und
/// rutscht dadurch dauerhaft nach hinten. Das ist die bewusst getragene
/// Folge der Entscheidung, kein Versehen — mit `pointsWeight` zurückdrehbar,
/// ohne diese Funktion anzufassen.
List<RankedCandidate> rankPresent(
  Iterable<String> presentIds,
  Map<String, PersonStats> stats,
  AppSettings settings,
) {
  final ids = presentIds.toList();
  if (ids.isEmpty) return const [];

  PersonStats of(String id) =>
      stats[id] ??
      PersonStats(
        personId: id,
        driven: 0,
        ridden: 0,
        oneWay: 0,
        carried: 0,
        points: 0,
      );

  // Competition-Ranking: Rang = 1 + Anzahl strikt kleinerer Werte.
  int rankOf(String id, double Function(PersonStats) metric) {
    final own = metric(of(id));
    return 1 + ids.where((other) => metric(of(other)) < own).length;
  }

  final candidates = [
    for (final id in ids)
      RankedCandidate(
        personId: id,
        pointsRank: rankOf(id, (s) => s.points),
        shareRank: rankOf(id, (s) => s.driveShare),
        score:
            settings.pointsWeight * rankOf(id, (s) => s.points) +
            (1 - settings.pointsWeight) * rankOf(id, (s) => s.driveShare),
        stats: of(id),
      ),
  ];

  candidates.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    if (byScore != 0) return byScore;
    final aLast = a.stats.lastDrive;
    final bLast = b.stats.lastDrive;
    if (aLast == null && bLast != null) return -1;
    if (aLast != null && bLast == null) return 1;
    if (aLast != null && bLast != null) {
      final byLast = aLast.compareTo(bLast);
      if (byLast != 0) return byLast;
    }
    return a.personId.compareTo(b.personId);
  });
  return candidates;
}

/// Vorgeschlagener Fahrer unter den Anwesenden (null bei leerer Auswahl).
String? suggestDriver(
  Iterable<String> presentIds,
  Map<String, PersonStats> stats,
  AppSettings settings,
) => rankPresent(presentIds, stats, settings).firstOrNull?.personId;

/// Verstärkung des Fahrraten-Trims im Wochenvorschlag — und zugleich seine
/// **Autoritätsgrenze**: Zwei Kandidaten können höchstens
/// `kRateBalance · Δ-Fahrrate · |dayFactor|` Punkte überbrücken, also nie
/// mehr als 2 (Raten liegen in 0..1). Jenseits dieses Bandes entscheiden
/// exakt die Punkte — die Grenze steckt in der Verstärkung selbst, nicht in
/// einer Sonderklausel (entschieden 2026-07-22, „bis ±2 Punkte").
const kRateBalance = 2.0;

/// Fahrer-Auswahl für einen **Plan-Tag**: Punkte zuerst, dazu ein begrenzter
/// Fahrraten-Trim (nur hier — Dashboard und Fahrten-Editor bleiben bei
/// [suggestDriver]).
///
/// Das Muster ist eine Kaskadenregelung mit begrenzter Autorität: Der
/// schnelle innere Kreis sind die Punkte („wer am wenigsten hat, ist dran"),
/// der langsame äußere die Fahrrate. Sie trimmt als reiner P-Regler den
/// wirksamen Punktestand:
///
///   wirksam = Punkte − kRateBalance · (Fahrrate − Ø-Rate des Pools) · dayFactor
///
/// [dayFactor] ∈ [−1, 1] ist die normierte Tagesgröße (−1 = kleinster Tag
/// der Woche, +1 = vollster, 0 = Durchschnitt oder alle gleich). Wenigfahrer
/// (Rate unter Ø) werden so an kleinen Tagen günstiger, Vielfahrer an
/// vollen — ein kleiner Tag hebt die Rate pro gewonnenem Punkt stark, ein
/// voller kaum, also gleichen sich die Raten an, während die Punkte die
/// Frequenz von allein nachregeln. Bewusst **kein I-Anteil**: Die Rate ist
/// selbst schon ein integrierender Zustand; ein Integrator darauf wäre
/// Doppel-Integration und schwänge (über-/unterkorrigierte Personen im
/// Wechsel).
///
/// Greift nur bei `pointsWeight == 1.0`: Der Trim ist in Punkte-Einheiten
/// definiert. Fährt eine Gruppe das Gewicht zurück (die „Rückfahrkarte"),
/// gilt wieder unverändert der kombinierte Rang aus [rankPresent].
String? suggestPlanDriver(
  Iterable<String> presentIds,
  Map<String, PersonStats> stats,
  AppSettings settings, {
  required double dayFactor,
}) {
  final ids = presentIds.toList();
  if (ids.isEmpty) return null;
  if (settings.pointsWeight != 1.0 || dayFactor == 0) {
    return suggestDriver(ids, stats, settings);
  }

  PersonStats of(String id) =>
      stats[id] ??
      PersonStats(
        personId: id,
        driven: 0,
        ridden: 0,
        oneWay: 0,
        carried: 0,
        points: 0,
      );

  final meanShare =
      ids.map((id) => of(id).driveShare).reduce((a, b) => a + b) / ids.length;
  double effective(String id) =>
      of(id).points -
      kRateBalance * (of(id).driveShare - meanShare) * dayFactor;

  // Gleicher Tie-Break wie in [rankPresent]: am längsten nicht gefahren
  // zuerst (nie gefahren vor allen), dann Id für Determinismus.
  final sorted = [...ids]
    ..sort((a, b) {
      final byEffective = effective(a).compareTo(effective(b));
      if (byEffective != 0) return byEffective;
      final aLast = of(a).lastDrive;
      final bLast = of(b).lastDrive;
      if (aLast == null && bLast != null) return -1;
      if (aLast != null && bLast == null) return 1;
      if (aLast != null && bLast != null) {
        final byLast = aLast.compareTo(bLast);
        if (byLast != 0) return byLast;
      }
      return a.compareTo(b);
    });
  return sorted.first;
}

/// Die beiden Auffälligkeiten für die Startseite: Wer fährt mit vollem Auto,
/// wer meist fast allein? Beides ist [PersonStats.quote] — Ø Mitfahrer je
/// eigener Fahrt.
///
/// Warum das die Rangliste erklärt: Der Fahraufwand ist pro Fahrt derselbe,
/// die Punkte sind es nicht. Wer immer vier Leute mitnimmt, sammelt je Fahrt
/// drei Punkte und hat schnell ein Polster; wer immer nur einen mitnimmt,
/// muss für dasselbe Polster dreimal so oft fahren und steht deshalb ständig
/// wieder oben. Genau diese Schieflage gleicht der kombinierte Rang aus
/// (KONZEPT.md 3.2) — sichtbar war sie bisher nirgends.
class QuoteExtremes {
  const QuoteExtremes({this.fullestId, this.emptiestId});

  /// Höchste Quote — „Volle Kischt".
  final String? fullestId;

  /// Niedrigste Quote — „Fast alloi".
  final String? emptiestId;
}

/// Ab so vielen eigenen Fahrten zählt jemand mit. Darunter würde ein einziger
/// voller (oder leerer) Tag schon einen Titel tragen.
const minDrivesForQuoteBadge = 3;

/// Extremwerte der Quote unter [ids]. Leer, wenn zu wenige Personen genug
/// gefahren sind oder alle dieselbe Quote haben — dann sagt die Markierung
/// nichts aus und wäre nur Dekoration.
QuoteExtremes findQuoteExtremes(
  Iterable<String> ids,
  Map<String, PersonStats> stats,
) {
  final eligible = <PersonStats>[
    for (final id in ids)
      if (stats[id] case final s?)
        if (s.driven >= minDrivesForQuoteBadge && s.quote != null) s,
  ];
  // Bei zwei Personen wäre einer zwangsläufig „voll" und der andere „leer",
  // ohne dass das etwas bedeutet.
  if (eligible.length < 3) return const QuoteExtremes();

  eligible.sort((a, b) => a.quote!.compareTo(b.quote!));
  final lowest = eligible.first;
  final highest = eligible.last;
  if (lowest.quote == highest.quote) return const QuoteExtremes();

  return QuoteExtremes(
    fullestId: highest.personId,
    emptiestId: lowest.personId,
  );
}

/// Ein Tag im Wochenplan.
class PlannedDay {
  const PlannedDay({
    required this.date,
    required this.availableIds,
    this.oneWayIds = const {},
    this.suggestedDriverId,
    this.driverId,
    this.confirmed = false,
    this.tripId,
  });

  final DateTime date;

  /// Wer an diesem Tag mitfahren kann, alphabetisch nach Id.
  final List<String> availableIds;

  /// Wer davon nur eine Richtung mitfährt. Teilmenge von [availableIds];
  /// diese Personen kommen als Fahrer nicht in Frage.
  final Set<String> oneWayIds;

  /// Was die Fairness-Regel vorschlägt — `null`, wenn niemand verfügbar ist.
  final String? suggestedDriverId;

  /// Wer tatsächlich fahren soll: der Vorschlag oder das Übersteuern.
  final String? driverId;

  /// Für diesen Tag existiert bereits eine echte Fahrt. Dann ist nichts mehr
  /// zu planen und der Tag zählt regulär in die Statistik.
  final bool confirmed;

  /// Die eingetragene Fahrt, falls [confirmed] — damit der Planer direkt in
  /// deren Bearbeitung springen kann, statt sie in der Historie suchen zu
  /// lassen.
  final String? tripId;

  bool get isOverridden =>
      !confirmed && driverId != null && driverId != suggestedDriverId;
}

/// Wer das vollste Auto der Woche fährt — das Konfetti im Planer.
///
/// Gezählt wird **je Tag** (Mitfahrer des Tages, der Fahrer selbst nicht):
/// Gefeiert wird der vollste einzelne Tag der Woche, nicht die Wochensumme —
/// entschieden 2026-07-22. Bei Gleichstand bekommen **alle** Fahrer solcher
/// Tage das Konfetti; leer, wenn niemand jemanden mitnimmt.
///
/// Eine 1-way-Mitfahrt zählt hier als **ganzer Kopf**, nicht als halbe wie in
/// den Punkten: Die Auszeichnung feiert ein volles Auto, nicht den
/// Punktestand — und Geplantes darf die Punkte ohnehin nie berühren.
Set<String> celebratedDrivers(List<PlannedDay> days) {
  final fullest = <String, int>{}; // Fahrer → vollster eigener Tag.
  for (final day in days) {
    final driver = day.driverId;
    if (driver == null) continue;
    final passengers = day.availableIds.where((id) => id != driver).length;
    fullest[driver] = math.max(fullest[driver] ?? 0, passengers);
  }
  final best = fullest.values.fold(0, math.max);
  if (best == 0) return const {};
  return {
    for (final entry in fullest.entries)
      if (entry.value == best) entry.key,
  };
}

int _dayKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

/// Fahrer-Vorschläge für eine ganze Woche.
///
/// Entscheidend ist die **Vorwärts-Simulation**: Jeder Tag wird gegen die
/// Statistik *inklusive* der bereits vorgeschlagenen Vortage gerechnet. Ohne
/// das ändert sich die Statistik erst, wenn eine Fahrt wirklich eingetragen
/// wird — und der Planer würde fünf Tage hintereinander dieselbe Person
/// vorschlagen.
///
/// Tage mit einer bereits eingetragenen Fahrt bleiben unangetastet: Sie
/// stecken schon in [trips] und dürfen nicht zusätzlich simuliert werden,
/// sonst zählte derselbe Tag doppelt.
///
/// Wer nur eine Richtung mitfährt, **kann an dem Tag nicht Fahrer sein** —
/// ein halber Weg stellt kein Auto. Für die Simulation zählt er als
/// 1-way-Mitfahrt (halbe Punkte), nicht als volle.
///
/// [seats] sind die gepflegten Sitzplätze (inklusive Fahrer) je Person. Wessen
/// Auto für die Anwesenden reicht, wird bevorzugt — aber **vor** der
/// Fairness-Regel gefiltert, nicht in sie hineingerechnet: Die Punkte bleiben
/// unangetastet, es wird nur die Auswahl eingeschränkt. Fehlt der Eintrag oder
/// passt niemandes Auto, gilt wieder das ganze Kandidatenfeld.
///
/// Die Fahrerwahl je Tag trifft [suggestPlanDriver]: Punkte zuerst, dazu der
/// auf ±2 Punkte begrenzte Fahrraten-Trim entlang der Tagesgrößen.
List<PlannedDay> planWeek({
  required List<DateTime> dates,
  required Map<DateTime, Map<String, PlanRide>> availability,
  required Map<DateTime, String> overrides,
  required List<Trip> trips,
  required AppSettings settings,
  Map<String, int> seats = const {},
}) {
  final availableByDay = {
    for (final entry in availability.entries) _dayKey(entry.key): entry.value,
  };
  final overrideByDay = {
    for (final entry in overrides.entries) _dayKey(entry.key): entry.value,
  };
  final realTripByDay = {for (final trip in trips) _dayKey(trip.date): trip};

  // Tagesgrößen der noch planbaren Tage (Mitfahrer = Verfügbare − Fahrer),
  // normiert auf [−1, 1] um das Wochenmittel — der [dayFactor] für den
  // Fahrraten-Trim in [suggestPlanDriver]. Eingetragene und leere Tage
  // zählen nicht mit: Dort gibt es nichts mehr zu wählen.
  final dayPassengers = <int, int>{
    for (final date in dates)
      if (!realTripByDay.containsKey(_dayKey(date)) &&
          (availableByDay[_dayKey(date)] ?? const {}).isNotEmpty)
        _dayKey(date): availableByDay[_dayKey(date)]!.length - 1,
  };
  final meanPassengers = dayPassengers.isEmpty
      ? 0.0
      : dayPassengers.values.reduce((a, b) => a + b) / dayPassengers.length;
  final maxDeviation = dayPassengers.values.fold(
    0.0,
    (max, v) => math.max(max, (v - meanPassengers).abs()),
  );
  double dayFactorOf(int key) => maxDeviation == 0
      ? 0
      : ((dayPassengers[key] ?? meanPassengers) - meanPassengers) /
            maxDeviation;

  // Wächst mit jedem geplanten Tag — das ist die Simulation.
  final simulated = <Trip>[...trips];
  final plan = <PlannedDay>[];

  for (final date in [...dates]..sort()) {
    final key = _dayKey(date);
    final rides = availableByDay[key] ?? const <String, PlanRide>{};
    final available = rides.keys.toList()..sort();
    final oneWayIds = {
      for (final e in rides.entries)
        if (e.value == PlanRide.oneWay) e.key,
    };

    final existing = realTripByDay[key];
    if (existing != null) {
      plan.add(
        PlannedDay(
          date: date,
          availableIds: available,
          oneWayIds: oneWayIds,
          driverId: existing.driverId,
          confirmed: true,
          tripId: existing.id,
        ),
      );
      continue;
    }

    if (available.isEmpty) {
      plan.add(PlannedDay(date: date, availableIds: available));
      continue;
    }

    // Wer nur eine Richtung mitfährt, stellt kein Auto — er kommt als Fahrer
    // nicht in Frage. Sind alle verfügbaren Personen 1-way, bleibt der Tag
    // ohne Fahrer statt jemanden vorzuschlagen, der gar nicht fahren kann.
    final candidates = [
      for (final id in available)
        if (!oneWayIds.contains(id)) id,
    ];
    // Wessen Auto reicht für alle, die an dem Tag können? Ein fehlender
    // Eintrag sortiert nie aus — jede Person hat zwar eine Vorgabe (5), aber
    // die Karte kann unvollständig übergeben werden, und daraus darf kein
    // stiller Ausschluss werden.
    final fitting = [
      for (final id in candidates)
        if ((seats[id] ?? available.length) >= available.length) id,
    ];
    // Passt an einem Tag niemandes Auto, bleibt der beste Vorschlag aus allen
    // Kandidaten stehen: ein Tag ganz ohne Fahrer wäre schlechter als einer,
    // an dem man zusammenrückt oder ein zweites Auto nimmt.
    final pool = fitting.isEmpty ? candidates : fitting;
    final stats = computeStats(simulated, settings);
    final suggested = suggestPlanDriver(
      pool,
      stats,
      settings,
      dayFactor: dayFactorOf(key),
    );
    // Ein Übersteuern auf jemanden, der inzwischen abgesagt hat oder nur noch
    // eine Richtung mitfährt, wird stillschweigend ignoriert statt eine tote
    // Auswahl anzuzeigen.
    final override = overrideByDay[key];
    final driver = override != null && candidates.contains(override)
        ? override
        : suggested;

    plan.add(
      PlannedDay(
        date: date,
        availableIds: available,
        oneWayIds: oneWayIds,
        suggestedDriverId: suggested,
        driverId: driver,
      ),
    );

    if (driver != null) {
      simulated.add(
        Trip(
          id: 'plan-$key',
          date: date,
          participations: {
            for (final id in available)
              id: id == driver
                  ? ParticipationStatus.driver
                  // 1-way zählt halb (oneWayFactor). Als volle Mitfahrt
                  // gebucht, rechnete der Vorschlag der Folgetage mit zu
                  // vielen Punkten und die ganze Woche kippte.
                  : oneWayIds.contains(id)
                  ? ParticipationStatus.oneWay
                  : ParticipationStatus.passenger,
          },
        ),
      );
    }
  }

  return plan;
}

/// Montag bis Freitag der Woche, die geplant werden soll.
///
/// Am Wochenende zeigt der Planer die **kommende** Woche: Die laufende ist
/// gefahren, ein Plan dafür wäre nur noch Rückschau.
List<DateTime> planningWeek([DateTime? today]) {
  final now = today ?? DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  final monday = base.weekday >= DateTime.saturday
      ? base.add(Duration(days: DateTime.monday + 7 - base.weekday))
      : base.subtract(Duration(days: base.weekday - DateTime.monday));
  return [for (var i = 0; i < 5; i++) monday.add(Duration(days: i))];
}

/// Darf für [planDate] schon eine Fahrt eingetragen werden?
///
/// Erst ab dem Fahrtag: Vorher steht nicht fest, wer wirklich mitfährt, und
/// eine im Voraus eingetragene Fahrt verschiebt die Punkte aller anderen für
/// etwas, das noch gar nicht passiert ist.
bool canConfirmPlan(DateTime planDate, DateTime today) => !DateTime(
  planDate.year,
  planDate.month,
  planDate.day,
).isAfter(DateTime(today.year, today.month, today.day));
