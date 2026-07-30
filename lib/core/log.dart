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

/// Zusätzlicher Abnehmer für Fehler-Meldungen (`log.e`/`log.f`) — die Senke
/// aus Issue #136. Als Callback statt Import, damit `core/` nicht von
/// `data/` abhängt; verdrahtet wird in `main()`, in Tests und im Demo-Modus
/// bleibt er `null` und alles verhält sich wie zuvor.
typedef LogErrorSink =
    void Function(String context, Object? error, StackTrace? stackTrace);

LogErrorSink? _errorSink;
bool _inErrorSink = false;

void setLogErrorSink(LogErrorSink? sink) => _errorSink = sink;

/// Schreibt weiter auf die Konsole und zusätzlich in den Ringpuffer. Als
/// [LogOutput] eingehängt, damit jede Meldung automatisch mitgeschnitten wird
/// — die globalen Fehler-Handler in `main.dart` laufen bereits über `log.e`,
/// es muss also keine einzige Aufrufstelle angefasst werden. Derselbe Griff
/// trägt die Fehler-Senke: Jeder `log.e` im Code meldet mit, ohne dass eine
/// Aufrufstelle davon weiß.
class _RingOutput extends LogOutput {
  final _console = ConsoleOutput();

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      logRing.add(line);
    }
    _console.output(event);
    final origin = event.origin;
    final isError = origin.level == Level.error || origin.level == Level.fatal;
    // Reentranz-Riegel: Loggte die Senke selbst, meldete sich ihr
    // Fehlschlag in einer Schleife immer wieder.
    if (isError && _errorSink != null && !_inErrorSink) {
      _inErrorSink = true;
      try {
        _errorSink!(origin.message.toString(), origin.error, origin.stackTrace);
      } catch (_) {
        // Die Senke darf das Loggen nie zum Absturz machen.
      } finally {
        _inErrorSink = false;
      }
    }
  }
}

final Logger log = Logger(
  // In Release nur warning+ — genau das, was für eine Fehlermeldung zählt.
  level: kDebugMode ? Level.debug : Level.warning,
  printer: SimplePrinter(colors: false),
  output: _RingOutput(),
);
