/// system_insets_test.dart – Wer sein Scroll-Padding selbst setzt, verliert
/// die Systemränder (#241).
///
/// Der Fehler ist nur auf einem Gerät zu sehen: In jedem Widget-Test sind die
/// Ränder null, im Browser gibt es keine Navigationsleiste, und im Simulator
/// je nach Einstellung auch nicht. Gemeldet wurde er am 12.08.2026 mit einem
/// Screenshot des Benachrichtigungs-Schirms, auf dem der letzte Knopf zur
/// Hälfte unter Androids Leiste lag — und weiter scrollen ging nicht, weil
/// die Liste zu Ende war.
///
/// Dieselbe Klasse wie `android_manifest_test.dart`: Es kompiliert sauber,
/// jeder Flow-Test bleibt grün. Deshalb prüft dieser Test den **Quelltext**.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die eigenständigen Routen — also die ohne `bottomNavigationBar`.
///
/// Nur sie sind betroffen: Das `Scaffold` nimmt den unteren Rand aus der
/// MediaQuery seines Rumpfes heraus, sobald eine Navigationsleiste darunter
/// steht. Die vier Tab-Seiten (Übersicht, Woche, Historie, Statistik) dürfen
/// ihr Padding deshalb weiter frei setzen.
const _standalone = [
  'lib/features/notifications/notifications_screen.dart',
  'lib/features/persons/persons_screen.dart',
  'lib/features/settings/settings_screen.dart',
  'lib/features/prices/prices_screen.dart',
  'lib/features/help/help_screen.dart',
  'lib/features/import/import_screen.dart',
  'lib/features/trip_editor/trip_editor_screen.dart',
];

void main() {
  test('jeder eigenständige Schirm ergänzt den unteren Systemrand', () {
    for (final path in _standalone) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('withSystemBottom('),
        reason:
            '$path steht ohne Navigationsleiste und setzt sein Scroll-Padding '
            'selbst. Ohne `withSystemBottom` fällt der untere Systemrand weg, '
            'und das letzte Element liegt auf dem Gerät unter der Leiste — '
            'erreichbar ist es dann nicht mehr.',
      );
    }
  });

  // Der Riegel muss die Liste oben mitziehen, sonst wächst die App an ihr
  // vorbei: Eine neue Route ohne Navigationsleiste wäre wieder betroffen,
  // ohne dass irgendetwas rot wird.
  test('die Liste kennt alle Routen ohne Navigationsleiste', () {
    final router = File('lib/core/router.dart').readAsStringSync();
    // Routen der Schale stehen im StatefulShellRoute; alles davor sind die
    // eigenständigen.
    final shellAt = router.indexOf('StatefulShellRoute');
    expect(shellAt, isNonNegative);
    final standalonePart = router.substring(0, shellAt);

    // Aus `builder: (context, state) => const FooScreen()` den Klassennamen
    // ziehen und auf die Datei schließen.
    final screens = RegExp(
      r'const (\w+Screen)\(',
    ).allMatches(standalonePart).map((m) => m.group(1)!).toSet();

    // Diese hier tragen bewusst kein eigenes Scroll-Padding und brauchen den
    // Helfer deshalb nicht — sie überlassen Flutter die Ränder.
    const withoutOwnPadding = {
      'LoginScreen',
      'ConsoleLoginScreen',
      'ConsoleScreen',
      'NotesScreen',
    };

    final covered = {
      for (final path in _standalone)
        RegExp(
          r'class (\w+Screen)',
        ).firstMatch(File(path).readAsStringSync())!.group(1)!,
    };

    for (final screen in screens.difference(withoutOwnPadding)) {
      expect(
        covered,
        contains(screen),
        reason:
            '$screen ist eine Route ohne Navigationsleiste und steht nicht in '
            'der Liste dieses Tests. Entweder setzt der Schirm sein '
            'Scroll-Padding selbst — dann gehört `withSystemBottom` hinein und '
            'der Pfad in `_standalone` —, oder er überlässt Flutter die Ränder '
            'und gehört in `withoutOwnPadding`, mit genau diesem Grund.',
      );
    }
  });
}
