/// drive_mood.dart – Fahranteil als Stimmung statt als Prozentzahl.
///
/// Seit Issue #38 steuert der Fahranteil die Reihenfolge nicht mehr; er ist
/// reine Anzeige. Eine nackte Prozentzahl neben Platz 1 las sich aber wie
/// ein Widerspruch („warum ist der mit 10 % dran?"). Ein Gesicht sagt das,
/// worum es geht: Musstest du zuletzt viel fahren oder wenig?
///
/// Reine Zuordnung ohne Widget, damit die Schwellen testbar bleiben —
/// dieselbe Trennung wie `chart_data.dart` ↔ `widgets/charts.dart`. Gezeichnet
/// wird in `widgets/mood_face.dart`.
library;

import 'mood.dart';

/// Die Stimmung wird **relativ zum Gruppenschnitt** bestimmt, nicht an
/// festen Prozentwerten.
///
/// Absolute Schwellen wären hier bedeutungslos: In einer Fünfergruppe fährt
/// jeder im Schnitt 20 % seiner Tage, in einer Zweiergruppe 50 %. Fest
/// verdrahtete Grenzen würden also die Gruppengröße messen statt die
/// Fairness — bei fünf Leuten strahlte immer die ganze Liste.
///
/// [share] und [averageShare] sind Anteile (0..1). Ohne gefahrene Tage in
/// der Gruppe ([averageShare] = 0) gibt es nichts zu vergleichen: dann
/// bekommen alle [Mood.neutral], statt aus 0 ÷ 0 ein Urteil zu erfinden.
///
/// [Mood.celebrating] kommt hier nie heraus — es ist keine Bewertungsstufe.
Mood driveMoodOf(double share, double averageShare) {
  if (averageShare <= 0) return Mood.neutral;
  final ratio = share / averageShare;
  if (ratio <= 0.45) return Mood.ecstatic;
  if (ratio <= 0.70) return Mood.happy;
  if (ratio <= 0.90) return Mood.good;
  if (ratio < 1.10) return Mood.neutral;
  if (ratio < 1.30) return Mood.meh;
  if (ratio < 1.60) return Mood.sad;
  return Mood.angry;
}

/// Durchschnittlicher Fahranteil der übergebenen Werte — die Bezugsgröße
/// für [driveMoodOf]. Leere Liste ⇒ 0.
double averageDriveShare(Iterable<double> shares) {
  final list = shares.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

/// Vorlesetext für Screenreader — ein Gesicht allein sagt dort nichts.
/// Enthält bewusst auch den Prozentwert: Die Zahl verschwindet aus der
/// Ansicht, soll aber zugänglich bleiben.
String driveMoodLabel(Mood mood, double share) {
  final percent = (share * 100).round();
  final wie = switch (mood) {
    Mood.ecstatic => 'viel seltener als die anderen',
    Mood.happy => 'deutlich seltener als die anderen',
    Mood.good => 'etwas seltener als die anderen',
    Mood.neutral => 'etwa wie die anderen',
    Mood.meh => 'etwas öfter als die anderen',
    Mood.sad => 'deutlich öfter als die anderen',
    Mood.angry => 'viel öfter als die anderen',
    Mood.celebrating => 'etwa wie die anderen',
  };
  return 'fährt $percent % — $wie';
}
