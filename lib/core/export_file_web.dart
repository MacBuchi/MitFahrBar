/// export_file_web.dart – Download über kurzlebige Blob-Links.
///
/// Bewusst kein Teilen-Menü: Im Browser ist die Web-Share-API für Dateien
/// nicht überall da, und für eine Sicherung will man ohnehin die Datei im
/// Download-Ordner.
///
/// Mehrere Dateien werden nacheinander angestoßen; der Browser fragt dabei
/// einmal, ob er mehrere Downloads erlauben darf. Ein ZIP daraus zu machen
/// hiesse, eine Archiv-Bibliothek einzubinden — für drei Textdateien, die
/// einzeln ohnehin lesbarer sind.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'export_payload.dart';

Future<void> saveTextFiles(List<ExportFile> files) async {
  for (final file in files) {
    final blob = web.Blob(
      [utf8.encode(file.content).toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = file.name;
    anchor.click();
    // Ohne revoke bleibt der Blob bis zum Neuladen im Speicher.
    web.URL.revokeObjectURL(url);
  }
}
