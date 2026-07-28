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

  /// [sql] ohne `--`-Kommentare.
  ///
  /// Nötig für jede Prüfung der Form „dieser Name kommt nicht mehr vor":
  /// Gerade ein Rückbau wird im File ausführlich begründet, und die
  /// Begründung nennt zwangsläufig, was entfernt wurde. Ohne diesen Filter
  /// scheitert so ein Test an seinem eigenen Kommentar — was hier beim
  /// Schreiben von #108 auch passiert ist.
  String sqlOnly(String sql) => sql
      .split('\n')
      .map((line) {
        final comment = line.indexOf('--');
        return comment == -1 ? line : line.substring(0, comment);
      })
      .join('\n');

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

    test('der Ausgangskorb ist für Clients weder les- noch schreibbar', () {
      expect(
        RegExp(r'create policy \w+ on public\.push_outbox').hasMatch(schema),
        isFalse,
        reason:
            'Im Korb steht der vorgeschlagene Fahrer im Klartext — die '
            'einzige Ausnahme von „wird nie gespeichert" (#132). Sie hängt '
            'daran, dass der Client ihn nicht zurücklesen kann: Sonst '
            'entstünde neben fairness.dart eine zweite Wahrheit darüber, wer '
            'fährt. Geschrieben wird über publish_push_outbox.',
      );
      expect(
        sqlOnly(schema),
        contains('revoke all on public.push_outbox from anon, authenticated'),
        reason:
            'Der Sammel-Grant weiter oben gibt Rechte auf JEDE Tabelle. Ohne '
            'die Rücknahme hinge der Riegel allein daran, dass niemand '
            'später eine Policy ergänzt.',
      );
    });

    test('der Korb-Schlüssel trägt die group_id', () {
      expect(
        primaryKeyOf('push_outbox').replaceAll(' ', ''),
        'group_id,person_id,plan_date',
        reason:
            'Fachlicher Schlüssel: Ohne group_id wäre (person_id, plan_date) '
            'über alle Gruppen eindeutig, und die zweite Gruppe liefe beim '
            'Schreiben in eine Unique-Verletzung auf einer Zeile, die sie '
            'nicht einmal sehen darf.',
      );
    });

    test('das Entprellen schiebt nur bei geändertem Inhalt', () {
      final function = RegExp(
        r'create or replace function public\.push_outbox_debounce.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains('is distinct from'),
        reason:
            'Der stündliche Reparatur-Job schreibt dieselben Zeilen immer '
            'wieder. Ohne den Vergleich setzte der Trigger die Fälligkeit '
            'auch dann neu und schöbe sie stündlich vor sich her — es würde '
            'NIE etwas gesendet, und im Log stünde kein Fehler.',
      );
    });

    test('der Schreibweg kann nur in den eigenen Korb schreiben', () {
      final function = RegExp(
        r'create or replace function public\.publish_push_outbox.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains('gid uuid := auth.uid()'),
        reason:
            'Die group_id muss aus der Sitzung kommen und nie aus der '
            'Nutzlast — sonst schriebe ein gebastelter Aufruf in fremde '
            'Körbe, und `authenticated` hat EXECUTE auf jede Funktion.',
      );
      expect(
        function,
        contains('person.group_id = gid'),
        reason:
            'Ohne den Join hinge eine Zeile an einer gruppenfremden '
            'person_id. Der Fremdschlüssel auf persons prüft nur, dass es '
            'die Person GIBT, nicht wem sie gehört.',
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
            'Geister-„pending"-Gruppe, die niemandem gehört.',
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

  // Die Freigabe ist abgeschafft (Issue #108). Was hier geprüft wird, ist
  // nicht der Rückbau selbst — der fällt beim Kompilieren auf —, sondern die
  // Zusicherung, dass keine Gruppe sich künftig selbst freischalten kann und
  // dass die Migration in einer Reihenfolge läuft, die Postgres akzeptiert.
  group('Keine Admin-Gruppe mehr (Issue #108)', () {
    final migration = File(
      'supabase/migrations/20260726172000_retire_admin_group.sql',
    ).readAsStringSync();

    test('groups hat keine Update-Policy', () {
      final policies = RegExp(
        r'create policy \w+ on public\.groups\s+for (\w+)',
      ).allMatches(schema).map((m) => m.group(1)).toList();

      expect(
        policies,
        isNot(contains('update')),
        reason:
            'Eine Update-Policy auf `groups` wäre der Selbstbedienungs-Weg zum '
            'eigenen `status`: Ein Client könnte sich freischalten oder eine '
            'Archivierung zurückdrehen. Genau deshalb brauchte die alte '
            'Freigabe eine Sonderrolle — Gruppen ändern sich nur noch über '
            'SECURITY-DEFINER-Funktionen und den Service-Role-Key.',
      );
      expect(
        policies,
        isNot(contains('all')),
        reason: '„for all" wäre update.',
      );
    });

    test('is_admin und is_group_admin sind restlos verschwunden', () {
      expect(
        sqlOnly(schema),
        isNot(contains('is_admin')),
        reason:
            'Das Flag saß auf einem GETEILTEN Gruppen-Login ohne „Passwort '
            'vergessen", und es gab keinen Code-Weg, es zu setzen. Genau das '
            'hat am 26.07.2026 eine Freigabe unmöglich gemacht.',
      );
      expect(
        sqlOnly(schema),
        isNot(contains('is_group_admin')),
        reason:
            'Die Funktion hing an der Spalte; bliebe sie stehen, verweigerte '
            'Postgres das `drop column` wegen der Abhängigkeit.',
      );
    });

    test('die Migration schreibt handle_new_group VOR dem drop column', () {
      final rewrite = migration.indexOf(
        'create or replace function public.handle_new_group',
      );
      final dropColumn = migration.indexOf(
        'alter table public.groups drop column is_admin',
      );
      expect(rewrite, greaterThan(-1));
      expect(dropColumn, greaterThan(-1));
      expect(
        rewrite,
        lessThan(dropColumn),
        reason:
            'Die alte Fassung führt `is_admin` in ihrer Insert-Spaltenliste. '
            'Fiele die Spalte zuerst, scheiterte in diesem Moment JEDER '
            'Signup — auch der eines Verwalter-Kontos. Umgekehrt ist es '
            'unkritisch: Die neue Fassung läuft auch gegen die noch '
            'vorhandene Spalte, die einen Default hat.',
      );
    });

    test('die Migration droppt die Policies vor der Funktion', () {
      final dropPolicy = migration.indexOf(
        'drop policy groups_admin_update on public.groups',
      );
      final dropFunction = migration.indexOf(
        'drop function public.is_group_admin()',
      );
      expect(dropPolicy, greaterThan(-1));
      expect(dropFunction, greaterThan(-1));
      expect(
        dropPolicy,
        lessThan(dropFunction),
        reason:
            'Beide Policies rufen die Funktion auf — in der anderen '
            'Reihenfolge bricht die Migration mit einem '
            'Abhängigkeitsfehler ab.',
      );
    });

    test('die Altlast wird differenziert aufgelöst, nicht pauschal', () {
      expect(
        migration,
        stringContainsInOrder([
          "set status = 'active'",
          'exists (select 1 from public.group_admins',
          'delete from auth.users',
          'not exists (select 1 from public.group_admins',
        ]),
        reason:
            'Verknüpfte pending-Gruppen gehören einem Verwalter, der sich '
            'ausgewiesen hat — sie werden aktiv. Unverknüpfte sind Fremd- '
            'oder Testsignups ohne Besitzer und ohne Inhalt (die RLS '
            'verbietet einer nicht-aktiven Gruppe jedes Schreiben). Eine '
            'pauschale Behandlung würde entweder Gruppen ohne Zuordnung '
            'stehenlassen oder die eines Verwalters löschen.',
      );
      expect(
        sqlOnly(migration),
        isNot(contains('rejected')),
        reason:
            'Ein ausgesprochenes Nein ist eine Entscheidung, kein Rest — '
            "'rejected' bleibt liegen. Die Migration darf diese Zeilen weder "
            'aktivieren noch löschen.',
      );
    });

    test('die Admin-Gruppe fällt nur, wenn sie frei UND leer ist', () {
      final block = sqlOnly(
        migration,
      ).split("g.handle = 'fahrgemeinschaft'").last.split(');').first;
      expect(
        block,
        stringContainsInOrder([
          'not exists',
          'group_admins',
          'not exists',
          'persons',
          'not exists',
          'trips',
        ]),
        reason:
            'Der Schritt muss selbstprüfend bleiben. Zu `delete … where '
            "handle = 'fahrgemeinschaft'` vereinfacht, risse er auf einer "
            'anderen Instanz eine Gruppe samt Daten mit — oder hier eine, an '
            'der inzwischen doch etwas hängt. Die Bedingungen sind der Grund, '
            'warum ein namentlicher Treffer in einer Migration überhaupt '
            'vertretbar ist.',
      );
    });

    test('die Migration hebt die Mindestversion NICHT', () {
      expect(
        sqlOnly(migration),
        isNot(contains('min_supported_version')),
        reason:
            'Hier wäre Heben schädlicher als der Schaden, den es verhindert. '
            'Der 0.37.0-Client bricht nicht: `json[\'is_admin\'] as bool? ?? '
            'false` fängt die entfernte Spalte ab, die Selects laufen ins '
            'Leere statt in Fehler. Erzwingen würde nur jeden veralteten '
            'Client auf den Sperr-Schirm werfen — dessen Update-Knopf war bis '
            '0.37.0 tot, und wer davorsteht, erreicht kein Fix mehr. Aus dem '
            'Loch kann man sich nicht heraus-releasen.',
      );
    });
  });

  group('Anmerkungen am Plantag (Issue #127)', () {
    final migration = File(
      'supabase/migrations/20260727173000_plan_notes.sql',
    ).readAsStringSync();

    test('die Tabelle ist gegen fremde Gruppen dicht', () {
      expect(
        schema,
        contains(
          'alter table public.plan_notes          enable row level security',
        ),
        reason:
            'Ohne RLS läse jede Gruppe die Anmerkungen jeder anderen. Die '
            'Ausrichtung ist Absicht: Der Block ist auf trip_participations '
            'ausgerichtet, und zwei Prüfungen hier vergleichen Zeilen '
            'daraus wörtlich.',
      );
      expect(
        sqlOnly(schema),
        stringContainsInOrder([
          'create policy plan_notes_isolated on public.plan_notes',
          'group_id = auth.uid() and public.my_group_active()',
          'with check (group_id = auth.uid() and public.my_group_active())',
        ]),
        reason:
            'Ohne `with check` könnte ein Client eine Zeile mit fremder '
            'group_id einfügen; ohne my_group_active() schriebe eine '
            'archivierte Gruppe weiter.',
      );
    });

    test('der Schlüssel ist eine generierte Kennung', () {
      expect(
        primaryKeyOf('plan_notes'),
        contains('id'),
        reason:
            'Anmerkungen haben keinen fachlichen Schlüssel — mehrere je Tag '
            'und Person sind der Normalfall. Deshalb steht plan_notes '
            'bewusst NICHT in der group_id-im-Schlüssel-Schleife oben: Eine '
            'UUID ist über alle Gruppen ohnehin eindeutig, dort wäre '
            'group_id sinnlos. Vorlage ist feedback, nicht plan_availability.',
      );
    });

    test('leere Anmerkungen kommen nicht in die Datenbank', () {
      expect(
        sqlOnly(schema),
        contains('char_length(btrim(body)) between 1 and 500'),
        reason:
            '`btrim` ist nicht kosmetisch: Ohne ihn ließe der Check 500 '
            'Leerzeichen durch, und die Anzeige stünde vor einer leeren '
            'Zeile, die sie nicht erklären kann. Der Screen spiegelt '
            'dieselbe Prüfung, damit niemand einen rohen Postgres-Fehler '
            'sieht.',
      );
    });

    test('die Gruppe nimmt ihre Anmerkungen beim Löschen mit', () {
      final table = RegExp(
        r'create table public\.plan_notes \((.*?)\n\);',
        dotAll: true,
      ).firstMatch(schema)!.group(1)!;
      expect(
        table,
        contains('references public.groups(id) on delete cascade'),
        reason:
            'admin_delete_group löscht ausschließlich den Auth-User und '
            'verlässt sich auf die Kaskade. Ohne sie bliebe hier ein Rest '
            'einer gelöschten Gruppe stehen.',
      );
    });

    test('die Migration setzt die Grants selbst', () {
      expect(
        sqlOnly(migration),
        stringContainsInOrder([
          'grant select, insert, update, delete on public.plan_notes',
          'grant all on public.plan_notes to service_role',
        ]),
        reason:
            'Neuere Stacks sind „secure by default": Ohne Grant fände die '
            'App die Tabelle auf einem frischen Stack nicht.',
      );
    });

    test('die Migration hebt die Mindestversion NICHT', () {
      expect(
        sqlOnly(migration),
        isNot(contains("value = '")),
        reason:
            'Eine reine Neuanlage entfernt und benennt nichts um, was ein '
            'veröffentlichter Client liest — ältere Clients kennen die '
            'Tabelle schlicht nicht. Heben würde nur jeden veralteten '
            'Client auf den Sperr-Schirm werfen.',
      );
    });
  });

  group('persons.name ist je Gruppe eindeutig (Issue #109)', () {
    final migration = File(
      'supabase/migrations/20260726213000_persons_name_unique_per_group.sql',
    ).readAsStringSync();

    test('das Gesamtbild trägt keinen globalen Unique auf dem Namen', () {
      final table = schema
          .split('create table public.persons')
          .last
          .split(');')
          .first;
      expect(
        table,
        isNot(contains('unique')),
        reason:
            'Ein `name text unique` gilt über ALLE Gruppen. Die zweite Gruppe '
            'kann dann keine „Anna" anlegen und erfährt an der Fehlermeldung, '
            'dass der Name woanders existiert — genau der Querverweis, den die '
            'RLS sonst unmöglich macht.',
      );
    });

    test('dafür einen Index je Gruppe, normalisiert', () {
      expect(
        sqlOnly(schema),
        stringContainsInOrder([
          'create unique index persons_group_name_key',
          'public.persons',
          'group_id',
          'lower(btrim(name))',
        ]),
        reason:
            '`lower(btrim())` ist genau die Abbildung, mit der '
            'core/csv_import.dart Namen auf Personen zuordnet '
            '(`name.trim().toLowerCase()`). Driftete beides auseinander, fände '
            'der Import zu einem Namen zwei Zeilen und schriebe Fahrten auf '
            'die falsche Person.',
      );
    });

    test('der Index nimmt Inaktive nicht aus', () {
      final index = sqlOnly(
        migration,
      ).split('create unique index').last.split(';').first;
      expect(
        index,
        isNot(contains('where')),
        reason:
            'Ein `where active` gäbe den Namen einer inaktiven Person frei. '
            'Wer zurückkommt, wird aber reaktiviert — eine zweite Zeile '
            'spaltete seine Punkte-Historie und verschöbe rückwirkend die '
            'Quote aller anderen. Dieselbe Begründung, aus der es kein '
            'deletePerson gibt.',
      );
    });

    test('der alte Constraint fällt, bevor der Index kommt', () {
      final sql = sqlOnly(migration);
      expect(
        sql.indexOf('drop constraint persons_name_key'),
        lessThan(sql.indexOf('create unique index')),
        reason:
            'Umgekehrt stünden für einen Moment beide Regeln, und die alte ist '
            'die strengere — auf einer Instanz mit „Anna" in zwei Gruppen '
            'scheiterte der Index dann an Daten, die er selbst erlauben soll.',
      );
    });

    test('die Migration hebt die Mindestversion NICHT', () {
      expect(
        sqlOnly(migration),
        isNot(contains("value = '")),
        reason:
            'Ein veröffentlichter Client liest keinen Constraint: Er bricht '
            'nicht und zeigt nichts Falsches — er kann danach mehr als vorher. '
            'Heben würde nur jeden veralteten Client auf den Sperr-Schirm '
            'werfen, für einen Gewinn, den er ohne Update ohnehin hat.',
      );
    });
  });
}
