/// stats_insights.dart – die Insight-Karten der Statistik-Seite.
///
/// Jede Karte erzählt genau eine Zahl als Geschichte; die App findet die
/// Pointe, nicht der Nutzer. Reine Funktionen: Jeder Builder liefert `null`,
/// wenn seine Zahl nicht berechenbar ist — die Guards SIND die Schnittstelle,
/// eine Karte ohne belastbare Zahl erscheint nicht. Die Texte entstehen hier
/// fertig auf Deutsch (Muster `push_digest.dart`), damit Widgets nur noch
/// zeigen und Tests am String prüfen können.
library;

import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/trip.dart';
import 'chart_data.dart';
import 'fairness.dart';
import 'price_series.dart';
import 'stats_data.dart';

enum StatsInsightKind { distance, bestWeek, kmHero, streak }

class StatsInsight {
  const StatsInsight({
    required this.kind,
    required this.title,
    required this.value,
  });

  final StatsInsightKind kind;

  /// Die kleine Zeile über der Zahl („Strecken-Meilenstein").
  final String title;

  /// Die Geschichte selbst („2.870 km seid ihr zusammen gefahren — …").
  final String value;
}

/// Anschauungs-Strecken ab Süddeutschland, aufsteigend — grobe Werte, es
/// geht um die Vorstellung, nicht um Routenplanung.
const List<(int, String)> kDistanceMilestones = [
  (230, 'bis München'),
  (520, 'bis Wien'),
  (600, 'bis Berlin'),
  (1100, 'bis Rom'),
  (1300, 'bis Barcelona'),
  (2300, 'bis Lissabon'),
  (2800, 'ans Nordkap'),
];

/// Erdumfang und Mondentfernung — die Leiter oberhalb der Städte.
const int kEarthLapKm = 40075;
const int kMoonDistanceKm = 384400;

String _times(int n) => switch (n) {
  1 => 'einmal',
  2 => 'zweimal',
  3 => 'dreimal',
  _ => '$n-mal',
};

/// Gesamtstrecke der Gruppe als Vergleich.
///
/// Rechnet mit Personen-Kilometern (`PersonStats.kilometers`) — dieselbe
/// Zahl wie die Kachel „Personen-km" auf der Übersicht, keine zweite
/// Wahrheit. Die Formulierung „seid ihr zusammen gefahren" trägt das mit:
/// Drei Personen im selben Auto sammeln dreimal Strecke.
StatsInsight? distanceInsight(
  Map<String, PersonStats> stats,
  AppSettings settings,
) {
  final totalKm = stats.values.fold<double>(
    0,
    (sum, s) => sum + s.kilometers(settings),
  );
  String? comparison;
  if (totalKm >= kMoonDistanceKm) {
    comparison = '${_times(totalKm ~/ kMoonDistanceKm)} bis zum Mond';
  } else if (totalKm >= kEarthLapKm) {
    comparison = '${_times(totalKm ~/ kEarthLapKm)} um die Erde';
  } else {
    for (final (km, place) in kDistanceMilestones) {
      if (km <= totalKm) comparison = '${_times(1)} $place';
    }
  }
  if (comparison == null) return null;
  final km = NumberFormat('#,##0', 'de');
  return StatsInsight(
    kind: StatsInsightKind.distance,
    title: 'Strecken-Meilenstein',
    value:
        '${km.format(totalKm)} km seid ihr zusammen gefahren — '
        '$comparison.',
  );
}

/// Die Woche mit der größten Ersparnis — aus den Wochen-Differenzen der
/// kumulierten Gruppenkurve. Ohne Preisdaten gibt es keine Kurve und damit
/// keine Karte; das ist gewollt.
StatsInsight? bestWeekInsight(SavingsChart chart) {
  var bestIndex = -1;
  var bestDelta = 0.0;
  for (var i = 0; i < chart.group.length; i++) {
    final before = i == 0 ? chart.carriedOver : chart.group[i - 1];
    final delta = chart.group[i] - before;
    if (delta > bestDelta) {
      bestDelta = delta;
      bestIndex = i;
    }
  }
  if (bestIndex < 0) return null;
  final euro = NumberFormat.currency(locale: 'de', symbol: '€');
  final label = weekShortLabel(
    chart.weeks[bestIndex],
    reference: chart.weeks.last,
  );
  return StatsInsight(
    kind: StatsInsightKind.bestWeek,
    title: 'Sparsamste Woche',
    value: '$label: ${euro.format(bestDelta)} gespart — eure stärkste Woche.',
  );
}

const List<String> _monthNames = [
  'Januar',
  'Februar',
  'März',
  'April',
  'Mai',
  'Juni',
  'Juli',
  'August',
  'September',
  'Oktober',
  'November',
  'Dezember',
];

/// Wer im laufenden Monat am meisten am Steuer saß — Rückfall auf den
/// Vormonat, solange der laufende noch keinen Fahr-Tag hat (Monatsanfang).
StatsInsight? kmHeroInsight(
  List<Trip> trips,
  AppSettings settings,
  Map<String, String> names, {
  required DateTime now,
}) {
  StatsInsight? forMonth(int year, int month) {
    final driven = <String, int>{};
    for (final trip in trips) {
      if (isSoloTrip(trip)) continue;
      if (trip.date.year != year || trip.date.month != month) continue;
      if (trip.date.isAfter(now)) continue;
      final driver = trip.driverId;
      if (driver == null) continue;
      driven[driver] = (driven[driver] ?? 0) + 1;
    }
    if (driven.isEmpty) return null;
    final hero = driven.keys.reduce((a, b) {
      final byCount = driven[b]!.compareTo(driven[a]!);
      return byCount != 0
          ? (byCount < 0 ? a : b)
          : (a.compareTo(b) < 0 ? a : b);
    });
    final name = names[hero];
    if (name == null) return null;
    final km = NumberFormat('#,##0', 'de');
    final heroKm = driven[hero]! * settings.commuteKm * 2;
    return StatsInsight(
      kind: StatsInsightKind.kmHero,
      title: 'Kilometerheld · ${_monthNames[month - 1]}',
      value: '$name — ${km.format(heroKm)} km am Steuer. 🏆',
    );
  }

  final current = forMonth(now.year, now.month);
  if (current != null) return current;
  final previous = DateTime(now.year, now.month - 1);
  return forMonth(previous.year, previous.month);
}

/// Die längste Serie von Fahrtagen ohne Solo-Fahrt.
///
/// Gezählt werden TAGE MIT FAHRT in ihrer Reihenfolge — Kalenderlücken
/// (Wochenende, Ferien) brechen die Serie nicht, denn ein fahrfreier Tag
/// ist kein Scheitern. Ein Tag, an dem eine Solo-Fahrt steht, bricht sie.
/// Unter fünf Tagen ist eine Serie keine Geschichte.
StatsInsight? streakInsight(List<Trip> trips) {
  // Je Datum: qualifiziert, wenn KEINE seiner Fahrten solo war.
  final byDate = <DateTime, bool>{};
  for (final trip in trips) {
    final day = DateTime(trip.date.year, trip.date.month, trip.date.day);
    byDate[day] = (byDate[day] ?? true) && !isSoloTrip(trip);
  }
  if (byDate.isEmpty) return null;
  final days = byDate.keys.toList()..sort();

  var best = 0;
  var current = 0;
  for (final day in days) {
    if (byDate[day]!) {
      current++;
      if (current > best) best = current;
    } else {
      current = 0;
    }
  }
  if (best < 5) return null;
  final running = current == best;
  return StatsInsight(
    kind: StatsInsightKind.streak,
    title: 'Serien-Rekord',
    value: running
        ? '$best Fahrtage in Folge ohne Solo-Fahrt — die Serie läuft noch.'
        : '$best Fahrtage in Folge ohne Solo-Fahrt.',
  );
}

/// Wählt aus den verfügbaren Karten die der Woche — deterministisch: Der
/// Seed ist die ISO-Woche, kein Zufall, kein `DateTime.now()`. Dieselbe
/// Woche zeigt dieselben Karten, die nächste rückt weiter.
List<StatsInsight> rotateInsights(
  List<StatsInsight> available, {
  required DateTime now,
  int count = 2,
}) {
  if (available.length <= count) return List.of(available);
  final week = IsoWeek.of(now);
  final offset = (week.year * 100 + week.week) % available.length;
  return [
    for (var i = 0; i < count; i++) available[(offset + i) % available.length],
  ];
}
