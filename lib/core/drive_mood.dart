/// drive_mood.dart – Fahranteil als Gesicht.
///
/// Seit Issue #38 steuert der Fahranteil die Reihenfolge nicht mehr; er ist
/// reine Anzeige. Als Gesicht sagt er das, worum es geht — musstest du zuletzt
/// viel fahren oder wenig? Die Prozentzahl steht zusätzlich in der Zeile.
///
/// Reine Zuordnung ohne Widget, damit die Schwellen testbar bleiben —
/// dieselbe Trennung wie `chart_data.dart` ↔ `widgets/charts.dart`. Gezeichnet
/// wird in `widgets/mood_face.dart`.
library;

import 'mood.dart';

/// Die Skala von zufrieden nach unzufrieden. Reihenfolge ist bedeutungstragend:
/// [driveMoodOf] interpoliert über genau diese Liste.
const _scale = [
  Mood.ecstatic,
  Mood.happy,
  Mood.good,
  Mood.neutral,
  Mood.meh,
  Mood.sad,
  Mood.angry,
];

/// Spannweite der Fahranteile in der Gruppe — die Bezugsgröße der Gesichter.
///
/// Bewusst Spannweite statt fester Prozentgrenzen: In einer Fünfergruppe fährt
/// jeder im Schnitt 20 % seiner Tage, in einer Zweiergruppe 50 %. Feste Grenzen
/// würden die Gruppengröße messen statt die Verteilung.
class DriveShareRange {
  const DriveShareRange({required this.lowest, required this.highest});

  factory DriveShareRange.of(Iterable<double> shares) {
    final list = shares.toList();
    if (list.isEmpty) return const DriveShareRange(lowest: 0, highest: 0);
    var lowest = list.first;
    var highest = list.first;
    for (final share in list) {
      if (share < lowest) lowest = share;
      if (share > highest) highest = share;
    }
    return DriveShareRange(lowest: lowest, highest: highest);
  }

  final double lowest;
  final double highest;

  /// Kein Abstand zwischen niedrigstem und höchstem Anteil — etwa wenn alle
  /// gleich viel fahren oder nur eine Person in der Liste steht.
  bool get isFlat => highest - lowest < 1e-9;
}

/// Das Gesicht zum Fahranteil: der **niedrigste** Anteil der Gruppe bekommt
/// das glücklichste Gesicht, der **höchste** das traurigste, dazwischen wird
/// linear über die sieben Stufen interpoliert.
///
/// Ist die Spannweite leer ([DriveShareRange.isFlat]), bekommen alle
/// [Mood.neutral]: Ohne Abstand gibt es nichts zu interpolieren, und jemanden
/// zum Traurigsten zu erklären, weil er einen Hauch über den anderen liegt,
/// wäre eine erfundene Aussage.
///
/// [Mood.celebrating] kommt hier nie heraus — es ist keine Bewertungsstufe.
Mood driveMoodOf(double share, DriveShareRange range) {
  if (range.isFlat) return Mood.neutral;
  final t = (share - range.lowest) / (range.highest - range.lowest);
  final index = (t.clamp(0.0, 1.0) * (_scale.length - 1)).round();
  return _scale[index];
}

/// Vorlesetext für Screenreader — ein Gesicht allein sagt dort nichts.
/// Enthält den Prozentwert, damit die Zahl auch ohne die Zeile daneben
/// verfügbar ist.
String driveMoodLabel(Mood mood, double share) {
  final percent = (share * 100).round();
  final wie = switch (mood) {
    Mood.ecstatic => 'fährt am seltensten in der Gruppe',
    Mood.happy => 'fährt deutlich seltener als die anderen',
    Mood.good => 'fährt etwas seltener als die anderen',
    Mood.neutral => 'fährt etwa wie die anderen',
    Mood.meh => 'fährt etwas öfter als die anderen',
    Mood.sad => 'fährt deutlich öfter als die anderen',
    Mood.angry => 'fährt am häufigsten in der Gruppe',
    Mood.celebrating => 'fährt etwa wie die anderen',
  };
  return 'Fahranteil $percent % — $wie';
}
