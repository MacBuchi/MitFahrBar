/// fuel_history_workflow_test.dart – Hält den Nachfüll-Lauf zusammen.
///
/// Dieselbe Klasse wie `notify_workflow_test.dart` und
/// `release_workflow_test.dart`: Was hier schiefgeht, fällt in keiner PR-CI
/// auf. Der Workflow läuft nur, wenn ihn jemand von Hand startet — und wenn
/// er dann falsch verdrahtet ist, merkt es niemand, weil eine ausbleibende
/// Vergangenheit keinen roten Lauf erzeugt, sondern nur eine gerade Linie
/// im Diagramm, die aussieht wie ein konstanter Preis.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '.github/workflows/fuel-history.yml',
  ).readAsStringSync();
  final tool = File('tool/import_fuel_history.py').readAsStringSync();

  group('Workflow und Werkzeug', () {
    test('der Lauf ruht, solange die Secrets fehlen', () {
      expect(workflow, contains(r'secrets.SUPABASE_SERVICE_ROLE_KEY'));
      expect(workflow, contains(r'secrets.TANKERKOENIG_ARCHIVE_PASSWORD'));
      expect(
        workflow,
        contains('::notice::'),
        reason:
            'Ein fehlendes Secret soll den Lauf still beenden, nicht rot '
            'färben — sonst steht der Workflow dauerhaft auf Fehler und '
            'niemand schaut mehr hin. Dieselbe Linie wie beim Feedback-Bot.',
      );
      expect(
        tool,
        contains("if not os.environ.get('SUPABASE_SERVICE_ROLE_KEY')"),
        reason:
            'Auch das Werkzeug selbst muss ruhen: Es läuft lokal ohne Secrets '
            'und darf dann nicht mit einem Stacktrace abbrechen.',
      );
    });

    test('Workflow und Werkzeug nennen dieselben Umgebungsvariablen', () {
      for (final name in [
        'SUPABASE_URL',
        'SUPABASE_SERVICE_ROLE_KEY',
        'TANKERKOENIG_ARCHIVE_USER',
        'TANKERKOENIG_ARCHIVE_PASSWORD',
      ]) {
        expect(
          workflow,
          contains('$name:'),
          reason: '$name wird im Workflow nicht gesetzt.',
        );
        expect(
          tool,
          contains("'$name'"),
          reason:
              '$name wird vom Werkzeug nicht gelesen. Ein umbenanntes Secret '
              'fällt sonst erst im Lauf auf — und dort sieht es aus wie ein '
              'fehlender Zugang, nicht wie ein Tippfehler.',
        );
      }
    });

    test('zwei Läufe können sich nicht überholen', () {
      expect(workflow, contains('concurrency:'));
      expect(
        workflow,
        contains('cancel-in-progress: false'),
        reason:
            'Zwei gleichzeitige Läufe zögen dieselben 30-MB-Dateien doppelt '
            'und schrieben dieselben Wochen. Abbrechen wäre schlimmer als '
            'warten: Der laufende hat die Dateien schon geholt.',
      );
    });

    test('der Lauf entscheidet in deutscher Zeit', () {
      expect(
        workflow,
        contains('TZ: Europe/Berlin'),
        reason:
            'Ob eine Woche abgeschlossen ist, entscheidet `date.today()`. Auf '
            'einem UTC-Runner wäre die Woche am Sonntagabend deutscher Zeit '
            'noch nicht vorbei — der Lauf ließe sie liegen, obwohl sie es '
            'ist. Dieselbe Zeitzone wie in rollup_fuel_weeks().',
      );
    });

    test('der Lauf ist gedeckelt und setzt fort', () {
      expect(
        workflow,
        contains('--max-weeks'),
        reason:
            'Ohne Deckel liefe ein Erst-Import über 165 Wochen in die '
            '6-Stunden-Grenze von Actions — und zwar erst nach Stunden.',
      );
      expect(
        tool,
        contains("default=100"),
        reason: 'Die Vorgabe im Werkzeug trägt den Lauf ohne Argument.',
      );
    });

    test('der Import läuft nicht nach Zeitplan', () {
      expect(
        workflow.contains(RegExp(r'^\s*schedule:', multiLine: true)),
        isFalse,
        reason:
            'Ein Zeitplan bräuchte zuerst einen Merker für Wochen, die das '
            'Archiv NIE haben wird (Lücken, Zeit vor Mitte 2014). Ohne ihn '
            'bleibt so eine Woche für immer eine Lücke und der Job zöge jede '
            'Nacht dieselben sieben Dateien vergeblich. Wer hier einen '
            'Zeitplan ergänzt, baut den Merker mit — sonst ist es kein '
            'Automatismus, sondern eine Endlosschleife.',
      );
    });
  });

  group('Dieselbe Kennzahl wie der Live-Takt', () {
    test('das Perzentil ist in Python dieselbe Zahl wie in Dart', () {
      final dart = File('lib/core/price_series.dart').readAsStringSync();
      final inDart = RegExp(
        r'const double defaultPercentile = ([0-9.]+);',
      ).firstMatch(dart);
      final inPython = RegExp(
        r'^PERCENTILE = ([0-9.]+)',
        multiLine: true,
      ).firstMatch(tool);
      expect(inDart, isNotNull, reason: 'defaultPercentile fehlt in Dart.');
      expect(inPython, isNotNull, reason: 'PERCENTILE fehlt im Werkzeug.');
      expect(
        double.parse(inPython!.group(1)!),
        double.parse(inDart!.group(1)!),
        reason:
            'Dritte Stelle derselben Definition — die beiden anderen hält '
            'schema_test.dart zusammen (Dart und percentile_cont in SQL). '
            'Driften sie auseinander, entsteht an der Naht zwischen '
            'importierter und gemessener Woche eine Stufe, die keine '
            'Preisänderung ist, und niemand könnte sie erklären.',
      );
    });

    test('die Stichzeiten des Imports sind die der Cron-Zeile', () {
      final migration = File(
        'supabase/migrations/20260802110000_fuel_sample_cron.sql',
      ).readAsStringSync();
      final cron = RegExp(r"'(\d+) ([\d,]+) \* \* \*'").firstMatch(migration);
      expect(cron, isNotNull, reason: 'Cron-Zeile nicht gefunden.');
      final minute = int.parse(cron!.group(1)!);
      final hours = cron.group(2)!.split(',').map(int.parse).toList()..sort();

      final block = RegExp(r'SAMPLE_TIMES_UTC = \((.*)\)').firstMatch(tool);
      expect(block, isNotNull, reason: 'SAMPLE_TIMES_UTC fehlt im Werkzeug.');
      final times =
          RegExp(r'dt\.time\((\d+),\s*(\d+)\)')
              .allMatches(block!.group(1)!)
              .map((m) => [int.parse(m.group(1)!), int.parse(m.group(2)!)])
              .toList()
            ..sort((a, b) => a[0].compareTo(b[0]));

      expect(
        times.map((t) => t[0]).toList(),
        hours,
        reason:
            'pg_cron rechnet in UTC — der Live-Takt tastet im Winter also '
            'eine Stunde früher ab als im Sommer. Feste ORTSZEITEN im Import '
            'wären der naheliegende, aber falsche Griff: Sie stellten im '
            'Winterhalbjahr eine andere Frage als die gemessene. Genau die '
            'Stufe, die dieses ganze Vorgehen vermeiden soll.',
      );
      expect(
        times.map((t) => t[1]).toSet(),
        {minute},
        reason: 'Auch die Minute muss dieselbe sein.',
      );
    });
  });

  test('der Lauf kann keinen vorhandenen Wert überschreiben', () {
    expect(
      tool,
      contains('resolution=ignore-duplicates'),
      reason:
          'Ein GEMESSENER Wert ist die genauere Wahrheit über seine Woche. '
          'Mit `merge-duplicates` schriebe ein Nachfüll-Lauf ihn still mit '
          'einem rekonstruierten über — und weil beide plausibel aussehen, '
          'fiele es niemandem auf. Der Riegel ersetzt zugleich jede '
          'Zustandsdatei: Ein zweiter Lauf ist einfach folgenlos.',
    );
    expect(
      tool,
      isNot(contains('merge-duplicates')),
      reason: 'Kein zweiter Schreibpfad daneben.',
    );
  });
}
