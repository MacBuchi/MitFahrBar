/// export_file_io.dart – Android: Datei ans Teilen-Menü übergeben.
///
/// `XFile.fromData` legt die Datei selbst temporär ab, deshalb braucht der
/// Export kein `path_provider` und keinen Schreibzugriff auf den Speicher.
/// Der Name muss über `fileNameOverrides` kommen — der `name` in
/// `XFile.fromData` wird auf den meisten Plattformen ignoriert.
library;

import 'dart:convert';

import 'package:share_plus/share_plus.dart';

Future<void> saveTextFile({
  required String name,
  required String content,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(utf8.encode(content), mimeType: 'text/csv')],
      fileNameOverrides: [name],
      subject: name,
    ),
  );
}
