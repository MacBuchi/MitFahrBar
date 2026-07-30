/// exit_info_repository.dart – Androids Beendigungs-Historie (Issue #144).
///
/// Der Error-Sink (#136) sieht nur Fehler, die die App überlebt — ein ANR,
/// ein nativer Crash oder ein Speicher-Kill hinterlässt nichts. Android
/// führt darüber ab Version 11 selbst Buch, und eine App darf ihre eigenen
/// Einträge ohne jede Berechtigung lesen. Das ist die einzige Quelle, die
/// auch harte Tode erfasst — Play-Vitals gibt es nur mit Play, und MitFahrBar
/// wird daran vorbei ausgeliefert.
///
/// Auf Web und älteren Androids liefert das schlicht nichts; der Aufrufer
/// merkt keinen Unterschied. Muster von PilzBuddy (pilzbuddy#147), mit
/// korrigierter Einheiten-Rechnung: `getRss()`/`getPss()` liefern kB, die
/// Vorlage teilte doppelt durch 1024 und meldete damit 1024-fach zu kleine
/// Werte.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ein Eintrag aus Androids Beendigungs-Historie.
class AppExit {
  const AppExit({
    required this.timestamp,
    required this.reason,
    this.description,
    this.rssKb = 0,
    this.pssKb = 0,
    this.importance = 0,
    this.hasTrace = false,
  });

  /// Wann der Prozess starb — NICHT, wann gemeldet wird.
  final DateTime timestamp;

  /// `ANR`, `CRASH`, `CRASH_NATIVE`, `LOW_MEMORY`, `USER_REQUESTED` …
  final String reason;

  final String? description;
  final int rssKb;
  final int pssKb;
  final int importance;

  /// Nur bei ANR legt Android einen Thread-Dump dazu.
  final bool hasTrace;

  /// Ein normales Beenden ist kein Fehler und gehört nicht gemeldet — sonst
  /// füllt jedes Wegwischen aus der Übersicht den Wochen-Digest (dieselbe
  /// Lehre wie beim `worthReporting`-Filter des Sinks).
  bool get isFailure => const {
    'ANR',
    'CRASH',
    'CRASH_NATIVE',
    'LOW_MEMORY',
    'EXCESSIVE_RESOURCE_USAGE',
    'INITIALIZATION_FAILURE',
  }.contains(reason);

  /// Was im Bericht steht. RSS/PSS von 0 heißt „Android hat den Speicher
  /// nicht erfasst" — dann bleibt der Wert weg statt als „RSS 0 MB" eine
  /// falsche Auskunft zu geben (DocuHub-Regel: ein unplausibilisiertes
  /// Feld ist schlimmer als keins).
  String get summary {
    final parts = <String>[
      if (description != null && description!.isNotEmpty) description!,
      if (rssKb > 0) 'RSS ${(rssKb / 1024).round()} MB',
      if (pssKb > 0) 'PSS ${(pssKb / 1024).round()} MB',
      'importance $importance',
    ];
    return parts.join(' · ');
  }

  static AppExit? fromMap(Map<Object?, Object?> map) {
    final timestamp = map['timestamp'];
    final reason = map['reasonName'];
    if (timestamp is! int || reason is! String) return null;
    return AppExit(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      reason: reason,
      description: map['description'] as String?,
      rssKb: (map['rssKb'] as int?) ?? 0,
      pssKb: (map['pssKb'] as int?) ?? 0,
      importance: (map['importance'] as int?) ?? 0,
      hasTrace: map['hasTrace'] == true,
    );
  }
}

/// Fragt die Historie über den MethodChannel in `MainActivity.kt` ab.
///
/// Zwei Methoden, bewusst getrennt: Die Übersicht ist billig, der
/// ANR-Thread-Dump ist es nicht (Rohdatei ~2 MB) — Dart holt ihn nur für
/// Einträge, die es noch nicht gemeldet hat.
class ExitInfoRepository {
  ExitInfoRepository({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Muss wörtlich mit `CHANNEL` in `MainActivity.kt` übereinstimmen —
  /// `test/android_manifest_test.dart` vergleicht beide Dateien.
  static const channelName = 'de.macbuchi.mitfahrbar/exit_info';

  final MethodChannel _channel;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Die letzten Beendigungen, neueste zuerst.
  Future<List<AppExit>> recentExits({int limit = 10}) async {
    if (!_supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('exitReasons', {
        'limit': limit,
      });
      return (raw ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(AppExit.fromMap)
          .whereType<AppExit>()
          .toList();
    } catch (_) {
      // Diagnose darf den Start nie gefährden: Fehlt der Kanal (alter
      // Build, anderes Gerät), ist die Liste eben leer.
      return const [];
    }
  }

  /// Der Haupt-Thread-Abschnitt des ANR-Dumps, oder null.
  Future<String?> traceFor(AppExit exit) async {
    if (!_supported || !exit.hasTrace) return null;
    try {
      return await _channel.invokeMethod<String>('exitTrace', {
        'timestamp': exit.timestamp.millisecondsSinceEpoch,
      });
    } catch (_) {
      return null;
    }
  }
}
