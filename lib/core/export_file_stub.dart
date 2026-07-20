/// export_file_stub.dart – Fallback für Plattformen ohne Weiche.
///
/// Wird nie eingebunden, solange die App nur Web und Android baut; existiert,
/// damit die bedingte Einbindung in `export_file.dart` auch beim Analysieren
/// ein Ziel hat.
library;

Future<void> saveTextFile({
  required String name,
  required String content,
}) async {
  throw UnsupportedError('Kein Datei-Export auf dieser Plattform.');
}
