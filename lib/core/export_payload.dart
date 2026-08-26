/// export_payload.dart – Was eine Export-Datei ausmacht.
///
/// Eigene Datei, weil beide Seiten der Plattform-Weiche sie brauchen: In
/// `export_file.dart` steht nur die bedingte Einbindung, und ein Typ dort
/// wäre je nach Plattform ein anderer.
library;

class ExportFile {
  const ExportFile({required this.name, required this.content});

  final String name;
  final String content;
}
