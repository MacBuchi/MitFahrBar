/// exit_reporting.dart – Meldet nachträglich, warum die App beim letzten
/// Mal beendet wurde (Issue #144, Phase 2 von #136).
///
/// Ablauf beim Start: Androids Historie lesen, alles überspringen, was
/// schon gemeldet wurde oder kein Fehler war, den Rest über den Error-Sink
/// nach `error_reports` schreiben und den neuesten Zeitpunkt merken.
///
/// Der Merker liegt in SharedPreferences statt in einer Datei:
/// `path_provider` ist hier bewusst kein Dependency (siehe
/// `export_file_io.dart`), SharedPreferences dagegen schon (Geräte-
/// Zuordnung #121). Die Android-Backup-Regeln schließen die Prefs-Datei
/// aus — der Merker überlebt also keinen Gerätewechsel. Das ist in
/// Ordnung: Sein Verlust kostet höchstens eine doppelte Meldung.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/log.dart';
import 'error_report_repository.dart';
import 'exit_info_repository.dart';

/// Wo der Zeitpunkt der letzten Meldung liegt — als Seam, damit Tests ohne
/// SharedPreferences auskommen (Muster `DeviceIdentityStore`).
abstract class ExitMarkerStore {
  Future<DateTime> lastReported();
  Future<void> remember(DateTime when);
}

class SharedPrefsExitMarkerStore implements ExitMarkerStore {
  static const _key = 'exit.last_reported';

  @override
  Future<DateTime> lastReported() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_key) ?? 0);
    } catch (_) {
      // Ohne Merker lieber doppelt melden als gar nicht.
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Future<void> remember(DateTime when) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, when.millisecondsSinceEpoch);
    } catch (_) {
      // Siehe oben: eine doppelte Meldung ist der harmlosere Ausgang.
    }
  }
}

class InMemoryExitMarkerStore implements ExitMarkerStore {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<DateTime> lastReported() async => _last;

  @override
  Future<void> remember(DateTime when) async => _last = when;
}

class ExitReporter {
  ExitReporter({
    required ExitInfoRepository exits,
    required ErrorReportRepository reports,
    ExitMarkerStore? marker,
  }) : _exits = exits,
       _reports = reports,
       _marker = marker ?? SharedPrefsExitMarkerStore();

  final ExitInfoRepository _exits;
  final ErrorReportRepository _reports;
  final ExitMarkerStore _marker;

  /// Einmal beim Start aufrufen. Wirft nie: Eine Diagnose, die den Start
  /// gefährdet, ist schlimmer als gar keine.
  Future<void> reportPending() async {
    try {
      final exits = await _exits.recentExits();
      if (exits.isEmpty) return;

      final since = await _marker.lastReported();
      // Älteste zuerst, damit der Merker am Ende auf dem Neuesten steht,
      // selbst wenn eine Meldung dazwischen scheitert.
      final pending =
          exits.where((e) => e.isFailure && e.timestamp.isAfter(since)).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final exit in pending) {
        await _reports.reportExit(
          reason: exit.reason,
          summary: exit.summary,
          when: exit.timestamp,
          trace: await _exits.traceFor(exit),
        );
        await _marker.remember(exit.timestamp);
      }

      // Auch ohne meldbare Einträge den Merker nachziehen: Sonst wird die
      // Historie bei jedem Start erneut durchgesehen.
      if (pending.isEmpty) {
        final newest = exits
            .map((e) => e.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (newest.isAfter(since)) await _marker.remember(newest);
      }
    } catch (e, stackTrace) {
      // Nur loggen: Der Weg hierher ist Diagnose, kein Kernpfad. Der Sink
      // hat einen Reentrancy-Riegel — das hier kann keine Schleife werden.
      log.e('Beendigungsgrund melden', error: e, stackTrace: stackTrace);
    }
  }
}
