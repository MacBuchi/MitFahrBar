/// share_outcome.dart – Ergebnis von `shareText`.
///
/// Eigene Datei, weil die Plattform-Umsetzungen sie brauchen und
/// `share_text.dart` genau diese exportiert — andersherum wäre es zirkulär.
library;

/// Wie der Text den Weg nach draußen genommen hat; die Oberfläche muss
/// anschließend das Richtige sagen.
enum ShareOutcome {
  /// Ans Teilen-Menü übergeben (Android).
  shared,

  /// In die Zwischenablage gelegt (Browser).
  copied,
}
