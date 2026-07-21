/// import_file.dart – Eine CSV-Datei zum Einlesen auswählen.
///
/// Gegenstück zu `export_file.dart`, hier aber **ohne** Plattform-Weiche:
/// `file_selector` deckt Web und Android mit demselben Aufruf ab. Ein zweiter,
/// handgeschriebener Web-Pfad wäre Code, den wir pflegen müssten, ohne etwas
/// zu gewinnen.
///
/// Warum nicht `file_picker`, das bekanntere Paket: Es verlangt ab 8.3.3
/// `win32 ^5.9`, `package_info_plus` aber `win32 ^6` — die beiden lassen sich
/// nicht zusammen auflösen. Übrig bliebe eine Version von 2021.
/// `file_selector` kommt von der Flutter-Foundation und löst sauber auf.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Öffnet die Dateiauswahl und liest die Datei als Text.
///
/// `null`, wenn abgebrochen wurde — das ist kein Fehler und soll auch nicht
/// wie einer aussehen.
///
/// Gelesen wird **UTF-8 mit `allowMalformed`**: Eine Datei, die durch ein
/// altes Tabellenprogramm gelaufen ist, kann einzelne kaputte Bytes tragen.
/// Daran soll nicht der ganze Import scheitern — die betroffene Stelle wird
/// zum Ersatzzeichen, und die Zeile fällt beim Prüfen auf.
Future<String?> pickCsvText() async {
  const csvFiles = XTypeGroup(
    label: 'CSV',
    extensions: ['csv'],
    mimeTypes: ['text/csv', 'text/plain'],
    webWildCards: ['.csv', 'text/csv'],
  );
  final file = await openFile(acceptedTypeGroups: const [csvFiles]);
  if (file == null) return null;
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
}
