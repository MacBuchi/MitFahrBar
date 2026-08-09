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
import '../models/group_defaults.dart';
import '../models/plan_ride.dart';
import '../models/person.dart';
import '../models/seat_choice.dart';
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
  ///
  /// Rechnet mit **einem** Preis für die ganze Historie — der Konstante aus
  /// den Parametern. Wer die Ersparnis je Woche mit dem Preis *dieser* Woche
  /// will, nimmt `weeklySavings` in `chart_data.dart`; beide teilen sich
  /// [savedCostsFor], damit es die Formel nur einmal gibt.
  double savedCosts(AppSettings s, Person person) => savedCostsFor(
    person: person,
    pricePerUnit: priceForEnergy(person.energyType, s),
    days: (ridden + oneWay).toDouble(),
    commuteKm: s.commuteKm,
  );
}

/// Die Ersparnis-Formel, an genau einer Stelle.
///
/// [days] ist die Zahl der Tage, an denen die Person mitgefahren ist statt
/// selbst zu fahren; [pricePerUnit] der dafür anzusetzende Preis (Liter oder
/// kWh). Ohne Verbrauch oder Energieart der Person ist die Ersparnis 0 —
/// nicht geschätzt: Ein angenommener Verbrauch stünde später in der
/// Gesamtsumme, ohne dass jemand ihn eingetragen hätte.
double savedCostsFor({
  required Person person,
  required double pricePerUnit,
  required double days,
  required double commuteKm,
}) {
  final consumption = person.consumptionPer100km;
  if (consumption == null || person.energyType == null) return 0;
  return consumption * pricePerUnit * days * commuteKm * 2 / 100;
}

/// Der Preis, mit dem eine Energieart gerechnet wird — die Konstante aus den
/// Parametern.
///
/// Steht hier und nicht im Aufrufer, weil `constantFor` in
/// `price_series.dart` dieselbe Zuordnung führt (Benzin → E5) und beide
/// nicht auseinanderlaufen dürfen: Sonst rechnete die Kachel mit einem
/// anderen Preis als das Diagramm darunter.
double priceForEnergy(EnergyType? energy, AppSettings s) => switch (energy) {
  EnergyType.electric => s.electricityPricePerKwh,
  EnergyType.diesel => s.dieselPricePerLiter,
  EnergyType.petrol => s.petrolPricePerLiter,
  null => 0,
};

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
/// `kRateBalance · Δ-Fahrrate · |dayFactor|` Punkte überbrücken. Jenseits
/// dieses Bandes entscheiden exakt die Punkte; die Grenze steckt in der
/// Verstärkung selbst, nicht in einer Sonderklausel.
///
/// Geschichte: Muster entschieden 2026-07-22 mit Deckel 2, auf 6 gehoben
/// 2026-07-24, **auf 12 gehoben 2026-08-09** (Marcus).
///
/// **Warum 12 — gemessen an ZWEI Datensätzen.** Gegen die echte
/// 401-Tage-Historie der Gruppe halbiert der Schritt die Abweichung der
/// Stammfahrer vom mittleren Fahranteil: **18,7 → 10,6 ‰**, bei
/// unveränderten Punkten. Der Zwölf-Seed-Soak bestätigt die Richtung
/// schwächer. Bewusst nicht nach dem Bestwert eines Datensatzes gewählt:
/// Die Kennzahl schwankt nicht monoton (auf der Historie ist k=30
/// schlechter als k=20, k=100 schlechter als k=60), und wer den Spitzenwert
/// pickt, überanpasst an dessen Zufall.
///
/// **Warum nicht 40, obwohl es auf der Historie minimal besser wäre**
/// (9,9 statt 10,6 ‰): Ab k≈20 kippt die Auslegung des Trims. Im Extremfall
/// — einer fuhr immer, einer nie, zwölf Punkte Abstand — schickt der Planer
/// bei k=40 am **kleinen** Tag den Vielfahrer statt den Wenigfahrer, also
/// genau umgekehrt zur Absicht „wer selten fährt, bekommt die kleinen Tage".
/// Der Grund: Bei unregelmäßiger Teilnahme liegt Δ-Rate um 0,2 statt 0,03,
/// die Autorität also bei 8 statt 1,2 Punkten — genug, um die beobachtete
/// Punkte-Spanne von ±2,5 zu überstimmen. Zwei Tests in `plan_test.dart`
/// nageln beide Invarianten fest; sie kippen bei 20 und bei 40, nicht bei
/// 12. **Wer den Wert erhöht, sieht sie fallen und weiß dann, was er tut.**
///
/// Nebenbefund: Die Punkte-Schranke des Soak durfte auf ±7 geöffnet werden
/// (Marcus, 09.08.2026), **wird aber nicht gebraucht** — bei 12 bleibt der
/// gemessene Höchstwert bei 3,5. Sie steht deshalb weiter auf ±5; ein
/// Grenzwert, der lockerer ist als nötig, fängt nichts mehr.
///
/// Alle Zahlen in `doc/entscheidung-mitfahrer-verteilung.md`, Nachträge 3
/// und 2026-08-09 (3).
const kRateBalance = 12.0;

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

  /// Ob [personId] in diesem Auto sitzt — als Fahrer oder als Mitfahrer.
  bool carries(String personId) =>
      driverId == personId ||
      fullIds.contains(personId) ||
      oneWayIds.contains(personId);
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
    this.forcedFor = const {},
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

  /// Fahrer, die **nur** wegen einer Absage im Satz stehen — Fahrer → die
  /// Personen, die ihn brauchen (#203).
  ///
  /// Berechnet wie alles hier, nie gespeichert. Der Umschalter „Wer fährt?"
  /// liest sie, um eine Abwahl gar nicht erst anzubieten, die die Rechnung
  /// im selben Atemzug überstimmen würde: Wer „zu diesen Bedingungen nicht"
  /// gesagt hat, braucht ein anderes Auto, und das nimmt ihm niemand nebenbei
  /// weg. Bis v0.69.0 verschwand die Abwahl kommentarlos.
  ///
  /// Leer ist der Normalfall — die Zusatzautos aus reiner Platznot stehen
  /// **nicht** darin, die sind eine Kapazitätsfrage und frei abwählbar.
  final Map<String, List<String>> forcedFor;

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
  Map<DateTime, List<SeatChoice>> seatChoices = const {},
  Map<DateTime, Map<String, GroupDefaults>> carDefaults = const {},
}) {
  final availableByDay = {
    for (final entry in availability.entries) _dayKey(entry.key): entry.value,
  };
  final overrideByDay = {
    for (final entry in overrides.entries) _dayKey(entry.key): entry.value,
  };
  // Der Gruppen-Schalter (#213) wirkt genau hier, an EINER Stelle: Ist die
  // Auto-Zuordnung aus, sind Zusagen und Auto-Abweichungen schlicht nicht da.
  //
  // Warum hier und nicht bei den Aufrufern: `settings` reicht ohnehin jeder
  // Aufrufer durch — die App wie `tool/notify.dart`. Gefiltert am Aufrufer
  // müssten es beide tun, und täte es einer nicht, verteilte er die Mitfahrer
  // anders als der andere; der Korb trüge dann je nach Schreiber verschiedene
  // Zeiten. Genau diese zweite Wahrheit soll der Schalter nicht erzeugen.
  //
  // Die Zeilen werden dabei **inert, nicht gelöscht** — Wiedereinschalten
  // stellt her, was dastand (dieselbe Regel wie bei verwaisten Zeilen).
  final on = settings.carAssignmentEnabled;
  final choicesByDay = {
    if (on)
      for (final entry in seatChoices.entries) _dayKey(entry.key): entry.value,
  };
  final carDefaultsByDay = {
    if (on)
      for (final entry in carDefaults.entries) _dayKey(entry.key): entry.value,
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
    var driverSet = override.isEmpty
        ? suggested
        : [
            for (final id in ranked)
              if (override.contains(id)) id,
          ];

    // Sitz-Entscheidungen des Tages (#189, Stufe B2): Pin und Ausschluss.
    //
    // **Gültig ist nur, was zu den AKTUELLEN Bedingungen passt.** `terms`
    // hält fest, wozu jemand ja oder nein gesagt hat — die Abweichung des
    // Autos zum Zeitpunkt der Entscheidung. Stimmt sie nicht mehr, wirkt die
    // Entscheidung nicht: Eine Zusage zu 06:45 ist kein Blankoscheck für
    // 05:30, und ein Nein zu 05:30 darf nicht bestehen bleiben, wenn der
    // Fahrer die Abweichung längst zurückgenommen hat — sonst gäbe es
    // dauerhaft zwei Autos wegen einer Zeit, die es nicht mehr gibt.
    // Fahrer entscheiden nicht über sich selbst (sie sitzen ohnehin in
    // ihrem Auto); Zeilen zu Personen, die gar nicht dabei sind, wirken
    // nicht — dieselbe Verwaisten-Regel wie bei `plan_car_defaults`.
    final dayCarDefaults =
        carDefaultsByDay[key] ?? const <String, GroupDefaults>{};
    final dayChoices = choicesByDay[key] ?? const <SeatChoice>[];
    final pins = seatPinsOf(
      dayChoices,
      dayCarDefaults,
      isAvailable: available.contains,
    );
    final excludedBy = <String, Set<String>>{};
    for (final choice in dayChoices) {
      // Nur ein ausdrückliches Nein schließt aus. Über `accepted` gelesen
      // käme dasselbe heraus — aber die Spalte ist seit #210 die Mitschrift
      // für alte Clients, und wer hier ihren Namen liest, hält sie für die
      // Wahrheit.
      if (choice.answer != SeatAnswer.no) continue;
      if (!available.contains(choice.personId)) continue;
      if (!choice.isCurrentFor(termsOf(dayCarDefaults[choice.driverId]))) {
        continue;
      }
      (excludedBy[choice.personId] ??= {}).add(choice.driverId);
    }

    // **Ein Ausschluss kann ein weiteres Auto erzwingen** — das ist sein
    // Zweck: „Zu diesen Bedingungen fahre ich dort nicht mit" heißt, jemand
    // anderes muss fahren. Wer dann fährt, entscheiden exakt die Punkte
    // (der fairness-erste noch nicht fahrende Kandidat, den die blockierte
    // Person nicht ausgeschlossen hat — oder sie selbst, wenn sie fahren
    // kann). Das gilt auch an übersteuerten Tagen: Genau dort entsteht der
    // Fall, denn die Zeit zu setzen schreibt die Fahrer fest (#183). Findet
    // sich niemand, bleibt die Person unplatziert — eine ehrliche Grenze,
    // kein stilles Hineinsetzen in ein Auto, dem sie abgesagt hat.
    driverSet = [...driverSet];
    // Wer nur deshalb fährt — Fahrer → die Personen, die ihn brauchen (#203).
    // Ohne diese Notiz kann der Umschalter „Wer fährt?" nicht unterscheiden,
    // ob eine Abwahl gewirkt hat oder von der Rechnung sofort überstimmt
    // wurde; bis v0.69.0 verwarf er sie stillschweigend.
    final forcedFor = <String, List<String>>{};

    /// Die Autos, in die [id] nach seinen Absagen überhaupt darf.
    Set<String> allowedFor(String id) {
      final out = excludedBy[id] ?? const <String>{};
      return {
        for (final d in driverSet)
          if (!out.contains(d)) d,
      };
    }

    /// Passen alle, die NUR in [allowed] dürfen, dort auch hinein?
    ///
    /// Ohne diese Prüfung endete die Schleife, sobald für jeden **irgendein**
    /// nicht ausgeschlossenes Auto existierte — ob dort noch ein Platz frei
    /// ist, fragte niemand. Ein Nein konnte damit kein weiteres Auto
    /// erzwingen, wenn die übrigen bloß **voll** waren; die Verteilung stopfte
    /// die Leute anschließend über die Rückfalllinie hinein.
    ///
    /// Das ist ausdrücklich NICHT der Fall aus #62: Dort reichen die Sitze
    /// des Tages insgesamt nicht, und Überfüllen ist die ehrliche Antwort.
    /// Hier reichen sie — sie sind nur durch Absagen unerreichbar, und genau
    /// dafür gibt es das Zusatzauto.
    ///
    /// Gezählt wird nach Hall: Wer ausschließlich in [allowed] darf, muss
    /// dort Platz finden; die Fahrer dieser Autos sitzen in ihrem eigenen und
    /// belegen je einen Sitz.
    bool cramped(Set<String> allowed) {
      if (allowed.isEmpty) return true;
      var need = 0;
      for (final q in available) {
        if (driverSet.contains(q)) {
          if (allowed.contains(q)) need++;
        } else if (allowedFor(q).every(allowed.contains)) {
          need++;
        }
      }
      final have = allowed.fold(0, (sum, d) => sum + seatOf(d));
      return need > have;
    }

    while (true) {
      final blocked = [
        for (final id in available)
          if (!driverSet.contains(id) &&
              driverSet.isNotEmpty &&
              cramped(allowedFor(id)))
            id,
      ];
      if (blocked.isEmpty) break;
      String? extra;
      for (final cand in ranked) {
        if (driverSet.contains(cand)) continue;
        final helps = blocked.any(
          (p) =>
              p == cand || !(excludedBy[p] ?? const <String>{}).contains(cand),
        );
        if (helps) {
          extra = cand;
          break;
        }
      }
      if (extra == null) break;
      forcedFor[extra] = [
        for (final p in blocked)
          if (p == extra ||
              !(excludedBy[p] ?? const <String>{}).contains(extra))
            p,
      ];
      driverSet.add(extra);
    }
    // An einem Vorschlags-Tag ist das Zusatzauto Teil des VORSCHLAGS — der
    // Tag bleibt „Vorschlag", denn kein Mensch hat die Fahrer-Menge gesetzt;
    // sie folgt nur einer anderen menschlichen Entscheidung (dem Nein).
    if (override.isEmpty) suggested = driverSet;

    // Mitfahrer deterministisch verteilen — in zwei Schritten:
    //
    // **Erst die Pins**, in `decided_at`-Reihenfolge und nur auf freie
    // Plätze: Wer zuerst gepinnt hat, bleibt; wessen Pin kein Platz mehr
    // erfüllt, fällt in die automatische Verteilung (nicht aus dem Tag) und
    // darf dort auch im vollen Wunsch-Auto landen — der Pin ist ein
    // Vorrecht auf einen Platz, kein Ausschluss aus allen anderen. Ein Pin
    // auf einen Fahrer, der heute nicht fährt, ist verwaist und wirkt nicht.
    //
    // **Dann alle Übrigen: ins Auto mit den WENIGSTEN Insassen** (#210,
    // Gruppe am 09.08.2026). Erst wenn dort kein Platz mehr frei ist, gewinnt
    // ein anderes Auto mit freiem Platz — „nur bei Erreichen des Limits
    // gewinnen zusätzlich freie Plätze in anderen Fahrzeugen".
    //
    // Bis v0.71.0 entschieden die **meisten freien Plätze**. Das erklärte
    // Ziel war schon damals, das „Mitgenommen" gleichmäßig auf die Fahrer zu
    // verteilen — bei ungleich großen Autos erreicht es das aber gerade
    // nicht: Ein 7-Sitzer und ein 4-Sitzer enden mit gleich vielen FREIEN
    // Plätzen, also trägt der große systematisch mehr. Genau das ist im
    // Soak-Report als Grenze notiert („bei dauerhaftem Kapazitäts-Gefälle
    // driften die Punkte unbegrenzt"). Nach Kopfzahl verteilt entfällt der
    // Antrieb dafür; **ob die Drift wirklich kleiner wird, sagt erst die
    // Neumessung** (#212) — hier wird nichts dergleichen behauptet.
    //
    // Gleichstand geht an das frühere Auto, und das ist der bedürftigste
    // Fahrer: `driverSet` steht in `ranked`-Reihenfolge. Der Punkte-Anteil
    // der Verteilung steckt allein darin.
    //
    // Ausschlüsse werden gemieden. 1-way belegt einen Sitz — dieselbe Regel
    // wie im Fahrten-Editor.
    final carFull = [for (final _ in driverSet) <String>[]];
    final carOneWay = [for (final _ in driverSet) <String>[]];
    final seated = <String>{};
    if (driverSet.isNotEmpty) {
      for (final pin in pins) {
        if (seated.contains(pin.personId)) continue;
        if (driverSet.contains(pin.personId)) continue;
        final i = driverSet.indexOf(pin.driverId);
        if (i < 0) continue;
        final free =
            seatOf(driverSet[i]) - 1 - carFull[i].length - carOneWay[i].length;
        if (free <= 0) continue;
        (oneWayIds.contains(pin.personId) ? carOneWay : carFull)[i].add(
          pin.personId,
        );
        seated.add(pin.personId);
      }
      for (final id in available) {
        if (driverSet.contains(id) || seated.contains(id)) continue;
        final excluded = excludedBy[id] ?? const <String>{};
        // Zwei Kandidaten nebeneinander: das leerste Auto MIT freiem Platz,
        // und — falls keines mehr Platz hat — das leerste überhaupt.
        //
        // Der zweite ist die Rückfalllinie aus #62 und darf nicht wegfallen:
        // Reichen die Sitze des Tages insgesamt nicht, wird überfüllt statt
        // jemanden stillschweigend stehen zu lassen. Ohne ihn verschwänden
        // Leute aus dem Plan, sobald ein Auto zu klein ist — und niemand
        // sähe, warum.
        var best = -1;
        var bestTaken = -1;
        var anyCar = -1;
        var anyTaken = -1;
        for (var i = 0; i < driverSet.length; i++) {
          if (excluded.contains(driverSet[i])) continue;
          final taken = carFull[i].length + carOneWay[i].length;
          if (anyCar < 0 || taken < anyTaken) {
            anyCar = i;
            anyTaken = taken;
          }
          if (seatOf(driverSet[i]) - 1 - taken <= 0) continue;
          if (best < 0 || taken < bestTaken) {
            best = i;
            bestTaken = taken;
          }
        }
        final target = best >= 0 ? best : anyCar;
        // Alle Autos ausgeschlossen und kein Kandidat mehr übrig: Die
        // Person bleibt sichtbar draußen statt still in einem Auto zu
        // sitzen, dem sie abgesagt hat.
        if (target < 0) continue;
        (oneWayIds.contains(id) ? carOneWay : carFull)[target].add(id);
      }
    }
    final cars = [
      for (var i = 0; i < driverSet.length; i++)
        PlannedCar(
          driverId: driverSet[i],
          fullIds: carFull[i]..sort(),
          oneWayIds: carOneWay[i]..sort(),
        ),
    ];

    plan.add(
      PlannedDay(
        date: date,
        availableIds: available,
        oneWayIds: oneWayIds,
        suggestedDriverIds: suggested,
        cars: cars,
        forcedFor: forcedFor,
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
/// Ab Freitag 12 Uhr und am Wochenende zeigt der Planer die **kommende**
/// Woche: Die laufende ist gefahren, ein Plan dafür wäre nur noch Rückschau.
/// Der Freitagmittag-Wechsel kam mit #131 und hält den Planer konsistent
/// zum „Nächste Fahrt"-Banner, das ab mittags nach vorn blickt ([nextRide]).
/// Nachtragen geht danach weiter über den Eintragen-Knopf und die Historie —
/// wie bisher am Wochenende.
List<DateTime> planningWeek([DateTime? today]) {
  final now = today ?? DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  // `now.hour` VOR der Tages-Normalisierung lesen — `base` trägt keine
  // Uhrzeit mehr.
  final nextWeek =
      base.weekday >= DateTime.saturday ||
      (base.weekday == DateTime.friday && now.hour >= 12);
  final monday = nextWeek
      ? base.add(Duration(days: DateTime.monday + 7 - base.weekday))
      : base.subtract(Duration(days: base.weekday - DateTime.monday));
  return [for (var i = 0; i < 5; i++) monday.add(Duration(days: i))];
}

/// Der Tag, um den es als Nächstes geht — für das Banner auf der Übersicht
/// (#122).
///
/// Der erste Tag ab heute, an dem überhaupt jemand verfügbar ist und für den
/// noch **keine** Fahrt eingetragen ist. Ist die heutige Fahrt eingetragen,
/// rückt das Banner auf den Folgetag — `confirmed` bleibt das primäre
/// Signal, die Auskunft der Gruppe selbst. Seit #131 blickt das Banner
/// zusätzlich **ab 12 Uhr** nach vorn: Der Vormittag gehört der heutigen
/// Fahrt, der Nachmittag der morgigen. Der Wechsel greift beim nächsten
/// Rebuild (App-Start, Reload), nicht live im offenen Tab — bewusst kein
/// Timer.
///
/// Weil [planningWeek] ab Freitagmittag die kommende Woche liefert, steht
/// dann schon der Montag hier. Das ist gewollt: gefragt war die nächste
/// Fahrt, nicht „morgen" — sonst bliebe das Banner am Wochenende leer.
PlannedDay? nextRide(List<PlannedDay> week, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (final day in week) {
    final date = DateTime(day.date.year, day.date.month, day.date.day);
    if (date.isBefore(today)) continue;
    // Ab mittags gilt der Blick dem nächsten Tag (#131).
    if (date == today && now.hour >= 12) continue;
    if (day.confirmed) continue;
    if (day.availableIds.isEmpty) continue;
    return day;
  }
  return null;
}

/// Das Auto, in dem [personId] an [day] sitzt — `null`, wenn in keinem.
///
/// Eine Stelle für eine Frage, die drei Schirme und der Versand stellen: der
/// Planer für die Auto-Marke (#183), `dayDigestFor`/`composeBody` für „bist du
/// überhaupt dabei", und der Ausgangskorb für die Zeit, die für dich gilt.
/// Dreimal nachgebaut wäre sie dreimal verschieden zu beantworten.
PlannedCar? carOf(PlannedDay day, String personId) {
  for (final car in day.cars) {
    if (car.carries(personId)) return car;
  }
  return null;
}

/// Der **Index** desselben Autos, 0-basiert — für alles, was die Autos
/// durchzählt oder einfärbt.
int? carIndexOf(PlannedDay day, String personId) {
  for (final (i, car) in day.cars.indexed) {
    if (car.carries(personId)) return i;
  }
  return null;
}

/// Die **wirksamen Pins** eines Tages, in `decided_at`-Reihenfolge (#189).
///
/// Gültig ist nur, was zu den aktuellen [carDefaults] passt und zu jemandem
/// gehört, der an dem Tag überhaupt kann ([isAvailable]) — die Verwaisten-Regel
/// aus `plan_car_defaults`, hier für Zusagen.
///
/// **Je Person höchstens einer, nämlich der zuletzt getroffene.** Ein Mensch
/// sitzt in einem Auto; von zwei Zusagen kann also nur eine gelten. Ohne diese
/// Zeile gewänne die **ältere**: [planWeek] setzt Pins in `decided_at`-Folge
/// und überspringt, wer schon sitzt. Wer sein Auto wechselt (#199), bliebe
/// damit im alten — der Tipp täte sichtbar nichts, dieselbe Klasse wie der tote
/// „Ich möchte fahren"-Pin aus v0.66.1.
///
/// Aufgeräumt wird auch hier nichts: Die überholte Zeile bleibt stehen und
/// wirkt einfach nicht mehr.
List<SeatChoice> seatPinsOf(
  Iterable<SeatChoice> choices,
  Map<String, GroupDefaults> carDefaults, {
  required bool Function(String personId) isAvailable,
}) {
  final latest = <String, SeatChoice>{};
  for (final choice in choices) {
    // **Nur „ja unbedingt" pinnt** (#210). Das ist der Unterschied zu
    // v0.71.0, wo Schweigen als Zusage abgelegt wurde und damit festhielt:
    // „Egal" heißt jetzt wörtlich egal, die Verteilung entscheidet. Über
    // `accepted` geprüft wäre es weiter ein Pin — die Spalte ist seit #210
    // nur noch die Mitschrift für alte Clients und sagt „nicht abgelehnt",
    // nicht „hierher".
    if (choice.answer != SeatAnswer.yes) continue;
    if (!isAvailable(choice.personId)) continue;
    if (!choice.isCurrentFor(termsOf(carDefaults[choice.driverId]))) continue;
    final held = latest[choice.personId];
    if (held == null || choice.decidedAt.isAfter(held.decidedAt)) {
      latest[choice.personId] = choice;
    }
  }
  // **Wer zuerst gepinnt hat, bleibt** (entschieden 07.08.): Bei einem
  // übervollen Auto entscheidet `decided_at`. Der Nachrang fällt in die
  // automatische Verteilung, nicht aus dem Tag.
  return latest.values.toList()..sort((a, b) {
    final byTime = a.decidedAt.compareTo(b.decidedAt);
    return byTime != 0 ? byTime : a.personId.compareTo(b.personId);
  });
}

/// Wie viele Plätze ein **neuer** Pin von [personId] auf das Auto von
/// [driverId] noch vorfindet (#199) — 0 oder weniger heißt „voll".
///
/// Spiegelt genau die Bedingung, unter der [planWeek] einen Pin setzt: Ein Pin
/// greift nur auf einen **freien** Platz, und Pins laufen vor der automatischen
/// Verteilung. Automatisch zugeteilte Mitfahrer blockieren deshalb nicht — sie
/// werden hinterher neu verteilt; was blockiert, sind die schon **fest
/// zugesagten** Plätze. Ein neuer Pin ist der jüngste, steht also hinter allen
/// bestehenden.
///
/// Ohne diese eine Stelle stünde die Frage „passt da noch jemand rein" zweimal
/// verschieden im Code: einmal hier, einmal in der Verteilung. Der Screen
/// sperrte dann Autos, in die man gekonnt hätte — oder ließe Tipps zu, die
/// nichts bewirken.
int freeSeatsForPin(
  PlannedDay day, {
  required String driverId,
  required String personId,
  required Map<String, Person> persons,
  required Iterable<SeatChoice> choices,
  required Map<String, GroupDefaults> carDefaults,
}) {
  final seats = persons[driverId]?.seats ?? defaultSeats;
  final taken =
      seatPinsOf(
        choices,
        carDefaults,
        isAvailable: day.availableIds.contains,
      ).where(
        (pin) =>
            pin.driverId == driverId &&
            pin.personId != personId &&
            // Ein Fahrer sitzt in seinem eigenen Auto; sein Pin auf ein fremdes
            // verfällt in `planWeek` und darf hier keinen Platz belegen.
            !day.driverIds.contains(pin.personId),
      );
  return seats - 1 - taken.length;
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
