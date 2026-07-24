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

  /// Der `primary key (...)`-Ausdruck aus dem `create table`-Block von
  /// [table].
  String primaryKeyOf(String table) {
    final block = RegExp(
      'create table public\\.$table \\((.*?)\\n\\);',
      dotAll: true,
    ).firstMatch(schema);
    expect(block, isNotNull, reason: 'Tabelle $table nicht in schema.sql');
    final key = RegExp(r'primary key \(([^)]*)\)').firstMatch(block!.group(1)!);
    expect(key, isNotNull, reason: '$table hat keinen primary key');
    return key!.group(1)!;
  }

  // Die Tabellen mit fachlichem (statt generiertem) Schlüssel. Bei `persons`
  // und `trips` ist der Schlüssel eine UUID und damit ohnehin global
  // eindeutig — dort wäre `group_id` im Schlüssel sinnlos.
  for (final table in ['plan_availability', 'plan_overrides']) {
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
  });
}
