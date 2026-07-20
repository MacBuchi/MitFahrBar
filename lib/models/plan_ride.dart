/// plan_ride.dart – Wie jemand an einem geplanten Tag mitfährt.
///
/// Bewusst ohne `driver`: Der Fahrer wird im Plan nie gespeichert, sondern
/// berechnet (siehe `core/fairness.dart`). Gespeichert wird nur, was Menschen
/// entschieden haben — und das ist „ich kann ganz" oder „ich kann nur eine
/// Richtung".
///
/// Eigene Datei statt eines Felds in `Trip`: Ein Plan ist keine Fahrt, und
/// `ParticipationStatus` kennt einen Fahrer, den es hier nicht geben darf.
library;

enum PlanRide {
  /// Hin- und Rückweg — kommt als Fahrer in Frage.
  full,

  /// Nur eine Richtung. Stellt kein Auto und kann deshalb an diesem Tag
  /// nicht Fahrer sein.
  oneWay,
}
