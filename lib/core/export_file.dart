/// export_file.dart – Plattform-Weiche: wie die fertige Datei beim Nutzer
/// ankommt. Web lädt herunter, Android reicht sie ans Teilen-Menü.
library;

export 'export_file_stub.dart'
    if (dart.library.js_interop) 'export_file_web.dart'
    if (dart.library.io) 'export_file_io.dart';
