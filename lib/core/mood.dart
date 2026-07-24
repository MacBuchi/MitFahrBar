/// mood.dart – Die Stimmungs-Skala des Design-Sets „MitFahrBar Smiley Set".
///
/// Sieben Bewertungsstufen von [Mood.angry] bis [Mood.ecstatic], dazu
/// [Mood.celebrating] — das steht bewusst **außerhalb** der Skala: Es ist
/// keine Bewertung, sondern die Auszeichnung eines Erfolgs. Deshalb kann
/// keine Bewertungsfunktion es zurückgeben; es wird gezielt gesetzt.
library;

enum Mood {
  angry,
  sad,
  meh,
  neutral,
  good,
  happy,
  ecstatic,

  /// Konfetti-Gesicht für einen Erfolg — nicht Teil der Skala.
  celebrating,
}
