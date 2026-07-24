/// plan_soak_test.dart – Langzeit-Validierung der Planer-Automatik (#62).
///
/// Kurze Szenario-Tests können Drift und Schwingen nicht sehen. Hier werden
/// je Szenario 400 Wochen (≈ 2000 Arbeitstage) deterministisch gewürfelte
/// Verfügbarkeiten geplant und der Vorschlag JEDE Woche unverändert gebucht
/// — exakt wie der Bestätigen-Flow (`_confirmSplit`: je `PlannedCar` eine
/// Fahrt, Fahrer → driver, Rest → passenger/oneWay). Kein Übersteuern:
/// Validiert wird die reine Automatik.
///
/// Zwei Szenarien, weil der erste Kalibrierungslauf einen echten Befund
/// lieferte:
///
/// * **Alltag** (Kapazität bindet selten): Punkte bleiben nullsummig und
///   beschränkt, die Fahranteile gleichen sich an — die Basislogik
///   (Punkte-Vorrang + gedeckelter Raten-Trim) konvergiert. Ein I-Anteil
///   oder Vorzeichenfehler schaukelte sich hier sichtbar auf.
/// * **Dauervoll** (Ø ~6 von 8 anwesend, nur EIN 7-Sitzer): Der Sitzfilter
///   qualifiziert fast täglich nur den Bus-Besitzer, „ein Auto, wann immer
///   eines reicht" zementiert ihn als Dauerfahrer — die Punkte-Spreizung
///   wächst OHNE SCHRANKE (struktureller Bus-Bias). Das ist kein Zielbild,
///   sondern eine dokumentierte Systemgrenze: Der Punkte-Vorrang kann nur
///   zwischen QUALIFIZIERTEN Kandidaten wählen. Wer Sitzfilter, Rückfall-
///   linie oder Ein-Auto-Regel anfasst, sieht diese Zahlen wandern und
///   weiß, was er tut (Kontext: Issue #62).
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

/// Sitze inkl. Fahrer (wie `persons.seats`): vom 2-Sitzer bis zum Bus.
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
  Map<String, double> availabilityP,
) {
  return {
    for (final day in days)
      day: {
        for (final person in _seats.keys)
          if (rng.next() < availabilityP[person]!)
            person: rng.next() < _oneWayP ? PlanRide.oneWay : PlanRide.full,
      },
  };
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

double _spread(Map<String, PersonStats> stats) {
  final points = [for (final p in _seats.keys) stats[p]?.points ?? 0.0];
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

_SoakResult _simulate(int seed, Map<String, double> availabilityP) {
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
      availability: _rollWeek(rng, days, availabilityP),
      overrides: const {},
      trips: trips,
      settings: _settings,
      seats: _seats,
    );
    trips.addAll(_bookWeek(week, plan));

    stats = computeStats(trips, _settings);
    weeklySpread.add(_spread(stats));
  }

  final lateSpread = weeklySpread.sublist(_weeks * 3 ~/ 4);
  final totalDriven = _seats.keys.fold(0, (a, p) => a + stats[p]!.driven);
  final totalDays = _seats.keys.fold(
    0,
    (a, p) => a + stats[p]!.participationDays,
  );
  final meanShare = totalDriven / totalDays;

  return _SoakResult(
    totalTrips: trips.length,
    soloTrips: trips.where((t) => t.participations.length == 1).length,
    spreadAt100: weeklySpread[99],
    spreadAtEnd: weeklySpread.last,
    maxLateSpread: lateSpread.fold(0.0, (a, b) => a > b ? a : b),
    pointsSum: _seats.keys.fold(0.0, (a, p) => a + stats[p]!.points),
    points: {for (final p in _seats.keys) p: stats[p]!.points},
    sharePermille: {
      for (final p in _seats.keys)
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
    'Alltag: Kohorten konvergieren, Kapazitäts-Gefälle dokumentiert',
    () {
      final r = _simulate(0xC0FFEE, _relaxedAvailability);
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
      final r = _simulate(0x5EED5, _crowdedAvailability);
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
