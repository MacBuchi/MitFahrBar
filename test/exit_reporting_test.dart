// Der Weg von Androids Beendigungs-Historie in `error_reports` (Issue #144).
//
// Ohne diesen Weg hinterlässt ein ANR oder Absturz gar nichts: Der
// Error-Sink (#136) sieht nur, was die App überlebt. Gefakt wird am
// Repository-Seam, nicht am MethodChannel — geprüft wird der Inhalt der
// Meldung, nicht die Plattform.
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/log.dart';
import 'package:mitfahrbar/data/error_report_repository.dart';
import 'package:mitfahrbar/data/exit_info_repository.dart';
import 'package:mitfahrbar/data/exit_reporting.dart';

/// Ein geschriebener Bericht — geprüft wird der Inhalt, nicht der Aufruf.
class ReportedExit {
  ReportedExit(this.reason, this.summary, this.when, this.trace);

  final String reason;
  final String summary;
  final DateTime when;
  final String? trace;
}

/// Sammelt statt zu schreiben; ohne Netz, wie der Rest der Suite.
class FakeErrorReports implements ErrorReportRepository {
  final exits = <ReportedExit>[];

  @override
  Future<void> reportExit({
    required String reason,
    required String summary,
    required DateTime when,
    String? trace,
  }) async => exits.add(ReportedExit(reason, summary, when, trace));

  @override
  Future<void> report(
    String context,
    Object? error,
    StackTrace? stackTrace,
  ) async {}
}

/// Liefert vorgegebene Einträge, statt die Plattform zu fragen.
class _FakeExits implements ExitInfoRepository {
  _FakeExits(this.exits, {this.trace, this.throwOnRead = false});

  final List<AppExit> exits;
  final String? trace;
  final bool throwOnRead;
  int traceCalls = 0;

  @override
  Future<List<AppExit>> recentExits({int limit = 10}) async {
    if (throwOnRead) throw StateError('Kanal fehlt');
    return exits;
  }

  @override
  Future<String?> traceFor(AppExit exit) async {
    traceCalls++;
    return exit.hasTrace ? trace : null;
  }
}

AppExit _exit(
  String reason,
  DateTime when, {
  int rssKb = 0,
  bool hasTrace = false,
}) => AppExit(
  timestamp: when,
  reason: reason,
  description: 'beschreibung',
  rssKb: rssKb,
  hasTrace: hasTrace,
);

void main() {
  late InMemoryExitMarkerStore marker;
  ExitReporter reporter(FakeErrorReports reports, _FakeExits exits) =>
      ExitReporter(exits: exits, reports: reports, marker: marker);

  setUp(() => marker = InMemoryExitMarkerStore());
  tearDown(() => setLogErrorSink(null));

  test('Ein ANR wird gemeldet, mit Zeitpunkt und Thread-Dump', () async {
    final when = DateTime(2026, 7, 30, 15, 39);
    final reports = FakeErrorReports();
    final exits = _FakeExits([
      _exit('ANR', when, rssKb: 1900 * 1024, hasTrace: true),
    ], trace: '"main" prio=5 tid=1 Native');

    await reporter(reports, exits).reportPending();

    expect(reports.exits, hasLength(1));
    final report = reports.exits.single;
    expect(report.reason, 'ANR');
    expect(
      report.when,
      when,
      reason:
          'Der Todeszeitpunkt, nicht der Meldezeitpunkt — sonst landet ein '
          'Absturz von Freitagnacht im Digest der Folgewoche.',
    );
    expect(report.trace, contains('"main"'));
    expect(
      report.summary,
      contains('RSS 1900 MB'),
      reason:
          'Der RSS zeigt einen Speicher-Tod vor jedem Stacktrace. kB → MB '
          'wird genau EINMAL geteilt — die PilzBuddy-Vorlage teilte doppelt '
          'und meldete 1024-fach zu kleine Werte.',
    );
  });

  test('RSS und PSS von 0 bleiben aus der Meldung draußen', () async {
    // Android erfasst den Speicher nicht immer (real beobachtet am
    // 27.07.2026: 0 im Eintrag, 1,7–1,9 GB in dumpsys). Ein „RSS 0 MB"
    // wäre eine falsche Auskunft — dann lieber keine.
    final reports = FakeErrorReports();
    final exits = _FakeExits([_exit('CRASH', DateTime(2026, 7, 30, 15))]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits.single.summary, isNot(contains('RSS')));
    expect(reports.exits.single.summary, isNot(contains('PSS')));
  });

  test('Ein normales Beenden wird NICHT gemeldet', () async {
    // Sonst füllt jedes Wegwischen aus der Übersicht den Wochen-Digest —
    // dieselbe Lehre wie beim worthReporting-Filter (#136).
    final reports = FakeErrorReports();
    final exits = _FakeExits([
      _exit('USER_REQUESTED', DateTime(2026, 7, 30, 12)),
      _exit('EXIT_SELF', DateTime(2026, 7, 30, 13)),
      _exit('OTHER', DateTime(2026, 7, 30, 14)),
    ]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits, isEmpty);
  });

  test(
    'Derselbe Eintrag wird beim zweiten Start nicht erneut gemeldet',
    () async {
      final reports = FakeErrorReports();
      final exits = _FakeExits([_exit('CRASH', DateTime(2026, 7, 30, 15))]);

      await reporter(reports, exits).reportPending();
      await reporter(reports, exits).reportPending();

      expect(reports.exits, hasLength(1));
    },
  );

  test('Nur Einträge nach dem letzten gemeldeten kommen dazu', () async {
    final reports = FakeErrorReports();
    final alt = _exit('ANR', DateTime(2026, 7, 30, 10));
    final neu = _exit('ANR', DateTime(2026, 7, 30, 20));

    await reporter(reports, _FakeExits([alt])).reportPending();
    await reporter(reports, _FakeExits([alt, neu])).reportPending();

    expect(reports.exits.map((e) => e.when), [alt.timestamp, neu.timestamp]);
  });

  test('Auch ohne meldbare Einträge rückt der Merker vor', () async {
    // Sonst wird die Historie bei jedem Start erneut durchgesehen.
    final reports = FakeErrorReports();
    final harmlos = _exit('USER_REQUESTED', DateTime(2026, 7, 30, 18));
    await reporter(reports, _FakeExits([harmlos])).reportPending();

    // Ein ANR VOR dem harmlosen Eintrag gilt damit als erledigt.
    final alt = _exit('ANR', DateTime(2026, 7, 30, 9));
    await reporter(reports, _FakeExits([harmlos, alt])).reportPending();

    expect(reports.exits, isEmpty);
  });

  test('Ein kaputter Kanal bricht den Start nicht ab', () async {
    // Diagnose, die den Start gefährdet, ist schlimmer als keine.
    final gemeldet = <String>[];
    setLogErrorSink((context, _, _) => gemeldet.add(context));
    final reports = FakeErrorReports();

    await expectLater(
      reporter(
        reports,
        _FakeExits(const [], throwOnRead: true),
      ).reportPending(),
      completes,
    );
    expect(reports.exits, isEmpty);
    expect(gemeldet, ['Beendigungsgrund melden']);
  });

  test('Ohne ANR wird kein Thread-Dump angefordert', () async {
    // Das Lesen des Dumps ist teuer (Rohdatei ~2 MB).
    final reports = FakeErrorReports();
    final exits = _FakeExits([_exit('LOW_MEMORY', DateTime(2026, 7, 30, 15))]);

    await reporter(reports, exits).reportPending();

    expect(reports.exits.single.trace, isNull);
  });
}
