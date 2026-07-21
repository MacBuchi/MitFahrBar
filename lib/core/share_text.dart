/// share_text.dart – Plattform-Weiche fürs Weitergeben eines Textes.
///
/// Gegenstück zu `export_file.dart`. Getrennt davon, weil hier ein **Text**
/// weitergeht und keine Datei: Android kann ihn ans Teilen-Menü geben, im
/// Browser ist die Web-Share-API für reinen Text unzuverlässig (auf dem
/// Desktop meist gar nicht vorhanden). Dort landet er deshalb in der
/// Zwischenablage — verlässlicher als ein Teilen-Dialog, den es nicht gibt.
library;

export 'share_outcome.dart';
export 'share_text_stub.dart'
    if (dart.library.js_interop) 'share_text_web.dart'
    if (dart.library.io) 'share_text_io.dart';
