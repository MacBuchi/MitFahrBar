/// export_file_io.dart – Android: Dateien ans Teilen-Menü übergeben.
///
/// `XFile.fromData` legt die Datei selbst temporär ab, deshalb braucht der
/// Export kein `path_provider` und keinen Schreibzugriff auf den Speicher.
/// Die Namen müssen über `fileNameOverrides` kommen — der `name` in
/// `XFile.fromData` wird auf den meisten Plattformen ignoriert.
///
/// **Ein Aufruf für alle Dateien**, nicht einer je Datei: Seit die Sicherung
/// aus Fahrten, Parametern und Preisen besteht (#272), wären das sonst drei
/// Teilen-Menüs hintereinander — und wer das zweite abbricht, hat eine halbe
/// Sicherung, ohne es zu merken.
library;

import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import 'export_payload.dart';

Future<void> saveTextFiles(List<ExportFile> files) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        for (final file in files)
          XFile.fromData(utf8.encode(file.content), mimeType: 'text/csv'),
      ],
      fileNameOverrides: [for (final file in files) file.name],
      subject: files.first.name,
    ),
  );
}
