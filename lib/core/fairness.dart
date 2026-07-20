/// fairness.dart – Punkte-/Statistikberechnung und Fahrer-Vorschlag.
///
/// Punktesystem (identisch zur Excel-Vorlage):
///   Punkte = Σ mitgenommen (an eigenen Fahrtagen)
///            − eigene Mitfahrten − OneWayFaktor × eigene 1-way-Fahrten.
/// „Wer ist dran" kombiniert Punkte-Rang und Fahranteil-Rang unter den
/// an einem Tag Anwesenden (siehe KONZEPT.md 3.2).
library;

import '../models/app_settings.dart';
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
  final DateTime? lastDrive;

  int get participationDays => driven + ridden + oneWay;

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

  for (final trip in trips) {
    final tripCarried = carriedOfTrip(trip, settings);
    for (final entry in trip.participations.entries) {
      final id = entry.key;
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
