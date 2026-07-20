/// export_file_web.dart – Download über einen kurzlebigen Blob-Link.
///
/// Bewusst kein Teilen-Menü: Im Browser ist die Web-Share-API für Dateien
/// nicht überall da, und für eine Sicherung will man ohnehin die Datei im
/// Download-Ordner.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> saveTextFile({
  required String name,
  required String content,
}) async {
  final blob = web.Blob(
    [utf8.encode(content).toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  anchor.click();
  // Ohne revoke bleibt der Blob bis zum Neuladen im Speicher.
  web.URL.revokeObjectURL(url);
}
