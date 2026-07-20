/// log.dart – Zentraler Logger-Wrapper. In lib/ nie print verwenden.
///
/// Zusätzlich hält [logRing] die letzten Meldungen im Speicher, damit man sie
/// einer Rückmeldung anhängen kann. Ohne das sind Abstürze auf den Geräten der
/// Gruppe unsichtbar: In Release schreibt der Logger nur auf die Konsole, und
/// die sieht niemand.
library;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Ringpuffer der letzten Log-Zeilen — **nur im Speicher**, nie auf Platte.
///
/// Bewusst klein und flüchtig: Der Inhalt kann auf Wunsch in eine Rückmeldung
/// wandern, und die wird ein öffentliches GitHub-Issue. Was hier landet, ist
/// damit potenziell öffentlich — deshalb gehören in `log`-Aufrufe keine
/// Personennamen und keine Fahrtdaten.
class LogRing {
  LogRing({this.capacity = 50});

  /// Wie viele Zeilen aufgehoben werden. Mehr würde den Dialog fluten, ohne
  /// dass die ältesten Zeilen noch zum Fehler gehören.
  final int capacity;

  final _lines = <String>[];

  void add(String line) {
    _lines.add(line);
    final excess = _lines.length - capacity;
    if (excess > 0) _lines.removeRange(0, excess);
  }

  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  List<String> get lines => List.unmodifiable(_lines);

  void clear() => _lines.clear();

  /// Die jüngsten Zeilen, zusammen höchstens [maxChars] lang. Von hinten
  /// gefüllt, weil die letzte Meldung vor einem Absturz die interessanteste
  /// ist — und weil `feedback.message` sonst unnötig aufgebläht würde.
  String tail({int maxChars = 2000}) {
    final kept = <String>[];
    var length = 0;
    for (final line in _lines.reversed) {
      final next = length + line.length + 1;
      if (kept.isNotEmpty && next > maxChars) break;
      kept.add(line);
      length = next;
    }
    return kept.reversed.join('\n');
  }
}

final logRing = LogRing();

/// Schreibt weiter auf die Konsole und zusätzlich in den Ringpuffer. Als
/// [LogOutput] eingehängt, damit jede Meldung automatisch mitgeschnitten wird
/// — die globalen Fehler-Handler in `main.dart` laufen bereits über `log.e`,
/// es muss also keine einzige Aufrufstelle angefasst werden.
class _RingOutput extends LogOutput {
  final _console = ConsoleOutput();

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      logRing.add(line);
    }
    _console.output(event);
  }
}

final Logger log = Logger(
  // In Release nur warning+ — genau das, was für eine Fehlermeldung zählt.
  level: kDebugMode ? Level.debug : Level.warning,
  printer: SimplePrinter(colors: false),
  output: _RingOutput(),
);
