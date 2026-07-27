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

/// Eine Solo-Fahrt: nur eine Person beteiligt, niemand wurde mitgenommen.
///
/// Sie ist keine Fahrgemeinschafts-Fahrt und zählt deshalb **gar nicht**
/// (Issue #61, Wunsch der Gruppe): nicht in den Punkten (dort war sie
/// schon immer 0), nicht im Fahranteil — der steuert seit dem Raten-Trim
/// die Planer-Vorschläge — und nicht in Quote oder Kilometern. Die
/// Historie zeigt sie blass mit dem Hinweis „zählt nicht".
bool isSoloTrip(Trip trip) => trip.participations.length == 1;

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
    // Solo-Fahrten sind für jede Kennzahl unsichtbar (Issue #61) — auch
    // für lastDrive/lastParticipation, damit es nur eine Wahrheit gibt.
    if (isSoloTrip(trip)) continue;
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
/// mehr als 6 (Raten liegen in 0..1). Jenseits dieses Bandes entscheiden
/// exakt die Punkte — die Grenze steckt in der Verstärkung selbst, nicht in
/// einer Sonderklausel (Muster entschieden 2026-07-22 mit Deckel 2; auf 6
/// gehoben 2026-07-24, weil das im Zielflotten-Soak den Raten-Worst-Case
/// von ±2,7 auf ±2,2 pp senkt — den strukturellen Boden. Die PRAKTISCHE
/// Autorität bleibt winzig: Reale Δ-Raten liegen um 0,03, der Trim bewegt
/// also ~0,2 Punkte. Details in
/// `doc/entscheidung-mitfahrer-verteilung.md`, Nachtrag 3).
const kRateBalance = 6.0;

/// Volle Fairness-Reihenfolge für einen **Plan-Tag**: Punkte zuerst, dazu ein
/// begrenzter Fahrraten-Trim (nur hier — Dashboard und Fahrten-Editor bleiben
/// bei [suggestDriver]). [suggestPlanDriver] ist der erste Eintrag; die
/// Mehr-Auto-Wahl (Issue #62) braucht die ganze Liste.
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
/// Die Reihenfolge ist **pool-unabhängig**: `meanShare` verschiebt alle
/// Kandidaten desselben Pools um denselben Betrag und ändert die Ordnung
/// nie — filtern vor oder nach dem Sortieren ist gleichwertig. Darauf
/// stützt sich die Sitzplatz-Auswahl in [planWeek].
///
/// Greift nur bei `pointsWeight == 1.0`: Der Trim ist in Punkte-Einheiten
/// definiert. Fährt eine Gruppe das Gewicht zurück (die „Rückfahrkarte"),
/// gilt wieder unverändert der kombinierte Rang aus [rankPresent].
List<String> rankedPlanDrivers(
  Iterable<String> presentIds,
  Map<String, PersonStats> stats,
  AppSettings settings, {
  required double dayFactor,
}) {
  final ids = presentIds.toList();
  if (ids.isEmpty) return const [];
  if (settings.pointsWeight != 1.0 || dayFactor == 0) {
    return [
      for (final candidate in rankPresent(ids, stats, settings))
        candidate.personId,
    ];
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
  return [...ids]..sort((a, b) {
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
}

/// Fahrer-Vorschlag für einen Plan-Tag — Kopf von [rankedPlanDrivers].
String? suggestPlanDriver(
  Iterable<String> presentIds,
  Map<String, PersonStats> stats,
  AppSettings settings, {
  required double dayFactor,
}) => rankedPlanDrivers(
  presentIds,
  stats,
  settings,
  dayFactor: dayFactor,
).firstOrNull;

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

  /// Höchste Quote — „Volle Kischd".
  final String? fullestId;

  /// Niedrigste Quote — „Faschd alloi".
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

/// Ein Auto eines Plan-Tags: Fahrer plus die ihm zugeteilten Mitfahrer.
///
/// Die Aufteilung ist eine berechnete Kennzahl wie der Fahrer selbst — sie
/// wird nie gespeichert (Konzept zu Issue #62). An bestätigten Tagen stehen
/// hier die **echten** Insassen der eingetragenen Fahrt(en); nur dort trägt
/// das Auto eine [tripId].
class PlannedCar {
  const PlannedCar({
    required this.driverId,
    this.fullIds = const [],
    this.oneWayIds = const [],
    this.tripId,
  });

  final String driverId;

  /// Volle Mitfahrer dieses Autos (ohne Fahrer), sortiert nach Id.
  final List<String> fullIds;

  /// 1-way-Mitfahrer dieses Autos, sortiert nach Id.
  final List<String> oneWayIds;

  /// Die echte Fahrt hinter diesem Auto — nur an bestätigten Tagen.
  final String? tripId;

  /// Personen im Auto inklusive Fahrer — das Gegenstück zu [Person.seats].
  int get headcount => 1 + fullIds.length + oneWayIds.length;
}

/// Ein Tag im Wochenplan.
class PlannedDay {
  const PlannedDay({
    required this.date,
    required this.availableIds,
    this.oneWayIds = const {},
    this.suggestedDriverIds = const [],
    this.cars = const [],
    this.confirmed = false,
  });

  final DateTime date;

  /// Wer an diesem Tag mitfahren kann, alphabetisch nach Id.
  final List<String> availableIds;

  /// Wer davon nur eine Richtung mitfährt. Teilmenge von [availableIds];
  /// diese Personen kommen als Fahrer nicht in Frage.
  final Set<String> oneWayIds;

  /// Was die Fairness-Regel vorschlägt, Auto 1 zuerst — leer, wenn niemand
  /// fahren kann oder der Tag bestätigt ist.
  final List<String> suggestedDriverIds;

  /// Die Autos des Tages mit zugeteilten Mitfahrern: der Vorschlag oder das
  /// Übersteuern. Leer = kein Fahrer möglich.
  final List<PlannedCar> cars;

  /// Für diesen Tag existiert bereits mindestens eine echte Fahrt. Dann ist
  /// nichts mehr zu planen und der Tag zählt regulär in die Statistik.
  final bool confirmed;

  /// Alle Fahrer des Tages, in Auto-Reihenfolge.
  List<String> get driverIds => [for (final car in cars) car.driverId];

  /// Fahrer des ersten Autos. Solange die UI nur ein Auto kennt (Teil 1 von
  /// Issue #62), hält dieser Getter sie unverändert am Laufen.
  String? get driverId => cars.firstOrNull?.driverId;

  /// Erster Vorschlags-Fahrer — Gegenstück zu [driverId].
  String? get suggestedDriverId => suggestedDriverIds.firstOrNull;

  /// Die eingetragene Fahrt des ersten Autos, falls [confirmed] — damit der
  /// Planer direkt in deren Bearbeitung springen kann, statt sie in der
  /// Historie suchen zu lassen.
  String? get tripId => cars.firstOrNull?.tripId;

  /// Von Hand gesetzt heißt: Die Fahrer-MENGE weicht vom Vorschlag ab.
  bool get isOverridden {
    if (confirmed || cars.isEmpty) return false;
    final actual = {for (final car in cars) car.driverId};
    final suggested = suggestedDriverIds.toSet();
    return actual.length != suggested.length || !actual.containsAll(suggested);
  }
}

/// Wer das vollste Auto der Woche fährt — das Konfetti im Planer.
///
/// Gezählt wird **je Tag** (Mitfahrer des Tages, der Fahrer selbst nicht):
/// Gefeiert wird der vollste einzelne Tag der Woche, nicht die Wochensumme —
/// entschieden 2026-07-22. Bei Gleichstand bekommen **alle** Fahrer solcher
/// Tage das Konfetti; leer, wenn niemand jemanden mitnimmt.
///
/// Gewichtet wird **wie in den Punkten** (Issue #59, Wunsch der Gruppe):
/// volle Mitfahrt = 1, 1-way = [oneWayFactor] — derselbe Faktor aus den
/// Gruppen-Settings, den auch `carriedOfTrip` nutzt. Ursprünglich zählte
/// hier jeder Kopf ganz; das fühlte sich falsch an, weil zwei halbe
/// Mitfahrten ein „volleres" Auto anzeigten als eine ganze. Das Hajo
/// bleibt trotzdem reine Dekoration: berechnet, nie gespeichert, und
/// Geplantes berührt die Punkte weiterhin nicht.
///
/// Seit Issue #62 zählt jedes **Auto** für sich (ein Tag kann mehrere
/// haben). Bestätigte Tage zählen damit die echten Insassen ihrer Fahrt
/// statt der Plan-Verfügbarkeit — die frühere Zählung übers ganze Raster
/// war nur richtig, solange Fahrt und Plan deckungsgleich waren.
Set<String> celebratedDrivers(
  List<PlannedDay> days, {
  required double oneWayFactor,
}) {
  final fullest = <String, double>{}; // Fahrer → punktstärkstes eigenes Auto.
  for (final day in days) {
    for (final car in day.cars) {
      final carried = car.fullIds.length + oneWayFactor * car.oneWayIds.length;
      fullest[car.driverId] = math.max(fullest[car.driverId] ?? 0, carried);
    }
  }
  final best = fullest.values.fold(0.0, math.max);
  if (best <= 0) return const {};
  return {
    for (final entry in fullest.entries)
      if (entry.value == best) entry.key,
  };
}

/// Vorschau: Statistik, wie sie NACH der geplanten Woche aussähe.
///
/// Die geplanten (noch nicht bestätigten) Tage werden **je Auto** als
/// Pseudo-Fahrt zu den echten dazugerechnet — Fahrer, volle Mitfahrer,
/// 1-way wie eingetragen; so teilt sich das „Mitgenommen" eines
/// Mehr-Auto-Tags auf seine Fahrer (Issue #62). Bestätigte Tage stecken
/// schon in [trips] und werden nicht doppelt gezählt; ein geplanter
/// Solo-Tag — oder ein Auto ohne Mitfahrer — fällt über die Solo-Regel
/// (Issue #61) von selbst heraus, genau wie der echte Eintrag später auch.
///
/// Nur fürs **Anzeigen** von Deltas im Planer (Issue #60): Punktediff und
/// Fahrraten-Änderung der Woche. Geplantes berührt die echten Punkte nie —
/// das hier wird berechnet, nie gespeichert.
Map<String, PersonStats> statsWithPlannedWeek(
  List<PlannedDay> days,
  List<Trip> trips,
  AppSettings settings,
) {
  final planned = <Trip>[
    for (final day in days)
      if (!day.confirmed)
        for (final (i, car) in day.cars.indexed)
          Trip(
            id: 'geplant-${_dayKey(day.date)}-$i',
            date: day.date,
            participations: {
              car.driverId: ParticipationStatus.driver,
              for (final id in car.fullIds) id: ParticipationStatus.passenger,
              for (final id in car.oneWayIds) id: ParticipationStatus.oneWay,
            },
          ),
  ];
  return computeStats([...trips, ...planned], settings);
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
/// sonst zählte derselbe Tag doppelt. Jede echte Fahrt des Tages erscheint
/// als eigenes Auto (bis Issue #62 kollabierten mehrere auf die letzte).
///
/// Wer nur eine Richtung mitfährt, **kann an dem Tag nicht Fahrer sein** —
/// ein halber Weg stellt kein Auto. Für die Simulation zählt er als
/// 1-way-Mitfahrt (halbe Punkte), nicht als volle.
///
/// **Sitzplätze und Autozahl (Issue #62):** [seats] sind die gepflegten
/// Plätze (inklusive Fahrer) je Person; ein fehlender Eintrag sortiert nie
/// aus. Reicht ein einzelnes Auto für alle, bleibt es bei einem. Sonst
/// fahren so wenige Autos wie möglich: k ist die kleinste Zahl, deren k
/// größte Kandidaten-Autos alle fassen — ein 7-Sitzer schlägt zwei kleine.
/// **Wer** fährt, entscheidet weiter die Fairness: die punktbeste machbare
/// k-Teilmenge entlang [rankedPlanDrivers] (die Reihenfolge ist
/// pool-unabhängig, siehe dort — deshalb ist k = 1 exakt der alte
/// „passendes Auto zuerst"-Filter). Reichen selbst alle Autos zusammen
/// nicht, fällt die Sitzprüfung weg: lieber zu wenige Plätze als ein Tag
/// ohne Fahrer — die alte Rückfalllinie, verallgemeinert.
List<PlannedDay> planWeek({
  required List<DateTime> dates,
  required Map<DateTime, Map<String, PlanRide>> availability,
  required Map<DateTime, Set<String>> overrides,
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
  final realTripsByDay = <int, List<Trip>>{};
  for (final trip in trips) {
    realTripsByDay.putIfAbsent(_dayKey(trip.date), () => []).add(trip);
  }

  // Tagesgrößen der noch planbaren Tage (Mitfahrer = Verfügbare − 1),
  // normiert auf [−1, 1] um das Wochenmittel — der [dayFactor] für den
  // Fahrraten-Trim in [rankedPlanDrivers]. Eingetragene und leere Tage
  // zählen nicht mit: Dort gibt es nichts mehr zu wählen. Dass ein
  // Mehr-Auto-Tag eigentlich k Fahrer stellt, ignoriert die Größe bewusst:
  // k steht erst nach der Wahl fest, und der Trim ist ohnehin auf ±2 Punkte
  // gedeckelt — eine genauere Tagesgröße änderte nur Nuancen.
  final dayPassengers = <int, int>{
    for (final date in dates)
      if (!realTripsByDay.containsKey(_dayKey(date)) &&
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

    final existing = realTripsByDay[key];
    if (existing != null) {
      // Ein eingetragener Tag zeigt die Fahrt, nicht die Planung (#85): Wer
      // wirklich mitgefahren ist, steht in der Fahrt — die Verfügbarkeit
      // wurde womöglich nie angetippt, wenn die Fahrt direkt im Editor
      // entstand. Beides wird vereint, und bei Widerspruch gewinnt die Fahrt
      // (wer voll mitfuhr, ist nicht mehr „nur eine Richtung").
      final rodeFull = <String>{};
      final rodeOneWay = <String>{};
      for (final trip in existing) {
        for (final e in trip.participations.entries) {
          if (e.value == ParticipationStatus.oneWay) {
            rodeOneWay.add(e.key);
          } else {
            rodeFull.add(e.key);
          }
        }
      }
      rodeOneWay.removeAll(rodeFull);
      plan.add(
        PlannedDay(
          date: date,
          availableIds: {...available, ...rodeFull, ...rodeOneWay}.toList()
            ..sort(),
          oneWayIds: {
            for (final id in oneWayIds)
              if (!rodeFull.contains(id)) id,
            ...rodeOneWay,
          },
          confirmed: true,
          cars: [
            // Eine (importierte) Fahrt ganz ohne Fahrer stellt kein Auto —
            // sie bleibt über die Historie erreichbar.
            for (final trip in existing)
              if (trip.driverId case final driverId?)
                PlannedCar(
                  driverId: driverId,
                  fullIds: [
                    for (final e in trip.participations.entries)
                      if (e.value == ParticipationStatus.passenger) e.key,
                  ]..sort(),
                  oneWayIds: [
                    for (final e in trip.participations.entries)
                      if (e.value == ParticipationStatus.oneWay) e.key,
                  ]..sort(),
                  tripId: trip.id,
                ),
          ],
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
    final n = available.length;
    // Ein fehlender Eintrag sortiert nie aus — jede Person hat zwar eine
    // Vorgabe (5), aber die Karte kann unvollständig übergeben werden, und
    // daraus darf kein stiller Ausschluss werden.
    int seatOf(String id) => seats[id] ?? n;

    final stats = computeStats(simulated, settings);
    final ranked = rankedPlanDrivers(
      candidates,
      stats,
      settings,
      dayFactor: dayFactorOf(key),
    );

    // Minimale Autozahl: kleinstes k, dessen k größte Autos alle fassen.
    final bySeatDesc = [...candidates]
      ..sort((a, b) {
        final bySeat = seatOf(b).compareTo(seatOf(a));
        return bySeat != 0 ? bySeat : a.compareTo(b);
      });
    final limit = candidates.length;
    var k = limit;
    var coverable = false;
    var seatSum = 0;
    for (var i = 0; i < limit; i++) {
      seatSum += seatOf(bySeatDesc[i]);
      if (seatSum >= n) {
        k = i + 1;
        coverable = true;
        break;
      }
    }

    List<String> suggested;
    if (!coverable) {
      // Reichen selbst alle (erlaubten) Autos zusammen nicht, fällt die
      // Sitzprüfung weg: lieber zu wenige Plätze als ein Tag ohne Fahrer —
      // die alte Rückfalllinie, verallgemeinert auf k Autos.
      suggested = ranked.take(k).toList();
    } else {
      // Fairness-erste machbare k-Teilmenge: je Slot der punktbeste
      // Kandidat, mit dem die restlichen Slots — besetzt mit den größten
      // übrigen Autos — noch auf n Plätze kommen. Die Prüfung ist exakt,
      // deshalb findet jeder Slot einen Fahrer.
      suggested = <String>[];
      var pickedSeats = 0;
      for (var slot = 0; slot < k; slot++) {
        final restSlots = k - slot - 1;
        for (final cand in ranked) {
          if (suggested.contains(cand)) continue;
          var rest = 0;
          var counted = 0;
          for (final other in bySeatDesc) {
            if (counted == restSlots) break;
            if (other == cand || suggested.contains(other)) continue;
            rest += seatOf(other);
            counted++;
          }
          if (pickedSeats + seatOf(cand) + rest >= n) {
            suggested.add(cand);
            pickedSeats += seatOf(cand);
            break;
          }
        }
      }
    }

    // Ein Übersteuern auf jemanden, der inzwischen abgesagt hat oder nur
    // noch eine Richtung mitfährt, verfällt JE PERSON statt eine tote
    // Auswahl anzuzeigen; verfallen alle, gilt wieder der Vorschlag. Eine
    // gültige Menge ersetzt den Vorschlag komplett — ohne Sitzprüfung, das
    // ist eine Menschenentscheidung (wie bisher beim einzelnen Fahrer).
    final override = {
      for (final id in overrideByDay[key] ?? const <String>{})
        if (candidates.contains(id)) id,
    };
    final driverSet = override.isEmpty
        ? suggested
        : [
            for (final id in ranked)
              if (override.contains(id)) id,
          ];

    // Mitfahrer deterministisch ausgeglichen verteilen: jede Person ins
    // Auto mit den meisten freien Plätzen (Gleichstand: erstes Auto). So
    // teilt sich das „Mitgenommen" des Tages möglichst gleichmäßig auf die
    // Fahrer, und kein Auto wird überfüllt, solange die Plätze insgesamt
    // reichen. 1-way belegt dabei einen Sitz — dieselbe Regel wie im
    // Fahrten-Editor.
    final carFull = [for (final _ in driverSet) <String>[]];
    final carOneWay = [for (final _ in driverSet) <String>[]];
    if (driverSet.isNotEmpty) {
      for (final id in available) {
        if (driverSet.contains(id)) continue;
        var best = 0;
        var bestFree = -n - 1;
        for (var i = 0; i < driverSet.length; i++) {
          final free =
              seatOf(driverSet[i]) -
              1 -
              carFull[i].length -
              carOneWay[i].length;
          if (free > bestFree) {
            bestFree = free;
            best = i;
          }
        }
        (oneWayIds.contains(id) ? carOneWay : carFull)[best].add(id);
      }
    }
    final cars = [
      for (var i = 0; i < driverSet.length; i++)
        PlannedCar(
          driverId: driverSet[i],
          fullIds: carFull[i],
          oneWayIds: carOneWay[i],
        ),
    ];

    plan.add(
      PlannedDay(
        date: date,
        availableIds: available,
        oneWayIds: oneWayIds,
        suggestedDriverIds: suggested,
        cars: cars,
      ),
    );

    // Je Auto eine Pseudo-Fahrt — so verteilt sich das „Mitgenommen" des
    // Tages auf alle Fahrer. Ein Auto ohne Mitfahrer ist dabei eine
    // Solo-Fahrt und zählt nichts (Issue #61), genau wie der spätere echte
    // Eintrag. 1-way zählt halb (oneWayFactor); als volle Mitfahrt gebucht,
    // rechnete der Vorschlag der Folgetage mit zu vielen Punkten und die
    // ganze Woche kippte.
    for (final (i, car) in cars.indexed) {
      simulated.add(
        Trip(
          id: 'plan-$key-$i',
          date: date,
          participations: {
            car.driverId: ParticipationStatus.driver,
            for (final id in car.fullIds) id: ParticipationStatus.passenger,
            for (final id in car.oneWayIds) id: ParticipationStatus.oneWay,
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

/// Der Tag, um den es als Nächstes geht — für das Banner auf der Übersicht
/// (#122).
///
/// Der erste Tag ab heute, an dem überhaupt jemand verfügbar ist und für den
/// noch **keine** Fahrt eingetragen ist. Ist die heutige Fahrt eingetragen,
/// rückt das Banner damit auf den Folgetag, ohne dass irgendwo eine Uhrzeit
/// entscheiden müsste, wann ein Tag „vorbei" ist — `confirmed` ist die
/// Auskunft, die die Gruppe selbst gegeben hat.
///
/// Weil [planningWeek] nur Montag bis Freitag liefert, steht am Freitag und
/// Samstag schon der Montag hier. Das ist gewollt: gefragt war die nächste
/// Fahrt, nicht „morgen" — sonst bliebe das Banner an zwei Tagen der Woche
/// leer.
PlannedDay? nextRide(List<PlannedDay> week, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (final day in week) {
    final date = DateTime(day.date.year, day.date.month, day.date.day);
    if (date.isBefore(today)) continue;
    if (day.confirmed) continue;
    if (day.availableIds.isEmpty) continue;
    return day;
  }
  return null;
}

/// Kalenderwoche nach ISO 8601 — Woche 1 ist die mit dem ersten Donnerstag
/// des Jahres (#84, Orientierung im Planer-Kopf).
///
/// Gerechnet wird in UTC: `Duration`-Addition auf lokalen `DateTime`s
/// verrutscht über die Sommerzeit-Umstellung um eine Stunde und damit
/// womöglich um einen Tag.
int isoWeekNumber(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  // Der Donnerstag derselben Woche bestimmt Jahr und Wochennummer.
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final firstDayOfYear = DateTime.utc(thursday.year);
  return 1 + thursday.difference(firstDayOfYear).inDays ~/ 7;
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
