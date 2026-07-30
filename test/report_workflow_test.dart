/// report_workflow_test.dart – Hält den Nutzungsbericht zusammen (#134).
///
/// Dieselbe Klasse wie `notify_workflow_test.dart`: Der Workflow läuft nur
/// nach Zeitplan auf `main` — was hier schiefgeht, fällt in keiner PR-CI
/// auf, und ein ausbleibender oder still falscher Bericht erzeugt keinen
/// roten Lauf.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '.github/workflows/usage-report.yml',
  ).readAsStringSync();
  final job = File('tool/usage_report.dart').readAsStringSync();

  test('der Zeitplan meidet die volle Stunde', () {
    final cron = RegExp(r'- cron: "([^"]+)"').firstMatch(workflow)?.group(1);
    expect(cron, isNotNull, reason: 'Ohne Zeitplan läuft nie etwas.');
    final minutes = cron!.split(' ').first;
    expect(
      minutes.split(',').map(int.parse),
      everyElement(greaterThan(0)),
      reason:
          'GitHub verzögert Läufe zur vollen Stunde regelmäßig um 5 bis 30 '
          'Minuten — der Offset kostet nichts.',
    );
  });

  test('zwei Läufe können sich nicht überholen', () {
    expect(
      workflow,
      contains('concurrency:'),
      reason:
          'Zwei gleichzeitige Läufe bearbeiteten dasselbe Issue und posteten '
          'den Mail-Kommentar doppelt.',
    );
    expect(workflow, contains('cancel-in-progress: false'));
  });

  test('der Job ruht, solange die Secrets fehlen', () {
    expect(workflow, contains(r'secrets.SUPABASE_SERVICE_ROLE_KEY'));
    expect(
      workflow,
      contains('::notice::'),
      reason:
          'Ein fehlendes Secret soll den Lauf still beenden, nicht rot '
          'färben — sonst steht der Workflow dauerhaft auf Fehler und '
          'niemand schaut mehr hin.',
    );
  });

  test('der Job rechnet in deutscher Zeit', () {
    expect(
      workflow,
      contains('TZ: Europe/Berlin'),
      reason:
          'Der Wochenschnitt (Montag) muss in deutscher Zeit fallen — in '
          'UTC zählte eine Sonntagsfahrt kurz vor Mitternacht zur falschen '
          'Woche.',
    );
  });

  test('die Flutter-Version ist dieselbe wie in der CI', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final version = RegExp(
      r'FLUTTER_VERSION:\s*"([^"]+)"',
    ).firstMatch(ci)?.group(1);
    expect(version, isNotNull);
    expect(
      workflow,
      contains('FLUTTER_VERSION: "$version"'),
      reason:
          'Driften die Versionen, rechnet der Bericht mit einem anderen SDK '
          'als die Tests, die seine Formeln absichern.',
    );
  });

  test('das Issue-Schreiben ist erlaubt', () {
    expect(
      workflow,
      contains('issues: write'),
      reason:
          'Ohne die Permission scheitert jeder gh-Aufruf — und zwar erst am '
          'Montag früh, nicht in der PR-CI.',
    );
    expect(workflow, contains(r'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}'));
  });

  test('die Ersparnis kommt aus der echten Fairness-Logik', () {
    expect(
      job,
      contains("import 'package:mitfahrbar/core/fairness.dart'"),
      reason:
          'Ersparnis und Kilometer sind berechnete Kennzahlen. Hier '
          'nachgebaut wären sie die zweite Wahrheit über dieselbe Formel — '
          'und niemand merkte es, solange beide zufällig gleich rechnen.',
    );
    expect(job, contains('computeStats('));
    expect(job, contains('savedCosts('));
    expect(job, contains('kilometers('));
    expect(
      job,
      contains('isoWeekNumber('),
      reason:
          'Auch die Kalenderwoche existiert schon in fairness.dart, '
          'getestet inkl. der W53-Kanten — ein Nachbau driftete genau dort.',
    );
  });

  // Anonymisierung strukturell: Namen und Freitexte erreichen den Speicher
  // des Jobs nie — dann können sie auch nicht ins öffentliche Log oder ins
  // Issue geraten.
  test('Namen und Notizen werden gar nicht erst geladen', () {
    final personsSelect = job.split("rows('persons'").last.split('});').first;
    expect(
      personsSelect,
      isNot(contains('name')),
      reason:
          'savedCosts braucht nur Energieart und Verbrauch. Läge der Name '
          'im Speicher, wäre „anonymisiert" nur noch eine Behauptung.',
    );
    expect(
      job,
      contains("name: ''"),
      reason: 'Die Person wird ohne Namen von Hand gebaut.',
    );
    final tripsSelect = job.split("rows('trips'").last.split('});').first;
    expect(
      tripsSelect,
      isNot(contains('note')),
      reason:
          'Die Fahrt-Notiz ist Freitext und kann Namen tragen — der Bericht '
          'braucht sie nicht.',
    );
    expect(
      job,
      isNot(contains('groups(name)')),
      reason: 'Auch Gruppennamen gehören nicht in den Bericht.',
    );
  });

  test('das Paging fängt den stillen 1000-Zeilen-Deckel', () {
    expect(
      job,
      contains("'Range': "),
      reason:
          'Hosted-PostgREST liefert höchstens 1000 Zeilen je Antwort — ohne '
          'Paging stünde ab der 1001. Fahrt eine still zu niedrige Zahl im '
          'Bericht, und niemand sähe einen Fehler.',
    );
  });

  test('der Bericht trägt die Trend-Charts', () {
    expect(
      job,
      contains('xychart-beta'),
      reason:
          'Die Mermaid-Charts sind Marcus\' Wunsch vom 30.07. — GitHub '
          'rendert sie nativ im Issue. Ohne den Pin verschwände die '
          'Chart-Hälfte lautlos bei einem „Aufräumen" des Bodys.',
    );
    expect(
      job,
      contains('plotColorPalette'),
      reason:
          'Ohne die Farb-Angabe fällt Mermaid auf sein Standard-Blau '
          'zurück — der Bericht soll das App-Teal tragen.',
    );
  });

  test('der Bericht landet als ops-Issue mit Mail-Kommentar', () {
    expect(job, contains("'ops'"));
    expect(
      job,
      contains('Usage report'),
      reason:
          'Gefunden wird das dauerhafte Issue über diesen Titel-Präfix — '
          'unter demselben Label liegen auch die Error-Digest-Issues.',
    );
    expect(
      job,
      contains('/comments'),
      reason:
          'Der Kommentar ist der Mail-Auslöser: GitHub verschickt neue '
          'Kommentare mit vollem Text und Link, das Umschreiben des '
          'Issue-Texts nicht (Entscheidung Marcus, #134). Er geht über die '
          'REST-API — `gh issue comment` scheiterte mit dem '
          'Actions-GITHUB_TOKEN an „Resource not accessible by integration" '
          '(30.07.2026).',
    );
  });
}
