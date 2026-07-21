/// release_notes.dart – Release-Body für den Update-Dialog lesbar machen.
///
/// Der Dialog zeigt schlichten Text, keinen Markdown-Renderer (bewusst keine
/// Dependency dafür). Seit dem Gerätetest 2026-07-21 ist klar, was sonst
/// passiert: `## What's Changed`, Sternchen und nackte PR-URLs standen roh
/// vor der Gruppe. Der Release-Workflow liefert inzwischen den deutschen
/// CHANGELOG-Auszug — diese Funktion glättet dessen Markdown-Reste und hält
/// zugleich ältere, auto-generierte englische Bodies lesbar.
library;

/// Reduziert Markdown auf Fließtext: Überschriften ohne Rauten,
/// Listenpunkte als `•`, Fett-/Kursiv-Marker weg, Links auf ihren Text,
/// reine URL- und „Full Changelog"-Zeilen ganz raus.
String plainReleaseNotes(String markdown) {
  final lines = <String>[];
  for (final raw in markdown.split('\n')) {
    var line = raw.trimRight();
    final trimmed = line.trimLeft();

    // Vergleichszeilen („Full Changelog: …") und nackte URLs tragen im
    // Dialog nichts — wer sie will, findet sie auf der Release-Seite.
    final bare = trimmed.replaceAll(RegExp(r'[*_]'), '').trim();
    if (bare.toLowerCase().startsWith('full changelog')) continue;
    if (RegExp(r'^https?://\S+$').hasMatch(bare)) continue;

    // Überschrift → eigene Zeile ohne Rauten.
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    // Listenpunkt → Aufzählungszeichen (Einrückung bleibt erhalten).
    line = line.replaceFirstMapped(
      RegExp(r'^(\s*)[-*+]\s+'),
      (m) => '${m[1]}• ',
    );
    // [Text](URL) → Text.
    line = line.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m[1]!,
    );
    // Fett/Kursiv/Code-Marker sind ohne Renderer nur Rauschen.
    line = line.replaceAll(RegExp(r'\*{1,2}|__|`'), '');
    // URL mitten im Satz („… by @x in https://…") → abschneiden.
    line = line.replaceAll(RegExp(r'\s*\bin\s+https?://\S+'), '');
    line = line.replaceAll(RegExp(r'https?://\S+'), '').trimRight();

    lines.add(line);
  }

  // Mehrfache Leerzeilen zusammenfalten, Ränder säubern.
  final text = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return text;
}
