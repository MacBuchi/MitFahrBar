/// schema_test.dart – Schützt Mandanten-Annahmen, die nur in der echten
/// Datenbank auffallen.
///
/// Dieselbe Fehlerklasse wie `android_manifest_test.dart`: Ein Schlüssel ohne
/// `group_id` kompiliert sauber, läuft im Test gegen das In-Memory-Backend
/// durch und fällt erst auf, wenn eine **zweite** Gruppe dasselbe tut.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = File('supabase/schema.sql').readAsStringSync();
  final repository = File(
    'lib/data/supabase_repository.dart',
  ).readAsStringSync();

  /// Der Primärschlüssel aus dem `create table`-Block von [table] — sowohl
  /// die Tabellen-Form `primary key (a, b)` als auch die Spalten-Form
  /// `token text primary key`.
  String primaryKeyOf(String table) {
    final block = RegExp(
      'create table public\\.$table \\((.*?)\\n\\);',
      dotAll: true,
    ).firstMatch(schema);
    expect(block, isNotNull, reason: 'Tabelle $table nicht in schema.sql');
    final body = block!.group(1)!;

    final composite = RegExp(r'primary key \(([^)]*)\)').firstMatch(body);
    if (composite != null) return composite.group(1)!;

    final inline = RegExp(
      r'^\s*(\w+)\s[^,]*\bprimary key\b',
      multiLine: true,
    ).firstMatch(body);
    expect(inline, isNotNull, reason: '$table hat keinen primary key');
    return inline!.group(1)!;
  }

  // Die Tabellen mit fachlichem (statt generiertem) Schlüssel. Bei `persons`
  // und `trips` ist der Schlüssel eine UUID und damit ohnehin global
  // eindeutig — dort wäre `group_id` im Schlüssel sinnlos.
  for (final table in [
    'plan_availability',
    'plan_overrides',
    'notification_prefs',
    'push_log',
  ]) {
    test('$table hat group_id im Primärschlüssel', () {
      expect(
        primaryKeyOf(table),
        contains('group_id'),
        reason:
            'Ohne group_id ist der Schlüssel über alle Gruppen eindeutig: '
            'Sobald eine zweite Gruppe denselben Tag plant, bricht ihr '
            'upsert mit einer Unique-Verletzung ab — auf einer Zeile, die '
            'die RLS ihr nicht einmal zeigt. Genau so lag plan_overrides '
            'bis v0.15.0 im Schema.',
      );
    });
  }

  // Push-Benachrichtigungen (Issue #101). Drei Annahmen, die alle erst in der
  // echten Datenbank auffielen — und eine bewusste Ausnahme von der Regel
  // oben, die ohne Test wie ein Versehen aussieht.
  group('Push-Benachrichtigungen', () {
    test('push_devices hat den Token als Schlüssel, nicht group_id', () {
      expect(
        primaryKeyOf('push_devices').replaceAll(' ', ''),
        'token',
        reason:
            'Bewusste Ausnahme von der group_id-Regel: FCM-Token sind '
            'global eindeutig, eine Kollision zwischen Gruppen ist '
            'konstruktiv unmöglich. Und ein Gerät gehört zu genau EINER '
            'Gruppe — mit (group_id, token) bliebe beim Gruppenwechsel die '
            'alte Zeile stehen, und die alte Gruppe bekäme weiter '
            'Nachrichten auf ein Gerät, das ihr nicht mehr gehört.',
      );
    });

    test('push_log hat RLS an und bewusst keine einzige Policy', () {
      expect(
        schema,
        contains(
          'alter table public.push_log            enable row level security',
        ),
        reason: 'Ohne RLS läse jeder authenticated das Versand-Gedächtnis.',
      );
      expect(
        RegExp(r'create policy \w+ on public\.push_log').hasMatch(schema),
        isFalse,
        reason:
            'Das Gedächtnis gehört allein dem Versand-Job. Mit einer '
            'Client-Policy könnte jedes Mitglied Nachrichten unterdrücken '
            '(Zeile anlegen) oder erneut auslösen (Zeile löschen) — '
            'dasselbe Muster wie bei group_admins.',
      );
    });

    test('register_push_device prüft die Gruppe der Person', () {
      final function = RegExp(
        r'create or replace function public\.register_push_device.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains('p.group_id = me'),
        reason:
            'Ohne die Prüfung könnte eine Gruppe ihre Zustellung an eine '
            'fremde person_id hängen — und bekäme Nachrichten über die '
            'Verfügbarkeit einer Person, die sie nie sehen darf.',
      );
      expect(
        function,
        contains('delete from public.push_devices where token'),
        reason:
            'Der Gruppenwechsel eines Geräts muss die alte Zeile entfernen. '
            'Sie liegt unter fremder group_id, die RLS zeigt sie nicht — '
            'ein blanker Upsert liefe in eine Unique-Verletzung auf einer '
            'unsichtbaren Zeile.',
      );
    });

    test('das Konfliktziel der Einstellungen nennt den Primärschlüssel', () {
      final targets = RegExp(r"onConflict: '([^']*)'")
          .allMatches(File('lib/data/push_repository.dart').readAsStringSync())
          .map((m) => m.group(1))
          .toList();
      expect(
        targets,
        contains(primaryKeyOf('notification_prefs').replaceAll(' ', '')),
        reason:
            'Weicht das Konfliktziel vom Schlüssel ab, meldet Postgres beim '
            'Speichern „no unique or exclusion constraint matching the ON '
            'CONFLICT specification" — und zwar erst am Gerät.',
      );
    });
  });

  // `app_config` hält die Mindestversion, die veraltete Clients aussperrt.
  // Eine Schreib-Policy dort wäre der Weg, sich selbst auszusperren: Ein
  // Client könnte den Wert hochsetzen und käme nie wieder in die App. Der
  // Wert gehört ausschließlich in Migrationen.
  test('app_config ist für Clients nur lesbar', () {
    final policies = RegExp(
      r'create policy \w+ on public\.app_config\s+for (\w+)',
    ).allMatches(schema).map((m) => m.group(1)).toList();

    expect(policies, isNotEmpty, reason: 'ohne Policy liest niemand die Zeile');
    expect(
      policies,
      everyElement('select'),
      reason:
          'Nur SELECT. Mit „for all" oder einer insert/update-Policy könnte '
          'ein Client die Mindestversion hochsetzen und damit die ganze '
          'Gruppe aussperren.',
    );
  });

  // Weicht das Konfliktziel vom Schlüssel ab, meldet Postgres beim Speichern
  // „there is no unique or exclusion constraint matching the ON CONFLICT
  // specification". Auch das sieht man erst am Gerät.
  test('die upsert-Konfliktziele nennen genau den Primärschlüssel', () {
    final targets = RegExp(
      r"onConflict: '([^']*)'",
    ).allMatches(repository).map((m) => m.group(1)).toList();

    expect(
      targets,
      contains(primaryKeyOf('plan_availability').replaceAll(' ', '')),
      reason: 'setAvailability muss auf den vollen Schlüssel upserten.',
    );
    expect(
      targets,
      contains(primaryKeyOf('plan_overrides').replaceAll(' ', '')),
      reason: 'setPlanDriver muss auf den vollen Schlüssel upserten.',
    );
  });

  // Mehrere Fahrer je Tag (Issue #62): Das Datenmodell ist „eine Zeile je
  // Fahrer" — und der Umbau dorthin war der erste echte Einsatz des
  // Mindestversions-Musters.
  group('Mehrere Fahrer je Tag (Issue #62)', () {
    test('plan_overrides-Schlüssel ist exakt eine Zeile je Fahrer', () {
      expect(
        primaryKeyOf('plan_overrides').replaceAll(' ', ''),
        'group_id,plan_date,driver_id',
        reason:
            'Fällt driver_id aus dem Schlüssel, passt wieder nur ein '
            'Fahrer je Tag und das Speichern der Menge bricht; jede '
            'weitere Spalte erlaubte Duplikate desselben Fahrers.',
      );
    });

    test('die Schlüssel-Migration hebt die Mindestversion im selben File', () {
      final migration = File(
        'supabase/migrations/20260724090000_plan_overrides_multi_driver.sql',
      ).readAsStringSync();
      expect(
        migration,
        contains('add primary key (group_id, plan_date, driver_id)'),
      );
      expect(
        migration,
        contains("key = 'min_supported_version'"),
        reason:
            'Der Schlüsselwechsel bricht den Upsert veröffentlichter '
            'Clients („no unique or exclusion constraint …"). Die Regel '
            'aus CLAUDE.md: Wer entfernt, was ein Client nutzt, hebt IM '
            'SELBEN FILE die Mindestversion — sonst scheitern alte '
            'Clients still, statt zum Update geführt zu werden.',
      );
    });
  });

  // Verwalter-Konsole (Issue #55): Die Sicherheit hängt an drei Annahmen,
  // die alle nur in der echten Datenbank auffallen würden.
  group('Verwalter-Konsole', () {
    test('groups hat weiterhin keine Delete-Policy', () {
      final policies = RegExp(
        r'create policy \w+ on public\.groups\s+for (\w+)',
      ).allMatches(schema).map((m) => m.group(1)).toList();

      expect(
        policies,
        isNot(contains('delete')),
        reason:
            'Gelöscht wird ausschließlich über admin_delete_group — eine '
            'Delete-Policy gäbe jedem Mitglied des geteilten Logins die '
            'Löschtaste.',
      );
      expect(
        policies,
        isNot(contains('all')),
        reason: '„for all" wäre delete.',
      );
    });

    test('group_admins hat RLS an und bewusst keine einzige Policy', () {
      expect(
        schema,
        contains(
          'alter table public.group_admins        enable row level '
          'security',
        ),
        reason: 'Ohne RLS läse jeder authenticated die Verknüpfungen.',
      );
      expect(
        RegExp(r'create policy \w+ on public\.group_admins').hasMatch(schema),
        isFalse,
        reason:
            'Jede Policy öffnete die Tabelle für Clients — der Zugriff '
            'gehört ausschließlich den SECURITY-DEFINER-Funktionen.',
      );
    });

    test('der Signup-Trigger überspringt Verwalter-Konten', () {
      final trigger = RegExp(
        r'create or replace function public\.handle_new_group.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(trigger, isNotNull);
      expect(
        trigger,
        contains("account_type' = 'admin'"),
        reason:
            'Ohne die Ausnahme erzeugte jede Konsolen-Registrierung eine '
            'Geister-„pending"-Gruppe in der Freigabeliste.',
      );
    });

    test('admin_delete_group löscht über auth.users, nicht Datentabellen', () {
      final function = RegExp(
        r'create or replace function public\.admin_delete_group.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains('delete from auth.users'),
        reason:
            'Der Auth-User ist die Wurzel der Kaskade (groups.id → '
            'auth.users): Nur so verschwinden Login, Gruppe und alle Daten '
            'ohne Reste. Einzelne Tabellen zu löschen hieße, bei jeder '
            'neuen Tabelle ans Nachziehen denken zu müssen.',
      );
      expect(
        function,
        isNot(contains('delete from public.')),
        reason: 'Kein Einzel-Löschen von Datentabellen — die Kaskade trägt.',
      );
    });

    test('admin_release_group löst NUR die Verknüpfung, mit Sudo', () {
      final function = RegExp(
        r'create or replace function public\.admin_release_group.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(
        function,
        isNotNull,
        reason: 'Die Übergabe (#73) braucht den RPC.',
      );
      expect(
        function,
        contains("crypt(admin_password, own)"),
        reason:
            'Ohne Sudo-Abfrage könnte jede offene Sitzung die Konsole '
            'freigeben — und ein Mitglied mit Gruppenpasswort übernähme sie.',
      );
      expect(
        function,
        contains('delete from public.group_admins'),
        reason: 'Gelöst wird nur die Verknüpfungszeile …',
      );
      expect(
        function,
        isNot(contains('delete from auth.users')),
        reason:
            '… nie ein Auth-User: Lösen ist eine Übergabe, kein Löschen — '
            'Gruppendaten und Verwalter-Konto bleiben bestehen.',
      );
    });

    test(
      'ein Konto trägt mehrere Gruppen, eine Gruppe nur einen Verwalter',
      () {
        final table = RegExp(
          r'create table public\.group_admins.*?\);',
          dotAll: true,
        ).firstMatch(schema)?.group(0);
        expect(table, isNotNull);
        expect(
          table,
          contains('primary key (user_id, group_id)'),
          reason:
              'Mit `user_id` allein als Schlüssel wäre der Deckel von fünf '
              'Gruppen unmöglich — das Schema erlaubte genau eine.',
        );
        expect(
          table,
          contains('group_id uuid unique'),
          reason:
              'Die Eindeutigkeit bleibt: Höchstens EIN Verwalter je Gruppe '
              '(#55). Fällt sie, könnten zwei Konten dieselbe Gruppe '
              'beanspruchen und einander die Passwörter überschreiben.',
        );
      },
    );

    test('der Deckel von fünf Gruppen hängt an einem Trigger', () {
      final function = RegExp(
        r'create or replace function public\.enforce_group_admin_cap.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(
        function,
        isNotNull,
        reason:
            'Der Deckel muss serverseitig gelten — ein Limit nur im UI ist '
            'kein Limit.',
      );
      expect(function, contains('>= 5'));
      expect(
        function,
        contains('pg_advisory_xact_lock'),
        reason:
            'Ohne den Riegel zählen zwei gleichzeitige Anlagen beide den '
            'Stand vor der jeweils anderen — dann entstehen sechs Gruppen.',
      );
      expect(
        schema,
        contains('before insert on public.group_admins'),
        reason:
            'Als Trigger und nicht als Funktion: `alter default privileges` '
            'gibt authenticated execute auf jede Funktion. Eine aufrufbare '
            '„verknüpfe mich"-Funktion wäre die Übernahme-Lücke — jedes '
            'Konto könnte sich an jede unverknüpfte Gruppe hängen, ohne das '
            'Gruppenpasswort zu kennen.',
      );
    });

    test('jede Aktion nennt ihre Gruppe, und Löschen trifft nur sie', () {
      expect(
        schema,
        contains('my_admin_groups('),
        reason: 'Die Konsole liest jetzt eine Liste.',
      );
      expect(
        RegExp(r'my_admin_group\(').hasMatch(schema),
        isFalse,
        reason:
            'Die Einzelform muss weg: Bei mehreren Gruppen zeigte sie eine '
            'beliebige davon, und ein alter Client träfe damit die falsche.',
      );
      final function = RegExp(
        r'create or replace function public\.admin_delete_group.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, contains('target_group'));
      expect(
        RegExp(r'delete from auth\.users').allMatches(function!).length,
        1,
        reason:
            'Genau eine Löschung — die der Zielgruppe. Ein zweites Delete '
            'auf `auth.uid()` nähme das Verwalter-Konto mit und damit den '
            'Zugang zu dessen übrigen Gruppen.',
      );
    });

    test('der Lebenszyklus ist vorbereitet: archived und released_at', () {
      expect(
        schema,
        contains(
          "check (status in ('pending', 'active', 'rejected', "
          "'archived'))",
        ),
        reason:
            'Stilllegen ist damit ein Statuswechsel: `my_group_active()` '
            'prüft auf \'active\', eine archivierte Gruppe ist also über '
            'alle Policies hinweg still — verlustfrei und umkehrbar. Ohne '
            'den erlaubten Wert bräuchte das später eine Constraint-'
            'Migration UND ein Client-Release.',
      );
      expect(
        schema,
        contains('released_at timestamptz'),
        reason:
            'Markiert Gruppen ohne Verwalter. Ohne den Zeitstempel wäre eine '
            'laufende Übergabe von einer echten Waise nicht zu '
            'unterscheiden.',
      );
      expect(
        schema,
        contains('after delete on public.group_admins'),
        reason:
            'Der Trigger fängt beide Wege — das absichtliche Lösen UND die '
            'Kaskade eines gelöschten Verwalter-Kontos. Der zweite wäre '
            'sonst eine stille Waise.',
      );
    });

    test('die Konsolen-Migration hebt die Mindestversion im selben File', () {
      final migration = File(
        'supabase/migrations/20260726153700_console_group_creation.sql',
      ).readAsStringSync();
      expect(migration, contains('add primary key (user_id, group_id)'));
      expect(
        migration,
        contains('drop function public.my_admin_group();'),
        reason:
            '`create or replace` kann keine Signatur ändern — ohne das Drop '
            'bliebe die alte Fassung als Overload stehen.',
      );
      expect(
        migration,
        contains("key = 'min_supported_version'"),
        reason:
            'Das File entfernt Funktionen, die veröffentlichte Clients '
            'aufrufen. Die Regel aus CLAUDE.md: Wer entfernt, was ein Client '
            'nutzt, hebt IM SELBEN FILE die Mindestversion.',
      );
    });
  });
}
