/// trip_editor_seed.dart – Vorbelegung des Fahrten-Editors aus dem
/// Eintragen-je-Auto-Ablauf des Wochenplaners (Issue #62).
library;

/// Wird als `state.extra` an `/trip/new` gereicht — bewusst nicht
/// deep-linkbar: Ein Reload landet im leeren Editor, verloren geht nichts,
/// der Plan bleibt ja stehen.
class TripEditorSeed {
  const TripEditorSeed({
    required this.date,
    required this.fullIds,
    required this.oneWayIds,
    required this.driverId,
    required this.carNumber,
    required this.carCount,
    required this.expectedSameDayTrips,
  });

  final DateTime date;

  /// Volle Teilnehmer dieses Autos INKLUSIVE Fahrer — das Modell des
  /// Editors, nicht das von `PlannedCar` (dort steht der Fahrer separat).
  final Set<String> fullIds;
  final Set<String> oneWayIds;

  /// Der geplante Fahrer dieses Autos. Er wird als manuelle Wahl gesetzt,
  /// nicht als Vorschlag: Auto 2 trägt selten den Fairness-Ersten seiner
  /// Teilmenge, und der Editor würde ihn sonst still ersetzen.
  final String driverId;

  /// Positionsnummer dieses Autos (1-basiert) und Gesamtzahl — reine
  /// Anzeige („Auto 2/2"), keine Aussage über die Abfahrtsreihenfolge.
  final int carNumber;
  final int carCount;

  /// So viele Fahrten existieren am Tag bereits, wenn dieser Editor
  /// aufgeht. Bis zu dieser Zahl schweigt die Rückfrage „Weitere Fahrt an
  /// diesem Tag?" — der orchestrierte Ablauf erzeugt sie ja absichtlich.
  /// Eine unerwartete Fremd-Fahrt liegt darüber und fragt weiter nach.
  final int expectedSameDayTrips;
}
