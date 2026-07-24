/// plan_soak_test.dart – Langzeit-Validierung der Planer-Automatik (#62).
///
/// Kurze Szenario-Tests können Drift und Schwingen nicht sehen. Hier werden
/// je Szenario 400 Wochen (≈ 2000 Arbeitstage) deterministisch gewürfelte
/// Verfügbarkeiten geplant und der Vorschlag JEDE Woche unverändert gebucht
/// — exakt wie der Bestätigen-Flow (`_confirmSplit`: je `PlannedCar` eine
/// Fahrt, Fahrer → driver, Rest → passenger/oneWay). Kein Übersteuern:
/// Validiert wird die reine Automatik.
///
/// Fünf Szenarien, vom Zielbild bis zur Grenze:
///
/// * **Zielflotte** (das Leit-Szenario, 2026-07-24 von Marcus als
///   Akzeptanz-Maßstab gesetzt): Flotte 1×4 / 6×5 / 1×7 Sitze, Tagesgrößen
///   und Anwesenheits-Gewichte exakt aus dem echten DaciaRacing-Protokoll
///   gemessen (401 Fahrt-Tage: 2er 40 %, 3er 33 %, 4er 20 %, 5er 5,5 %,
///   6er 1 %, nie 7/8). Ergebnis: Punkte-Ziel klar erfüllt (±2), Raten im
///   Mittel im ±2-pp-Ziel, Worst-Case ±2,7 pp — der strukturelle Boden:
///   Selten Anwesende sind (real wie simuliert) eher an GROSSEN Tagen
///   dabei, fahren also voller und bei gleichen Punkten seltener. Die
///   Kontrolle „gleicher Würfel, lauter 5-Sitzer" reißt ±2 pp genauso;
///   die echte, von Menschen geplante Gruppe liegt bei ±5 pp.
/// * **Realflotte** (ältere Kalibrierung mit deutlich mehr großen Tagen:
///   Ø ~3,3 Anwesende bei Tagen mit ≥ 2, P(5) ≈ 9 %, P(≥6) ≈ 3 %; Autos
///   4/4/4/4/5/5/5/7): Das Punkte-Ziel wird KLAR erfüllt — alle Endstände
///   nach 2000 Tagen innerhalb ±2 Punkten. Das Raten-Ziel
///   (±2 Prozentpunkte) reißt der 7-Sitzer strukturell (−8,8 pp):
///   punkte-fair heißt, er fährt seltener, aber voller —
///   Rate ≈ 1/(1 + Ø Mitgenommene je eigener Fahrt), und die hängt an
///   der Autogröße. Gleiche Punkte UND gleiche Raten sind bei DIESER
///   Groß-Tage-Häufigkeit mathematisch nicht gleichzeitig zu haben; bei
///   der echten (Zielflotte) sehr wohl.
/// * **Kontrolle** (identische Anwesenheit, alle Autos 5 Sitze): erfüllt
///   BEIDE Ziele — Raten innerhalb ±1 pp. Das isoliert die Autogröße als
///   einzige Ursache der Raten-Spreizung und verankert Marcus'
///   Akzeptanzziel dort, wo es erreichbar ist.
/// * **Alltag** (synthetisch, mit 2-/3-Sitzern): Punkte konvergieren nur
///   innerhalb vergleichbarer Autogrößen; zwischen den Kohorten driftet
///   es unbegrenzt.
/// * **Dauervoll** (Ø ~6 von 8 anwesend, nur EIN 7-Sitzer): Der Sitzfilter
///   qualifiziert fast täglich nur den Bus-Besitzer — die Spreizung
///   wächst OHNE SCHRANKE. Dokumentierte Systemgrenze, kein Zielbild:
///   Der Punkte-Vorrang kann nur zwischen QUALIFIZIERTEN wählen. Wer
///   Sitzfilter, Rückfalllinie oder Ein-Auto-Regel anfasst, sieht diese
///   Zahlen wandern und weiß, was er tut (Kontext: Issue #62).
///
/// Der Datensatz kommt aus einem eigenen, winzigen PRNG mit festem Seed —
/// bewusst nicht `dart:math` `Random(seed)`, dessen Folge über VM-Versionen
/// nicht garantiert ist. So ist er „einmal erstellt und für immer gleich",
/// ohne als Datei im Repo zu liegen. Würfel-Reihenfolge (Tag, dann Person
/// alphabetisch) ist Teil des Vertrags: Wer sie ändert, erzeugt einen
/// anderen Datensatz und kalibriert die gepinnten Werte neu.
library;

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/models/app_settings.dart';
import 'package:fahrgemeinschaft/models/plan_ride.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = AppSettings();
const _weeks = 400;

/// Realflotte (Marcus, 2026-07-24): jeder mindestens 4 Sitze, teils 5,
/// einer 7 — Sitze inkl. Fahrer, wie `persons.seats`.
const _realSeats = {
  'p1': 4,
  'p2': 4,
  'p3': 4,
  'p4': 4,
  'p5': 5,
  'p6': 5,
  'p7': 5,
  'p8': 7,
};

/// Anwesenheit der Realflotte, kalibriert auf die Empirie der Gruppe:
/// Ø ~3,3 bei Tagen mit ≥ 2 Anwesenden, 5er-Tage ~9 %, ≥6 nur ~3 %.
const _realAvailability = {
  'p1': 0.50,
  'p2': 0.45,
  'p3': 0.45,
  'p4': 0.40,
  'p5': 0.35,
  'p6': 0.30,
  'p7': 0.25,
  'p8': 0.20,
};

/// Zielflotte (Marcus, 2026-07-24): 1 Auto mit 4 Sitzen, sechs mit 5,
/// eines mit 7 — Sitze inkl. Fahrer, wie `persons.seats`. Der 7-Sitzer
/// gehört dem viert-präsentesten Stammfahrer (in der Realgruppe die
/// Dacia Lodgy, die der Gruppe den Namen gibt); der 4-Sitzer bewusst dem
/// präsentesten — der härteste Fall, denn er ist am häufigsten da, wenn
/// der Sitzfilter ihn an 5er-Tagen aussortiert.
const _targetSeats = {
  'p1': 4,
  'p2': 5,
  'p3': 5,
  'p4': 7,
  'p5': 5,
  'p6': 5,
  'p7': 5,
  'p8': 5,
};

/// Anwesenheits-Gewichte = die gemessenen Quoten der acht aktivsten
/// Personen im DaciaRacing-Protokoll (401 Tage, 2023–2026), absteigend.
/// Gewichtete Ziehung OHNE Zurücklegen je Tag — die Marginalquoten
/// treffen die Empirie dadurch nur ungefähr, die Struktur (vier
/// Stammfahrer, langer Ausläufer) bleibt erhalten.
const _targetWeights = {
  'p1': 0.641,
  'p2': 0.594,
  'p3': 0.516,
  'p4': 0.469,
  'p5': 0.237,
  'p6': 0.170,
  'p7': 0.130,
  'p8': 0.075,
};

/// Tagesgrößen-Verteilung, kumuliert — ebenfalls gemessen (jeder
/// Sim-Tag ist ein Fahrt-Tag, Tage ohne gemeinsame Fahrt stehen auch im
/// echten Protokoll nicht): 2er 39,9 %, 3er 33,1 %, 4er 20,1 %,
/// 5er 5,5 %, 6er 1,0 %. Einen 7er-Tag gab es real nie; er ist mit
/// 0,4 % ≈ 1×/Jahr (Marcus' Obergrenze) trotzdem drin, ein 8er nicht.
const _targetSizeCum = [
  (2, 0.399),
  (3, 0.730),
  (4, 0.931),
  (5, 0.986),
  (6, 0.996),
  (7, 1.0),
];

/// One-Way-Quote der Zielflotte: real 57 von 1188 Teilnahmen ≈ 4,8 %.
const _targetOneWayP = 0.05;

/// Kontrolle: gleiche Anwesenheit, alle Autos gleich groß — isoliert die
/// Autogröße als Ursache der Raten-Spreizung.
const _uniformSeats = {
  'p1': 5,
  'p2': 5,
  'p3': 5,
  'p4': 5,
  'p5': 5,
  'p6': 5,
  'p7': 5,
  'p8': 5,
};

/// Synthetische Stress-Flotte (vom 2-Sitzer bis zum Bus).
const _seats = {
  'p1': 2,
  'p2': 3,
  'p3': 3,
  'p4': 4,
  'p5': 5,
  'p6': 5,
  'p7': 5,
  'p8': 7,
};

/// Alltag: Ø ~3,5 Anwesende — fast immer reicht mehr als ein Auto,
/// der Sitzfilter bindet selten. Hier MUSS die Fairness konvergieren.
const _relaxedAvailability = {
  'p1': 0.70,
  'p2': 0.60,
  'p3': 0.50,
  'p4': 0.45,
  'p5': 0.40,
  'p6': 0.35,
  'p7': 0.30,
  'p8': 0.25,
};

/// Dauervoll: Ø ~6,1 Anwesende — fast täglich qualifiziert nur der
/// 7-Sitzer als Ein-Auto-Lösung.
const _crowdedAvailability = {
  'p1': 0.95,
  'p2': 0.85,
  'p3': 0.60,
  'p4': 0.75,
  'p5': 0.90,
  'p6': 0.55,
  'p7': 0.80,
  'p8': 0.70,
};

/// Wer da ist, ist gelegentlich nur eine Richtung dabei.
const _oneWayP = 0.15;

/// Xorshift32 — 10 Zeilen, plattform- und versionsstabil.
class _Rng {
  _Rng(this._state) : assert(_state != 0);
  int _state;

  double next() {
    var x = _state;
    x = (x ^ (x << 13)) & 0xFFFFFFFF;
    x = x ^ (x >>> 17);
    x = (x ^ (x << 5)) & 0xFFFFFFFF;
    _state = x;
    return x / 0x100000000;
  }
}

Map<DateTime, Map<String, PlanRide>> _rollWeek(
  _Rng rng,
  List<DateTime> days,
  Iterable<String> persons,
  Map<String, double> availabilityP,
) {
  return {
    for (final day in days)
      day: {
        for (final person in persons)
          if (rng.next() < availabilityP[person]!)
            person: rng.next() < _oneWayP ? PlanRide.oneWay : PlanRide.full,
      },
  };
}

/// Zielflotte-Würfel: erst die TAGESGRÖSSE aus der gemessenen Verteilung,
/// dann gewichtet ohne Zurücklegen, WER dabei ist. Würfel-Reihenfolge ist
/// Teil des PRNG-Vertrags: je Tag 1 Wurf Größe, dann je Auswahl 1 Wurf,
/// zuletzt je gewählter Person (in Auswahl-Reihenfolge) 1 Wurf One-Way.
Map<DateTime, Map<String, PlanRide>> _rollWeekSized(
  _Rng rng,
  List<DateTime> days,
  List<String> persons,
) {
  final result = <DateTime, Map<String, PlanRide>>{};
  for (final day in days) {
    final u = rng.next();
    var size = _targetSizeCum.last.$1;
    for (final (n, cum) in _targetSizeCum) {
      if (u < cum) {
        size = n;
        break;
      }
    }

    final pool = [...persons];
    final chosen = <String>[];
    while (chosen.length < size && pool.isNotEmpty) {
      final total = pool.fold(0.0, (a, p) => a + _targetWeights[p]!);
      var t = rng.next() * total;
      var pick = pool.last;
      for (final p in pool) {
        t -= _targetWeights[p]!;
        if (t < 0) {
          pick = p;
          break;
        }
      }
      pool.remove(pick);
      chosen.add(pick);
    }

    result[day] = {
      for (final p in chosen)
        p: rng.next() < _targetOneWayP ? PlanRide.oneWay : PlanRide.full,
    };
  }
  return result;
}

/// Eine geplante Woche exakt wie der Bestätigen-Flow buchen.
List<Trip> _bookWeek(int week, List<PlannedDay> plan) {
  return [
    for (final day in plan)
      for (final (i, car) in day.cars.indexed)
        Trip(
          id: 'soak-w$week-${day.date.toIso8601String()}-c$i',
          date: day.date,
          participations: {
            car.driverId: ParticipationStatus.driver,
            for (final id in car.fullIds) id: ParticipationStatus.passenger,
            for (final id in car.oneWayIds) id: ParticipationStatus.oneWay,
          },
        ),
  ];
}

double _spread(Map<String, PersonStats> stats, Iterable<String> persons) {
  final points = [for (final p in persons) stats[p]?.points ?? 0.0];
  points.sort();
  return points.last - points.first;
}

/// Ergebnis eines Simulationslaufs — alles, was die Tests pinnen.
class _SoakResult {
  final int totalTrips;
  final int soloTrips;
  final double spreadAt100;
  final double spreadAtEnd;
  final double maxLateSpread;
  final double pointsSum;
  final Map<String, double> points;
  final Map<String, int> sharePermille;

  _SoakResult({
    required this.totalTrips,
    required this.soloTrips,
    required this.spreadAt100,
    required this.spreadAtEnd,
    required this.maxLateSpread,
    required this.pointsSum,
    required this.points,
    required this.sharePermille,
  });

  @override
  String toString() =>
      'Fahrten: $totalTrips (solo: $soloTrips)\n'
      'Spread @100W: ${spreadAt100.toStringAsFixed(2)} · '
      '@400W: ${spreadAtEnd.toStringAsFixed(2)} · '
      'max letztes Viertel: ${maxLateSpread.toStringAsFixed(2)}\n'
      'Punkte: ${points.map((k, v) => MapEntry(k, v.toStringAsFixed(1)))}\n'
      'Fahranteil-Abweichung (‰): $sharePermille';
}

/// Würfelt die Verfügbarkeiten einer Woche für [_simulateWith].
typedef _Roller =
    Map<DateTime, Map<String, PlanRide>> Function(
      _Rng rng,
      List<DateTime> days,
      List<String> persons,
    );

_SoakResult _simulate(
  int seed,
  Map<String, int> seats,
  Map<String, double> availabilityP,
) => _simulateWith(
  seed,
  seats,
  (rng, days, persons) => _rollWeek(rng, days, persons, availabilityP),
);

_SoakResult _simulateWith(int seed, Map<String, int> seats, _Roller roll) {
  final persons = seats.keys.toList();
  final rng = _Rng(seed);
  final trips = <Trip>[];
  final weeklySpread = <double>[];
  Map<String, PersonStats> stats = const {};

  for (var week = 0; week < _weeks; week++) {
    // Datumsarithmetik über Tag-Komponenten, nie über Duration: Ein
    // Duration-Tag über die Zeitumstellung hinweg wiederholte ein Datum.
    final monday = DateTime(2026, 1, 5 + week * 7);
    final days = [
      for (var d = 0; d < 5; d++)
        DateTime(monday.year, monday.month, monday.day + d),
    ];

    final plan = planWeek(
      dates: days,
      availability: roll(rng, days, persons),
      overrides: const {},
      trips: trips,
      settings: _settings,
      seats: seats,
    );
    trips.addAll(_bookWeek(week, plan));

    stats = computeStats(trips, _settings);
    weeklySpread.add(_spread(stats, persons));
  }

  final lateSpread = weeklySpread.sublist(_weeks * 3 ~/ 4);
  final totalDriven = persons.fold(0, (a, p) => a + stats[p]!.driven);
  final totalDays = persons.fold(0, (a, p) => a + stats[p]!.participationDays);
  final meanShare = totalDriven / totalDays;

  return _SoakResult(
    totalTrips: trips.length,
    soloTrips: trips.where((t) => t.participations.length == 1).length,
    spreadAt100: weeklySpread[99],
    spreadAtEnd: weeklySpread.last,
    maxLateSpread: lateSpread.fold(0.0, (a, b) => a > b ? a : b),
    pointsSum: persons.fold(0.0, (a, p) => a + stats[p]!.points),
    points: {for (final p in persons) p: stats[p]!.points},
    sharePermille: {
      for (final p in persons)
        p: ((stats[p]!.driveShare - meanShare) * 1000).round(),
    },
  );
}

void main() {
  test('der Datensatz ist deterministisch (PRNG-Vertrag)', () {
    final a = _Rng(0xC0FFEE);
    final b = _Rng(0xC0FFEE);
    for (var i = 0; i < 10000; i++) {
      expect(a.next(), b.next(), reason: 'Gleicher Seed, gleiche Folge.');
    }
  });

  test(
    'Zielflotte: Punkte im Ziel, Raten am strukturellen Boden',
    () {
      final r = _simulateWith(0xDAC1A, _targetSeats, _rollWeekSized);
      printOnFailure('$r');

      expect(r.pointsSum, closeTo(0, 1e-6), reason: 'Punkte sind nullsummig.');

      for (final p in _targetSeats.keys) {
        // Marcus' erstes Ziel: Punktedifferenzen um 0 — klar erfüllt
        // (beobachtet ±2 auf dem Haupt-Seed).
        expect(
          r.points[p]!.abs(),
          lessThan(5),
          reason: 'Endstand $p muss um 0 pendeln (Punkte-Ziel).',
        );
        // Marcus' zweites Ziel: Fahrraten ±2 pp. Ø-Abweichung liegt im
        // Ziel; die Schranke hier ist der gemessene strukturelle BODEN
        // (±3 pp, Worst-Case über 10 Seeds): Wer an kleinen Tagen dabei
        // ist, fährt bei gleichen Punkten zwangsläufig öfter — die
        // Kontrolle mit lauter 5-Sitzern reißt ±2 pp genauso (22 ‰).
        // Kein Fahrerwahl-Mechanismus kann darunter; Details im Report
        // `doc/entscheidung-mitfahrer-verteilung.md`, Nachtrag 3.
        expect(
          r.sharePermille[p]!.abs(),
          lessThanOrEqualTo(30),
          reason:
              'Fahrrate $p muss am strukturellen Boden (±3 pp) bleiben '
              '(Akzeptanz Marcus, 2026-07-24).',
        );
      }
      expect(
        r.maxLateSpread,
        lessThan(25),
        reason: 'Auch zwischendrin bleibt die Spreizung klein.',
      );

      // Exakte Regressions-Pins (Datensatz ist deterministisch).
      expect(r.totalTrips, 2003);
      expect(r.soloTrips, 0);
      expect(r.spreadAt100, closeTo(3.0, 1e-9));
      expect(r.spreadAtEnd, closeTo(3.0, 1e-9));
      expect(r.maxLateSpread, closeTo(7.5, 1e-9));
      expect(r.sharePermille['p4'], -27, reason: 'Bus: seltener, aber voller.');
      expect(r.points['p4'], closeTo(2.0, 1e-9));

      // Robustheit: neun weitere Seeds nur gegen die Ziele (beobachtet:
      // Punkte ≤ 5,5 · Raten ≤ 27 ‰ — Haupt-Seed ist der Worst-Case).
      for (final seed in [
        0xBEEF01,
        0x5EED02,
        0x5EED03,
        0x5EED04,
        0x5EED05,
        0x5EED06,
        0x5EED07,
        0x5EED08,
        0x5EED09,
      ]) {
        final rr = _simulateWith(seed, _targetSeats, _rollWeekSized);
        for (final p in _targetSeats.keys) {
          expect(
            rr.points[p]!.abs(),
            lessThan(7),
            reason: 'Seed $seed: Endstand $p muss um 0 pendeln.',
          );
          expect(
            rr.sharePermille[p]!.abs(),
            lessThanOrEqualTo(30),
            reason: 'Seed $seed: Fahrrate $p muss am Boden (±3 pp) bleiben.',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'Realflotte: Punkte-Ziel erfüllt, Raten-Ziel reißt der Bus',
    () {
      final r = _simulate(0xFAB42, _realSeats, _realAvailability);
      printOnFailure('$r');

      expect(r.pointsSum, closeTo(0, 1e-6), reason: 'Punkte sind nullsummig.');

      // Marcus' erstes Ziel (2026-07-24): Punktedifferenzen konvergieren
      // um 0. Deutlich erfüllt — nach 2000 Tagen liegt JEDER Endstand
      // innerhalb ±5 Punkten (beobachtet: ±2), die Spreizung ist stationär.
      for (final p in _realSeats.keys) {
        expect(
          r.points[p]!.abs(),
          lessThan(5),
          reason: 'Endstand $p muss um 0 pendeln (Punkte-Ziel).',
        );
      }
      expect(
        r.maxLateSpread,
        lessThan(25),
        reason: 'Auch zwischendrin bleibt die Spreizung klein.',
      );

      // Marcus' zweites Ziel — Fahrraten ±2 Prozentpunkte — wird bei
      // GEMISCHTER Flotte strukturell verfehlt, am stärksten vom 7-Sitzer:
      // Rate ≈ 1/(1 + Ø Mitgenommene je eigener Fahrt); punkte-fair fährt
      // der Bus seltener, aber voller. Kein Planer-Fehler, sondern
      // Arithmetik — die Kontrolle darunter beweist es. Dokumentiert, damit
      // niemand versucht, beide Ziele gleichzeitig „hinzutunen".
      expect(
        r.sharePermille['p8'],
        lessThan(-50),
        reason: 'Der 7-Sitzer fährt punkte-fair deutlich seltener je Tag.',
      );

      // Exakte Regressions-Pins (Datensatz ist deterministisch).
      expect(r.totalTrips, 1945);
      expect(r.soloTrips, 205);
      expect(r.spreadAt100, closeTo(9.5, 1e-9));
      expect(r.spreadAtEnd, closeTo(4.0, 1e-9));
      expect(r.maxLateSpread, closeTo(18.5, 1e-9));
      expect(r.sharePermille['p8'], -88);
      expect(r.points['p8'], closeTo(0.5, 1e-9));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Kontrolle: gleiche Autos — BEIDE Ziele erfüllt',
    () {
      final r = _simulate(0xFAB42, _uniformSeats, _realAvailability);
      printOnFailure('$r');

      expect(r.pointsSum, closeTo(0, 1e-6), reason: 'Punkte sind nullsummig.');

      // Identische Anwesenheits-Würfel wie die Realflotte, nur die Autos
      // sind gleich groß: Jetzt hält der Planer auch das Raten-Ziel
      // (±2 Prozentpunkte = ±20 ‰). Die Raten-Spreizung der Realflotte
      // kommt also vollständig aus der Autogrößen-Mischung.
      for (final p in _uniformSeats.keys) {
        expect(
          r.sharePermille[p]!.abs(),
          lessThanOrEqualTo(20),
          reason:
              'Fahrrate $p muss im ±2-Prozentpunkte-Ziel liegen '
              '(Akzeptanzziel Marcus, 2026-07-24).',
        );
        expect(
          r.points[p]!.abs(),
          lessThan(5),
          reason: 'Und die Punkte pendeln weiter um 0.',
        );
      }

      // Exakte Regressions-Pins.
      expect(r.totalTrips, 1968);
      expect(r.soloTrips, 205);
      expect(r.spreadAt100, closeTo(3.5, 1e-9));
      expect(r.spreadAtEnd, closeTo(3.5, 1e-9));
      expect(r.maxLateSpread, closeTo(6.0, 1e-9));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Alltag: Kohorten konvergieren, Kapazitäts-Gefälle dokumentiert',
    () {
      final r = _simulate(0xC0FFEE, _seats, _relaxedAvailability);
      printOnFailure('$r');

      expect(r.pointsSum, closeTo(0, 1e-6), reason: 'Punkte sind nullsummig.');

      // Der Kern der Fairness: Unter Gleich-Kapablen bleiben die Punkte über
      // 2000 Tage BEIEINANDER. Schaukelte der Raten-Trim (I-Anteil!) oder
      // kippte der Punkte-Vorrang, explodierten diese Kohorten-Spreizungen.
      final bigCohort = [
        for (final p in ['p4', 'p5', 'p6', 'p7', 'p8']) r.points[p]!,
      ]..sort();
      expect(
        bigCohort.last - bigCohort.first,
        lessThan(40),
        reason:
            'p4–p8 können fast jeden Tag fahren — zwischen ihnen muss die '
            'Fairness ausgleichen (beobachtet: ~28 Punkte auf 2000 Tage).',
      );
      final threeSeaters = [r.points['p2']!, r.points['p3']!]..sort();
      expect(
        threeSeaters.last - threeSeaters.first,
        lessThan(15),
        reason: 'Auch die beiden 3-Sitzer bleiben beieinander (~5,5 Punkte).',
      );

      // Dokumentierte Systemgrenze, KEIN Zielbild: ZWISCHEN den Kohorten
      // driftet es, weil der Sitzfilter den 2-Sitzer fast nie fahren lässt —
      // er nimmt ehrlich mehr, als er gibt, und sinkt unbegrenzt. Schlägt
      // diese Erwartung eines Tages fehl, hat jemand Sitzfilter, Rückfall-
      // linie oder Ein-Auto-Regel verändert: Zahlen bewusst neu kalibrieren
      // (Kontext: Issue #62).
      expect(
        r.spreadAtEnd,
        greaterThan(r.spreadAt100 * 2),
        reason: 'Kapazitäts-Gefälle: globale Spreizung wächst mit der Zeit.',
      );

      // Exakte Regressions-Pins (Datensatz ist deterministisch).
      expect(r.totalTrips, 2070);
      expect(r.soloTrips, 85);
      expect(r.spreadAt100, closeTo(289.5, 1e-9));
      expect(r.spreadAtEnd, closeTo(1140.0, 1e-9));
      expect(r.points['p1'], closeTo(-831.0, 1e-9));
      expect(r.sharePermille['p1'], -115);
      expect(r.sharePermille['p8'], 51);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'Dauervoll: der strukturelle Bus-Bias, beziffert',
    () {
      final r = _simulate(0x5EED5, _seats, _crowdedAvailability);
      printOnFailure('$r');

      expect(r.pointsSum, closeTo(0, 1e-6), reason: 'Punkte sind nullsummig.');

      // Bei Ø ~6 Anwesenden qualifiziert der Sitzfilter fast täglich NUR den
      // 7-Sitzer für die Ein-Auto-Lösung — der Punkte-Vorrang kann nichts
      // ausgleichen, weil er nur zwischen Qualifizierten wählt. Der Bus-
      // Besitzer fährt dauerhaft ~45 % über dem Schnitt und sammelt
      // unbegrenzt Punkte. Dokumentierte Grenze, kein Zielbild.
      expect(
        r.sharePermille['p8'],
        greaterThan(300),
        reason: 'Der einzige Bus fährt fast immer.',
      );
      expect(
        r.spreadAtEnd,
        greaterThan(r.spreadAt100 * 2),
        reason: 'Ohne kapable Alternative wächst die Spreizung unbegrenzt.',
      );

      // Exakte Regressions-Pins.
      expect(r.totalTrips, 2679);
      expect(r.soloTrips, 0);
      expect(r.spreadAt100, closeTo(1270.5, 1e-9));
      expect(r.spreadAtEnd, closeTo(5131.5, 1e-9));
      expect(r.points['p8'], closeTo(4187.0, 1e-9));
      expect(r.sharePermille['p8'], 448);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
