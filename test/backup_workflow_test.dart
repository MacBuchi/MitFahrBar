/// backup_workflow_test.dart – Hält den Backup-Workflow zusammen (#135).
///
/// Dieselbe Klasse wie `notify_workflow_test.dart`: Was hier schiefgeht,
/// fällt in keiner PR-CI auf, denn der Workflow läuft nur wöchentlich —
/// und ein Backup, das still weniger sichert als gedacht, merkt man erst
/// im Ernstfall, wenn es zu spät ist.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File('.github/workflows/backup.yml').readAsStringSync();
  final backup = File('tool/db_backup.sh').readAsStringSync();
  final drill = File('tool/db_restore_drill.sh').readAsStringSync();
  final schema = File('supabase/schema.sql').readAsStringSync();

  test('jede Tabelle aus schema.sql steht in der Vollständigkeitsprüfung', () {
    final tables = RegExp(
      r'create table (public\.\w+)',
    ).allMatches(schema).map((m) => m.group(1)!).toSet();
    expect(
      tables,
      isNotEmpty,
      reason: 'Ohne gefundene Tabellen prüft dieser Test nichts.',
    );
    for (final table in tables) {
      expect(
        backup,
        contains(table),
        reason:
            'Eine künftige Tabelle, die hier fehlt, fährt ungeprüft im Dump '
            'mit: Die Vollständigkeitsprüfung sähe sie nie, und ein Dump '
            'ohne sie würde still hochgeladen. Genau diese Drift soll '
            'dieser Test verhindern — $table in tool/db_backup.sh '
            'nachtragen.',
      );
    }
  });

  test('auth und supabase_migrations werden mitgesichert und mitgeprüft', () {
    for (final schemaFlag in [
      '--schema=public',
      '--schema=auth',
      '--schema=supabase_migrations',
    ]) {
      expect(
        backup,
        contains(schemaFlag),
        reason:
            'Ohne auth gibt es nach einem Restore keine Logins '
            '(group_id = auth.uid()); ohne supabase_migrations spielte die '
            'GitHub-Integration alle Migrationen erneut gegen das fertige '
            'Schema ein.',
      );
    }
    expect(backup, contains('auth.users'));
    expect(backup, contains('supabase_migrations.schema_migrations'));
    expect(
      backup,
      contains('my_group_active'),
      reason:
          'Die Funktion steht in jeder RLS-Policy — fehlte sie im Dump, '
          'scheiterte beim Einspielen schon CREATE POLICY. Dieselbe '
          'Fehlerklasse fand PilzBuddys allererster Restore-Drill.',
    );
  });

  test('der Empfänger ist ein age-Schlüssel, keine Passphrase', () {
    expect(
      RegExp(
        r'RECIPIENT="\$\{BACKUP_AGE_RECIPIENT:-age1[0-9a-z]{10,}\}"',
      ).hasMatch(backup),
      isTrue,
      reason:
          'Asymmetrisch mit Absicht: Der öffentliche Schlüssel darf ins '
          'Repo, der private bleibt beim Betreiber. Eine Passphrase als '
          'Secret könnte der Runner auch ENTschlüsseln — dann gäbe ein '
          'geleaktes Secret alle Backups her.',
    );
  });

  test('der Zeitplan meidet die volle Stunde', () {
    final cron = RegExp(r'- cron: "([^"]+)"').firstMatch(workflow)?.group(1);
    expect(cron, isNotNull, reason: 'Ohne Zeitplan läuft nie ein Backup.');
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
          'Zwei gleichzeitige Dumps wären nur Last; abbrechen wäre '
          'schlimmer — ein halb hochgeladenes Backup sieht aus wie ein '
          'ganzes.',
    );
    expect(workflow, contains('cancel-in-progress: false'));
  });

  test('der Job ruht still, solange die Secrets fehlen', () {
    expect(workflow, contains(r'secrets.SUPABASE_DB_URL'));
    expect(workflow, contains(r'secrets.BACKUP_REPO_TOKEN'));
    expect(
      workflow,
      contains('::notice::'),
      reason:
          'Ein fehlendes Secret soll den Lauf still beenden, nicht rot '
          'färben — ein dauerhaft roter Workflow stumpft ab, und wenn es '
          'wirklich brennt, schaut niemand mehr hin.',
    );
  });

  test('erst hochladen, dann drillen — und zwar die hochgeladene Datei', () {
    final uploadAt = workflow.indexOf('db_backup.sh');
    final drillAt = workflow.indexOf('db_restore_drill.sh');
    expect(uploadAt, greaterThanOrEqualTo(0));
    expect(
      drillAt,
      greaterThan(uploadAt),
      reason:
          'Scheitert der Drill VOR dem Upload, existiert kein Backup — '
          'dabei ist kaputte Wiederherstellbarkeit genau der Moment, in '
          'dem man den Dump am dringendsten behalten will.',
    );
    expect(
      workflow,
      contains('gh release download'),
      reason:
          'Gedrillt wird das Artefakt aus der Ablage, nicht die lokale '
          'Schwesterdatei — nur so ist die Ablage selbst bewiesen.',
    );
    expect(
      workflow,
      contains('BACKUP_EXTRA_RECIPIENT'),
      reason:
          'Der Drill entschlüsselt über den Wegwerf-Empfänger. Fällt der '
          'weg, müsste der private Betreiber-Schlüssel zu GitHub — genau '
          'das darf nie passieren.',
    );
  });

  test('der Drill spielt hart ein und beweist Auth', () {
    expect(
      drill,
      contains('ON_ERROR_STOP=1'),
      reason:
          'Ohne ON_ERROR_STOP läuft psql über Fehler hinweg und meldet '
          'Erfolg für einen halben Restore.',
    );
    expect(
      drill,
      contains('drop schema if exists supabase_migrations cascade'),
      reason:
          'Nach db reset steht die lokale Migrationshistorie im Stack — '
          'bliebe sie stehen, prüfte der Drill ein Mischwesen aus beidem.',
    );
    expect(
      drill,
      contains('grant_type=password'),
      reason:
          'Ein Restore, nach dem sich niemand anmelden kann, ist keiner. '
          'Der Login ist die Hälfte, die PilzBuddys Drill offen lässt.',
    );
  });
}
