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

  group('Ein Download trägt alle Gebiete', () {
    // Der teure Teil ist der Download (7 × ~30 MB je Woche), und er hing
    // bis August 2026 am GEBIET statt an der Woche. Weil `region_key` auf
    // ~1 km auflöst, hat praktisch jede Gruppe ihr eigenes Gebiet — der
    // Aufwand wuchs also mit der Zahl der Gruppen. Zahlen und die
    // verworfene Raster-Alternative: doc/entscheidung-preisnetz.md.
    test('die Schleife dreht sich um die Woche, nicht um das Gebiet', () {
      expect(
        tool,
        contains('def collect_weeks('),
        reason:
            'collect_weeks() ist die Umkehr: eine Woche einmal lesen, '
            'daraus alle Mittelpunkte bedienen. Ohne sie zahlt jede '
            'zusätzliche Gegend dieselben 210 MB noch einmal.',
      );
      expect(
        tool,
        contains('by_week'),
        reason:
            'Die Wochen müssen vor dem Laden gebündelt werden — sonst '
            'nützt collect_weeks() nichts, weil jede Region einzeln '
            'hineingeht.',
      );
    });

    test('die Gleichwertigkeit hängt in der PR-CI, nicht nur im Werkzeug', () {
      expect(
        tool,
        contains('def self_check('),
        reason:
            'Ein geteilter Download, der andere Wochenwerte liefert, wäre '
            'kein Fortschritt, sondern eine stille Verschiebung der '
            'Ersparnis aller Gruppen.',
      );
      expect(
        File('.github/workflows/ci.yml').readAsStringSync(),
        contains('import_fuel_history.py --self-check'),
        reason:
            'Die Prüfung braucht weder Netz noch Datenbank und gehört '
            'deshalb in JEDE PR — im nächtlichen Job liefe sie erst, wenn '
            'der Schaden schon in price_week steht.',
      );
    });
  });

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

    test('der Import läuft nächtlich — und NUR zusammen mit dem Merker', () {
      // Bis v0.84.0 war der Zeitplan bewusst abwesend: Ohne Merker zöge
      // der Job für eine Woche, die das Archiv nie haben wird, jede Nacht
      // dieselben sieben Dateien. Der Merker (`price_week_skip`) ist jetzt
      // gebaut — Zeitplan und Merker gehören ab hier ZUSAMMEN. Wer eine
      // Hälfte entfernt, macht aus dem Automatismus wieder die
      // Endlosschleife, vor der die alte Fassung dieses Tests gewarnt hat.
      expect(
        workflow,
        contains(RegExp(r'^\s*schedule:', multiLine: true)),
        reason:
            'Der Anlass ist real: Nachgetragene oder umdatierte Fahrten in '
            'vormals fahrfreien Wochen und der CSV-Import einer Gruppe '
            'erzeugen neue Lücken, und niemand stößt den Lauf von Hand an — '
            '2023-W48 hat so die Ersparnis-Kurve zweieinhalb Jahre '
            'gestrichelt.',
      );
      expect(
        tool,
        contains('price_week_skip'),
        reason:
            'Der Zeitplan ohne den Merker ist die Endlosschleife: Eine '
            'Woche ohne Archivdaten bliebe für immer eine Lücke, und der '
            'Job zöge jede Nacht dieselben sieben 30-MB-Dateien.',
      );
      expect(
        File('supabase/schema.sql').readAsStringSync(),
        contains('create table public.price_week_skip'),
        reason: 'Der Merker braucht seine Tabelle.',
      );
      expect(
        tool,
        contains('class ArchiveUnavailable'),
        reason:
            'Nur eine 404 ist eine Aussage über die Woche — ein Timeout ist '
            'eine über die Leitung. Ohne die Unterscheidung könnte eine '
            'Netzstörung eine Woche für immer abschreiben.',
      );
      expect(
        tool,
        contains('MARK_AFTER_DAYS'),
        reason:
            'Das Archiv publiziert mit Verzug — eine junge Woche ist „noch '
            'nicht da", nicht „nie". Ohne Alters-Riegel würde die Naht '
            'zwischen Live-Takt und Archiv dauerhaft ausgeschlossen.',
      );
    });

    test('ein Zeitplan-Lauf hat keine Inputs — der Deckel braucht einen '
        'Rückfall', () {
      expect(
        workflow,
        contains("inputs.max_weeks || '100'"),
        reason:
            'Bei `schedule:` ist jeder inputs.* leer. Ohne Rückfall stünde '
            '--max-weeks "" im Aufruf, argparse bräche ab — und zwar NUR '
            'nachts, nie beim Hand-Dispatch, mit dem man es testet.',
      );
    });

    test('eine Woche ist erst mit allen drei Sorten fertig', () {
      expect(
        tool,
        contains('select=group_id,iso_year,iso_week,series'),
        reason:
            'Die „schon da"-Prüfung muss serienweise lesen: Eine Teilwoche '
            '(eine Sorte ohne Wert) gälte sonst für immer als fertig, und '
            '`ignore-duplicates` könnte die fehlende Sorte nie nachtragen.',
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
    // `merge-duplicates` gibt es seit dem Merker doch — aber ausschließlich
    // für dessen Buchhaltung: Dort muss die NEUSTE Entscheidung gewinnen,
    // sonst liefe eine Marke mit veraltetem region_key nach einem
    // Gebietswechsel als ewige Wiedervorlage. Für die PREISWERTE bleibt es
    // verboten; die Prüfung läuft je Funktion, damit ein zweiter
    // merge-Schreibpfad an price_week sofort auffällt.
    final functions = tool.split(RegExp(r'^def ', multiLine: true));
    for (final body in functions.where((f) => f.contains('merge-duplicates'))) {
      expect(
        body,
        contains('price_week_skip'),
        reason:
            'merge-duplicates außerhalb des Merker-Schreibers: Ein '
            'Nachfüll-Lauf könnte damit einen GEMESSENEN Preis still mit '
            'einem rekonstruierten überschreiben.',
      );
      expect(
        body,
        isNot(contains("'/rest/v1/price_week'")),
        reason: 'Der Merker-Schreiber fasst die Preiswerte nicht an.',
      );
    }
  });
}
