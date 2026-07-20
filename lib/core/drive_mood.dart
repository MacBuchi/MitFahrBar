/// drive_mood.dart – Fahranteil als Stimmung statt als Prozentzahl.
///
/// Seit Issue #38 steuert der Fahranteil die Reihenfolge nicht mehr; er ist
/// reine Anzeige. Eine nackte Prozentzahl neben Platz 1 las sich aber wie
/// ein Widerspruch („warum ist der mit 10 % dran?"). Ein Gesicht sagt das,
/// worum es geht: Musstest du zuletzt viel fahren oder wenig?
///
/// Reine Zuordnung ohne Widget, damit die Schwellen testbar bleiben —
/// dieselbe Trennung wie `chart_data.dart` ↔ `widgets/charts.dart`.
library;

/// Wie viel jemand im Vergleich zur Gruppe fahren musste.
enum DriveMood {
  /// Deutlich seltener als der Schnitt.
  veryHappy,
  happy,

  /// Ungefähr sein Teil.
  neutral,
  unhappy,

  /// Deutlich öfter als der Schnitt.
  veryUnhappy,
}

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
/// bekommen alle [DriveMood.neutral], statt aus 0 ÷ 0 ein Urteil zu
/// erfinden.
DriveMood driveMoodOf(double share, double averageShare) {
  if (averageShare <= 0) return DriveMood.neutral;
  final ratio = share / averageShare;
  if (ratio <= 0.6) return DriveMood.veryHappy;
  if (ratio <= 0.85) return DriveMood.happy;
  if (ratio < 1.15) return DriveMood.neutral;
  if (ratio < 1.4) return DriveMood.unhappy;
  return DriveMood.veryUnhappy;
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
String driveMoodLabel(DriveMood mood, double share) {
  final percent = (share * 100).round();
  return switch (mood) {
    DriveMood.veryHappy => 'fährt $percent % — viel seltener als die anderen',
    DriveMood.happy => 'fährt $percent % — seltener als die anderen',
    DriveMood.neutral => 'fährt $percent % — etwa wie die anderen',
    DriveMood.unhappy => 'fährt $percent % — öfter als die anderen',
    DriveMood.veryUnhappy => 'fährt $percent % — viel öfter als die anderen',
  };
}
