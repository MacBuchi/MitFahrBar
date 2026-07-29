/// notify_workflow_test.dart – Hält den Versand-Workflow zusammen (#101).
///
/// Dieselbe Klasse wie `release_workflow_test.dart`: Was hier schiefgeht,
/// fällt in keiner PR-CI auf. Der Workflow läuft nur nach einem Merge auf
/// `main` — und wenn er dann falsch konfiguriert ist, merkt es niemand,
/// weil ausbleibende Benachrichtigungen keinen roten Lauf erzeugen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/notify.yml').readAsStringSync();
  final job = File('tool/notify.dart').readAsStringSync();

  test('der Zeitplan meidet die volle Stunde', () {
    final cron = RegExp(r'- cron: "([^"]+)"').firstMatch(workflow)?.group(1);
    expect(cron, isNotNull, reason: 'Ohne Zeitplan läuft nie etwas.');
    final minutes = cron!.split(' ').first;
    expect(
      minutes.split(',').map(int.parse),
      everyElement(greaterThan(0)),
      reason:
          'GitHub verzögert Läufe zur vollen Stunde regelmäßig um 5 bis 30 '
          'Minuten. Der Offset kostet nichts und nimmt genau diese Spitze '
          'mit.',
    );
  });

  test('zwei Läufe können sich nicht überholen', () {
    expect(
      workflow,
      contains('concurrency:'),
      reason:
          'Zwei gleichzeitige Läufe schrieben dieselben Korb-Zeilen. Der '
          'Trigger auf push_outbox vergliche dabei gegen einen halb '
          'geschriebenen Stand und setzte womöglich eine Fälligkeit, die es '
          'nicht gibt.',
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
          'Ein GitHub-Runner steht auf UTC, die Uhrzeiten in '
          'notification_prefs sind aber Ortszeit. Ohne TZ feuerte der '
          'Abend-Push im Sommer zwei Stunden zu spät — und niemand sähe '
          'einen Fehler, nur eine Nachricht zur falschen Zeit.',
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
          'Driften die Versionen, rechnet der Versand-Job mit einem anderen '
          'SDK als die Tests, die ihn absichern.',
    );
  });

  test('der Job rechnet mit der echten Fairness-Logik', () {
    expect(
      job,
      contains("import 'package:mitfahrbar/core/fairness.dart'"),
      reason:
          'Der Text nennt, wer morgen fährt — eine berechnete Kennzahl. Wer '
          'sie hier nachbaut oder den Versand nach TypeScript verschiebt, '
          'erzeugt die zweite Wahrheit über die Fairness-Regel.',
    );
    expect(job, contains('planWeek('));
  });

  test('die Anmerkungen werden sortiert gelesen (#127)', () {
    final query = job.split("api.rows('plan_notes'").last.split('});').first;
    expect(
      query,
      contains("'order': 'created_at'"),
      reason:
          'Der Digest mischt die Kennungen der Anmerkungen ein. PostgREST '
          'sichert ohne `order` keine Reihenfolge zu — der Hash unterschiede '
          'sich dann zwischen zwei Läufen ohne jede Datenänderung, und jeder '
          'Anwesende bekäme dauerhaft „Änderung"-Meldungen über eine '
          'Planänderung, die es nie gab. (Der Digest sortiert zusätzlich '
          'selbst; das hier ist die zweite Hälfte desselben Riegels und '
          'zugleich die Reihenfolge, in der die App sie anzeigt.)',
    );
  });

  test('das Konfliktziel des Korbs nennt den vollen Schlüssel', () {
    final schema = File('supabase/schema.sql').readAsStringSync();
    final key = RegExp(
      r'create table public\.push_outbox \((.*?)\n\);',
      dotAll: true,
    ).firstMatch(schema)!.group(1)!;
    final primary = RegExp(
      r'primary key \(([^)]*)\)',
    ).firstMatch(key)!.group(1)!.replaceAll(' ', '');
    expect(
      job,
      contains("onConflict: '$primary'"),
      reason:
          'Weicht es ab, meldet Postgres „no unique or exclusion constraint '
          'matching the ON CONFLICT specification" — und der Korb bliebe '
          'stehen, ohne dass jemand eine Meldung vermisst, bis der Abend '
          'kommt.',
    );
  });

  // Seit #132 rechnet dieser Job nur noch den Korb neu. Verschickt wird aus
  // der Datenbank heraus (pg_cron → flush-push). Bliebe der alte Versandweg
  // daneben stehen, gäbe es zwei Absender für dieselbe Nachricht — und der
  // Digest-Vergleich in push_log entschiede per Wettlauf, welcher gewinnt.
  test('der Job verschickt nichts mehr', () {
    expect(
      job,
      isNot(contains('send-push')),
      reason:
          'Der Versand gehört seit #132 der Datenbank. Ein zweiter Absender '
          'hier wäre ein Wettlauf um push_log.',
    );
    expect(
      job,
      contains('outboxEntries('),
      reason: 'Stattdessen schreibt er den Ausgangskorb.',
    );
  });
}
