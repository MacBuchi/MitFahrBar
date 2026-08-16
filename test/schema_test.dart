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
    'plan_defaults',
    'plan_car_defaults',
    'plan_overrides',
    'notification_prefs',
    'push_log',
    'price_week',
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

  // Abweichende Zeiten je Tag (#183).
  group('Tages-Abweichungen', () {
    test('plan_defaults ist mandantengetrennt wie jede Datentabelle', () {
      expect(
        schema,
        contains(
          'create policy plan_defaults_isolated on public.plan_defaults',
        ),
        reason:
            'Ohne Policy bei aktivem RLS wäre die Tabelle für jeden Client '
            'leer — und die Abweichung eines Tages verschwände, ohne dass '
            'irgendetwas einen Fehler meldete.',
      );
      expect(
        schema,
        contains(
          'alter table public.plan_defaults       enable row level security',
        ),
      );
    });

    test('das Konfliktziel des upsert nennt denselben Schlüssel', () {
      expect(
        repository,
        contains("onConflict: 'group_id,plan_date'"),
        reason:
            'Weicht es vom Primärschlüssel ab, meldet Postgres „no unique or '
            'exclusion constraint matching the ON CONFLICT specification" — '
            'und zwar erst beim zweiten Speichern desselben Tages.',
      );
      expect(
        primaryKeyOf('plan_defaults').replaceAll(' ', ''),
        'group_id,plan_date',
      );
    });

    test('die Auto-Ebene ist mandantengetrennt und richtig geschlüsselt', () {
      expect(
        schema,
        contains(
          'create policy plan_car_defaults_isolated on public.plan_car_defaults',
        ),
      );
      expect(
        primaryKeyOf('plan_car_defaults').replaceAll(' ', ''),
        'group_id,plan_date,driver_id',
        reason:
            'Derselbe Schlüssel wie `plan_overrides`, und das ist keine '
            'Analogie: Ein Auto existiert in der Datenbank nur als „diese '
            'Person fährt an diesem Tag".',
      );
      expect(
        repository,
        contains("onConflict: 'group_id,plan_date,driver_id'"),
        reason:
            'Weicht das Konfliktziel ab, meldet Postgres „no unique or '
            'exclusion constraint matching the ON CONFLICT specification" — '
            'und zwar erst beim zweiten Speichern desselben Autos.',
      );
    });

    test('die wirksamen Zeiten stehen NICHT im Entprell-Vergleich', () {
      final trigger = RegExp(
        r'function public\.push_outbox_debounce\(\).*?\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(trigger, isNotNull);
      for (final column in ['outbound_time', 'return_time']) {
        expect(
          sqlOnly(trigger!.group(0)!),
          isNot(contains(column)),
          reason:
              'Die `title_out`-Lehre aus v0.58.0: Ein Client, der die Spalte '
              'nicht kennt, schreibt NULL, ein anderer Schreiber gefüllt — im '
              'Vergleich wechselte der Inhalt hin und her und schöbe `due_at` '
              'endlos vor sich her, für ALLE Meldungen dieser Person. '
              'Ausgelöst wird trotzdem: Der `digest` trägt die Abweichung.',
        );
      }
    });

    test('push_due nimmt die Zeile der Zeit vor der Vorgabe der Gruppe', () {
      final function = RegExp(
        r'function public\.push_due\(.*?\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(function, isNotNull);
      final body = sqlOnly(function!.group(0)!);
      expect(
        body,
        contains('coalesce(box.outbound_time, gd.outbound_time)'),
        reason:
            'Sonst feuerte die Erinnerung zur Gruppenzeit, während Planer '
            'und Banner die Zeit des Tages zeigen.',
      );
      expect(
        body,
        contains('left join public.group_defaults gd'),
        reason:
            'Als INNERER Join verschluckte er den Fall „ein einzelner Tag '
            'hat eine Zeit, die Gruppe aber nie eine gesetzt" — dann gäbe es '
            'nie eine Erinnerung, und niemand sähe warum.',
      );
    });
  });

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

    test('der Korb-Schlüssel trägt group_id UND die Art', () {
      expect(
        primaryKeyOf('push_outbox').replaceAll(' ', ''),
        'group_id,person_id,plan_date,kind',
        reason:
            'Fachlicher Schlüssel: Ohne group_id wäre (person_id, plan_date) '
            'über alle Gruppen eindeutig, und die zweite Gruppe liefe beim '
            'Schreiben in eine Unique-Verletzung auf einer Zeile, die sie '
            'nicht einmal sehen darf. Und seit #163 gehört `kind` dazu: Zum '
            'selben Tag können eine Plan-Zeile und eine Fahrt-Meldung '
            'gleichzeitig offen sein — ohne die Spalte im Schlüssel '
            'überschriebe die eine die andere, und je nach Reihenfolge '
            'verschwände mal die Planung, mal die Fahrtänderung.',
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

    test('die Auswahl rechnet das Fenster in deutscher Zeit', () {
      final function = RegExp(
        r'create or replace function public\.push_due.*?\$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains("at time zone 'Europe/Berlin'"),
        reason:
            'Postgres läuft in UTC, die Zeiten in notification_prefs sind '
            'Ortszeit. Ohne die Umrechnung feuerte der Abend-Blick im Sommer '
            'zwei Stunden zu spät — und zweimal im Jahr eine Stunde daneben, '
            'ohne dass irgendwo ein Fehler auftaucht.',
      );
    });

    test('der Digest des Ausgetragenen heißt in SQL wie in Dart', () {
      final dart = File('lib/core/push_digest.dart').readAsStringSync();
      final value = RegExp(
        r"const String removedDigest = '([^']+)'",
      ).firstMatch(dart)?.group(1);
      expect(value, isNotNull);
      expect(
        RegExp(
          r'create or replace function public\.push_due.*?\$\$;',
          dotAll: true,
        ).firstMatch(schema),
        isNotNull,
      );
      expect(
        schema,
        contains("box.digest <> '$value'"),
        reason:
            'Der Wert steht in SQL ein zweites Mal. Driftete er, bekäme ein '
            'Ausgetragener entweder gar keine Meldung mehr oder bei jedem '
            'Lauf eine neue — je nachdem, in welche Richtung.',
      );
    });

    test('der Digest des eingetragenen Tages heißt in SQL wie in Dart', () {
      final dart = File('lib/core/push_digest.dart').readAsStringSync();
      final value = RegExp(
        r"const String confirmedDigest = '([^']+)'",
      ).firstMatch(dart)?.group(1);
      expect(value, isNotNull);
      expect(
        schema,
        contains("box.digest <> '$value'"),
        reason:
            'Wie bei removedDigest steht der Wert in SQL ein zweites Mal. '
            'Driftete er, bekäme beim Eintragen einer Fahrt die halbe Gruppe '
            'eine „Änderung"-Meldung über einen Tag, der gerade erst '
            'stattgefunden hat.',
      );
    });

    test('die Erinnerung rechnet ihr Fenster in deutscher Zeit', () {
      final function = RegExp(
        r'create or replace function public\.push_due.*?\n\$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      final reminder = function!.substring(function.indexOf('reminder_ready'));
      expect(
        reminder,
        contains("at time zone 'Europe/Berlin'"),
        reason:
            'Derselbe Grund wie beim Plan-Fenster: Postgres läuft in UTC. '
            'Ohne die Umrechnung erinnerte die App im Sommer zwei Stunden '
            'zu früh — und zweimal im Jahr eine Stunde daneben.',
      );
      expect(
        reminder,
        contains('make_interval(mins => leg.lead_minutes)'),
        reason:
            'Der Vorlauf ist eine Einstellung, keine Konstante — und seit '
            '#168 eine je Richtung. Er kommt deshalb aus derselben Zeile '
            'wie Uhrzeit und Kopfzeile (`leg`), nicht direkt aus `prefs`: '
            'Stünde hier wieder ein fester Bezug auf `prefs`, bekämen beide '
            'Beine denselben Vorlauf und die Rückfahrt-Erinnerung käme zur '
            'falschen Zeit.',
      );
      expect(
        reminder,
        allOf(
          contains('prefs.reminder_lead_minutes'),
          contains('prefs.reminder_lead_return_minutes'),
        ),
        reason:
            'Beide Werte müssen ins `values`-Paar — fehlte einer, fiele '
            'sein Bein still aus dem Vergleich.',
      );
      expect(
        reminder,
        contains('sent.person_id is null'),
        reason:
            'Zeitgetrieben, also genau einmal. Ohne den Riegel feuerte die '
            'Erinnerung in jedem Minutentakt des Fensters neu — bei 15 '
            'Minuten Vorlauf fünfzehnmal.',
      );
    });

    test('die Erinnerung schließt Ausgetragene aus, Eingetragene nicht', () {
      final function = RegExp(
        r'create or replace function public\.push_due.*?\n\$\$;',
        dotAll: true,
      ).firstMatch(schema)!.group(0)!;
      final reminder = sqlOnly(
        function.substring(function.indexOf('reminder_ready')),
      );
      expect(reminder, contains("box.digest <> 'raus'"));
      expect(
        reminder,
        isNot(contains("box.digest <> 'fix'")),
        reason:
            'An einem eingetragenen Tag fährt die Gruppe gerade — das ist '
            'der Moment, für den die Erinnerung gebaut wurde. Wer „fix" hier '
            'ausschließt, schaltet sie genau dann ab, wenn sie zählt.',
      );
    });

    test('push_log kennt jede protokollierte Art — und `trip` nicht', () {
      final table = RegExp(
        r'create table public\.push_log \((.*?)\n\);',
        dotAll: true,
      ).firstMatch(schema)!.group(1)!;
      final check = sqlOnly(table);
      for (final kind in [
        'evening',
        'change',
        'departure_out',
        'departure_return',
        'roster',
      ]) {
        expect(
          check,
          contains("'$kind'"),
          reason:
              'Der CHECK ist der Riegel, der Erinnerung und Eintrag-Meldung '
              'auf einmal je Zustand begrenzt. Fehlte eine Art darin, schlüge '
              'das Protokollieren fehl — und weil ein abgewiesenes Protokoll '
              'wie ein nie gesendeter Push aussieht, feuerte die Meldung '
              'danach jede Minute neu.',
        );
      }
      expect(
        check,
        isNot(contains("'trip'")),
        reason:
            'Trip-Zeilen werden nach dem Versand GELÖSCHT statt quittiert — '
            'ein Protokolleintrag wäre die zweite Buchführung über dasselbe. '
            'Stünde die Art hier, sähe es aus, als gäbe es ein Gedächtnis, '
            'das niemand pflegt.',
      );
    });

    test('der Versand quittiert nur, was an due_at hing', () {
      final flush = File(
        'supabase/functions/flush-push/index.ts',
      ).readAsStringSync();
      expect(
        flush,
        contains("first.kind === 'evening' || first.kind === 'change'"),
        reason:
            'Die Quittung `due_at = null` gehört zum Plan-Weg. Liefe sie '
            'nach JEDEM Versand, verschluckte eine Erinnerung um 07:15 eine '
            'Planänderung, die um 07:14 entprellt wurde: Die Zeile wäre '
            'erledigt, ohne dass die Änderung je rausging — und der Digest '
            'ändert sich danach nicht mehr.',
      );
    });

    test('der Entprell-Trigger vergleicht die neuen Kopfzeilen NICHT', () {
      final trigger = RegExp(
        r'create or replace function public\.push_outbox_debounce.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(trigger, isNotNull);
      expect(
        sqlOnly(trigger!),
        isNot(anyOf(contains('title_out'), contains('title_return'))),
        reason:
            'Ein Client von vor v0.58.0 schreibt sie als NULL, der stündliche '
            'Job gefüllt. Im Vergleich wechselte der Inhalt zwischen beiden '
            'Schreibern hin und her, jede Änderung schöbe due_at 60 Sekunden '
            'nach hinten — die Zeile wäre NIE fällig, und zwar für alle '
            'Meldungen dieser Person.',
      );
    });

    test('ein Alt-Client leert eine gesetzte Kopfzeile nicht aus', () {
      final function = RegExp(
        r'create or replace function public\.publish_push_outbox.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        sqlOnly(function!),
        contains('coalesce(excluded.title_out, push_outbox.title_out)'),
        reason:
            '0.57.0 ruft die Funktion ohne die neuen Felder. Ohne coalesce '
            'setzte jeder Schreibvorgang von dort die Kopfzeile auf NULL — '
            'und ohne Kopfzeile fällt die Erinnerung aus, bis der stündliche '
            'Job sie wiederherstellt. Eine wirklich entfernte Gruppenzeit '
            'macht das nicht rückgängig: ohne outbound_time kein Fenster.',
      );
    });

    test('der Purge fasst nur Plan-Zeilen an (#163)', () {
      final function = RegExp(
        r'create or replace function public\.publish_push_outbox.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        sqlOnly(function!),
        contains("kind = 'plan' and plan_date < keep_from"),
        reason:
            'Der teuerste Einzelfehler dieser Umstellung. Ohne den Filter '
            'löschte JEDER Schreibvorgang des Clients alle Zeilen vor der '
            'Planwoche — also genau die Meldungen über ältere Fahrten, für '
            'die es #163 gibt. Sie stürben, bevor sie eine Minute später '
            'verschickt würden, und im Log stünde nichts.',
      );
      expect(
        sqlOnly(function),
        contains('on conflict (group_id, person_id, plan_date, kind)'),
        reason:
            'Weicht das Konfliktziel vom Schlüssel ab, meldet Postgres „no '
            'unique or exclusion constraint matching the ON CONFLICT '
            'specification" — und zwar erst am Gerät.',
      );
    });

    test('der Roster-Detektor feuert nur beim UPDATE', () {
      final function = RegExp(
        r'create or replace function public\.push_outbox_debounce.*?end \$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      final body = sqlOnly(function!);
      expect(
        body,
        stringContainsInOrder([
          "if tg_op = 'UPDATE'",
          "new.kind = 'plan'",
          "(old.digest = 'raus') is distinct from (new.digest = 'raus')",
          'not new.suppress_roster',
          'new.roster_due_at :=',
        ]),
        reason:
            'Beim ersten Füllen des Korbs entstehen Zeilen für JEDE Person — '
            'eine neue Gruppe, ein Wochenwechsel, ein Gerät, das den Korb '
            'erstmals schreibt. Ohne `tg_op = UPDATE` weckte das die halbe '
            'Gruppe mit „Eingetragen" für Tage, an denen sich nichts '
            'geändert hat.',
      );
      expect(
        body,
        stringContainsInOrder(["old.digest <> 'fix'", "new.digest <> 'fix'"]),
        reason:
            'Wird eine Fahrt eingetragen, wechselt der Digest derer, die '
            'nicht mitfuhren, auf `raus`. Diesen Fall deckt die '
            'Fahrt-Meldung ab — ohne den Ausschluss käme zusätzlich ein '
            '„Ausgetragen".',
      );
    });

    test('die Sofort-Meldungen haben eine eigene Fälligkeit', () {
      final table = RegExp(
        r'create table public\.push_outbox \((.*?)\n\);',
        dotAll: true,
      ).firstMatch(schema)!.group(1)!;
      expect(
        sqlOnly(table),
        contains('roster_due_at timestamptz'),
        reason:
            'Über `due_at` liefe sie dem Abend-Blick ins Handwerk: Der '
            'quittiert dieselbe Spalte mit NULL, und eine noch offene '
            'Eintrag-Meldung wäre damit stillschweigend erledigt.',
      );
      expect(
        sqlOnly(schema),
        contains(
          'create index push_outbox_roster_idx on public.push_outbox '
          '(roster_due_at)',
        ),
      );
    });

    test('push_due trennt Planung und Fahrt-Meldung', () {
      final function = RegExp(
        r'create or replace function public\.push_due.*?\n\$\$;',
        dotAll: true,
      ).firstMatch(schema)!.group(0)!;
      final body = sqlOnly(function);
      expect(
        RegExp(r"box\.kind = 'plan'").allMatches(body).length,
        greaterThanOrEqualTo(3),
        reason:
            'Abend-Blick, Erinnerung und Eintrag-Meldung lesen alle die '
            'Plan-Zeile. Ohne den Filter läse der Abend-Blick eine '
            'Trip-Zeile als Plan des Tages — und schickte den Text einer '
            'Fahrtänderung als „Morgen (Do)".',
      );
      expect(body, contains("box.kind = 'trip'"));
      expect(
        body,
        contains('box.digest is distinct from sent.digest'),
        reason:
            'Eine Meldung je Zustand: Wer hin- und hergetragen wird, hört '
            'jede Wendung einmal — nicht jede Schreibrunde.',
      );
    });

    test('der Versand löscht Trip-Zeilen, statt sie zu quittieren', () {
      final flush = File(
        'supabase/functions/flush-push/index.ts',
      ).readAsStringSync();
      expect(
        flush,
        stringContainsInOrder([
          "first.kind === 'trip'",
          ".from('push_outbox')",
          '.delete()',
        ]),
        reason:
            'Eine Trip-Zeile trägt keinen wiederkehrenden Zustand, über den '
            'ein Protokoll wachen könnte — sie entsteht einmal und ist dann '
            'erledigt. Bliebe sie stehen, ginge sie in jedem Minutentakt '
            'erneut raus.',
      );
      expect(
        flush,
        contains("first.kind === 'roster'"),
        reason:
            'Die Eintrag-Meldung quittiert ihre EIGENE Spalte. Über `due_at` '
            'löschte sie die Fälligkeit des Abend-Blicks mit.',
      );
    });

    test('der Abholer holt seine Zugangsdaten aus dem Vault', () {
      final function = RegExp(
        r'create or replace function public\.flush_due_push.*?\$\$;',
        dotAll: true,
      ).firstMatch(schema)?.group(0);
      expect(function, isNotNull);
      expect(
        function,
        contains('vault.decrypted_secrets'),
        reason:
            'Eine Tabellenspalte mit dem Job-Geheimnis stünde für jeden mit '
            'service_role-Zugang im Klartext und läge in jedem '
            'Datenbank-Abzug.',
      );
      expect(
        function,
        contains('return;'),
        reason:
            'Fehlen die Einträge, muss die Funktion NICHTS tun — sonst '
            'scheiterte jeder Minutentakt auf dem Teststack und in jeder '
            'Frischinstallation.',
      );
      expect(
        function,
        contains("'apikey', service_key"),
        reason:
            'Das API-Gateway weist einen Aufruf ohne apikey ab, BEVOR die '
            'Function läuft — und pg_net schickt asynchron, die Antwort '
            'landet in net._http_response und sonst nirgends. Das Symptom '
            'wäre „es kommt nichts an, und nirgends steht ein Fehler". Jeder '
            'andere Aufrufer im Repo schickt den Header (tool/notify.dart '
            'kommentiert sogar die Regel dazu).',
      );
      expect(
        sqlOnly(schema),
        contains("cron.schedule("),
        reason: 'Ohne den Eintrag weckt niemand den Abholer.',
      );
    });

    test('beide Extensions des Versands werden ausdrücklich angelegt', () {
      for (final extension in ['pg_cron', 'pg_net']) {
        expect(
          sqlOnly(schema),
          contains('create extension if not exists $extension'),
          reason:
              'Der lokale CLI-Stack bringt pg_net vorinstalliert mit, '
              'Produktion nicht — genau diese Differenz hat am 29.07.2026 '
              'den Versand still stehen lassen: flush_due_push() scheiterte '
              'jede Minute, sichtbar nur in cron.job_run_details, und kein '
              'Test auf dem Teststack konnte es zeigen. Wer sich hier auf '
              '„ist doch eh da" verlässt, wiederholt das.',
        );
      }
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
  group('Fehlerberichte (#136)', () {
    test('error_reports: nur einwerfen, nie zurücklesen', () {
      final policies = RegExp(
        r'create policy \w+ on public\.error_reports for (\w+)',
      ).allMatches(schema).map((m) => m.group(1)).toList();
      expect(
        policies,
        ['insert'],
        reason:
            'Ein Fehlertext kann in Ausnahmefällen Serverdetails tragen, '
            'und die Berichte aller Gruppen gehen keinen Client etwas an. '
            'Eine select-Policy — und sei es „nur zum Debuggen" — machte '
            'aus dem Riegel eine Absichtserklärung; gelesen wird allein '
            'mit dem service_role-Key im Feedback-Bot.',
      );
      expect(
        sqlOnly(schema),
        contains('revoke all on public.error_reports from anon, authenticated'),
        reason:
            'Der Sammel-Grant gibt select/update/delete auf JEDE Tabelle — '
            'ohne die Rücknahme hinge insert-only allein an der fehlenden '
            'Policy (dasselbe Muster wie push_outbox).',
      );
      expect(
        sqlOnly(schema),
        contains('grant insert on public.error_reports to anon'),
        reason:
            'Auch anon darf einwerfen — sonst fehlen genau die Fehler aus '
            'dem Login, und die sind die wertvollsten.',
      );
    });

    test('der Gruppen-Trigger nimmt Nicht-Gruppen-Kennungen zurück', () {
      expect(
        schema,
        contains('error_reports_resolve_group'),
        reason:
            'Ein Verwalter-Konto trägt auth.uid() ohne groups-Zeile — der '
            'Default liefe in den Fremdschlüssel und der Bericht ginge '
            'verloren. Der Trigger löst unter der RLS des Aufrufers auf '
            'und meldet notfalls gruppenlos.',
      );
      expect(
        RegExp(
          r'group_id uuid default auth\.uid\(\)\s*\n?\s*references public\.groups\(id\) on delete cascade',
        ).hasMatch(schema),
        isTrue,
        reason:
            'Die Kaskade hält das Löschversprechen: admin_delete_group '
            'nimmt die Berichte der Gruppe mit — ohne Fremdschlüssel '
            'überlebte eine gelöschte Gruppe bis zu 90 Tage in den '
            'Berichten.',
      );
    });
  });

  // Preisarchiv. Zwei Riegel und eine bewusste Ausnahme von der
  // group_id-Regel, die ohne Test wie ein Versehen aussieht.
  group('Preisarchiv', () {
    test('die Rohschicht hängt an der Region, nicht an der Gruppe', () {
      expect(
        primaryKeyOf('price_sample').replaceAll(RegExp(r'\s'), ''),
        'region_key,captured_at,station_id',
        reason:
            'Bewusste Ausnahme von der group_id-Regel: In price_sample '
            'stehen keine Gruppendaten, sondern öffentliche Marktdaten. '
            'An der Region statt an der Gruppe hängt sie, damit zwei '
            'Gruppen derselben Gegend EINE Abfrage teilen — und damit ein '
            'späterer Tankdaumen eine Abfrage bleibt statt eines Umbaus.',
      );
    });

    test('die Rohschicht hat RLS an und bewusst keine einzige Policy', () {
      expect(
        schema,
        contains('alter table public.price_sample enable row level security'),
        reason: 'Ohne RLS läse jeder authenticated die Rohschicht.',
      );
      expect(
        RegExp(r'create policy \w+ on public\.price_sample').hasMatch(schema),
        isFalse,
        reason:
            'Kein Client liest die Rohschicht je — gruppensichtbar ist '
            'allein price_week. Eine SELECT-Policy hier, und sei es „nur '
            'zum Debuggen", macht aus dem Riegel eine Absichtserklärung.',
      );
      expect(
        sqlOnly(schema),
        contains('revoke all on public.price_sample from anon, authenticated'),
        reason:
            'Der Sammel-Grant gibt Rechte auf JEDE Tabelle. Ohne die '
            'Rücknahme hinge der Riegel allein daran, dass niemand später '
            'eine Policy ergänzt — dieselbe Begründung wie bei push_outbox.',
      );
    });

    test('die Wochenwerte darf ein Client nur lesen', () {
      final policies = RegExp(
        r'create policy (\w+) on public\.price_week\s+for (\w+)',
      ).allMatches(schema).map((m) => '${m.group(1)}:${m.group(2)}').toList();
      expect(
        policies,
        ['price_week_read:select'],
        reason:
            'Geschrieben wird allein vom Verdichtungslauf mit service_role. '
            'Mit einer Schreib-Policy könnte ein Gerät die Preiskurve '
            'fälschen — und eine gefälschte Kurve fiele niemandem auf, weil '
            'niemand die Vergangenheit im Kopf hat.',
      );
      expect(
        sqlOnly(schema),
        contains('revoke all on public.price_week from anon, authenticated'),
        reason: 'Der Sammel-Grant gäbe insert/update/delete.',
      );
      expect(
        sqlOnly(schema),
        contains('grant select on public.price_week to anon, authenticated'),
        reason:
            'Nach der Rücknahme muss das Lesen ausdrücklich zurück — und '
            'zwar für BEIDE Rollen (#254). Nur authenticated machte '
            'price_week zur einzigen Tabelle, die ein Client liest und die '
            'ohne Sitzung 42501 wirft statt still `[]` (RLS filtert) — '
            'genau das Fenster beim Abmelden, belegt in error_reports '
            'KW 33. Für anon bleiben es null Zeilen, die Policy ist '
            'to authenticated.',
      );
    });

    test('die Konstanten stehen NICHT in der Wochenschicht', () {
      final block = RegExp(
        r'create table public\.price_week \((.*?)\n\);',
        dotAll: true,
      ).firstMatch(schema)!.group(1)!;
      expect(
        sqlOnly(block),
        isNot(anyOf(contains('house_power'), contains('charging_power'))),
        reason:
            'Hausstrom und Tankstellenstrom sind vorerst Konstanten aus '
            'settings, und Konstanten werden nicht gespeichert: Eine '
            'Parameteränderung müsste sonst die Historie umschreiben, und '
            'eine abgelegte Konstante sähe später aus wie eine Messung. '
            'Der Lesepfad in core/price_series.dart füllt und markiert sie.',
      );
    });

    test('der Abtast-Takt hat ein eigenes Job-Geheimnis', () {
      final function = RegExp(
        r'create or replace function public\.sample_fuel_prices\(\)(.*?)\n\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(function, isNotNull, reason: 'sample_fuel_prices fehlt.');
      final body = sqlOnly(function!.group(1)!);
      expect(
        body,
        contains("name = 'fuel_job_secret'"),
        reason:
            'Eigenes Geheimnis statt push_job_secret: Ein Leck im Push-Weg '
            'soll nicht auch den Abtast-Endpunkt öffnen.',
      );
      expect(
        body,
        isNot(contains('push_job_secret')),
        reason: 'Sonst hängen beide Wege an einem Wert.',
      );
      expect(
        body,
        contains('vault.decrypted_secrets'),
        reason:
            'Zugangsdaten aus dem Vault, nicht aus einer Tabelle — sonst '
            'stehen sie in jedem Datenbank-Abzug im Klartext.',
      );
    });

    test('das Perzentil heißt in SQL wie in Dart', () {
      final dart = File('lib/core/price_series.dart').readAsStringSync();
      final constant = RegExp(
        r'const double defaultPercentile = ([0-9.]+);',
      ).firstMatch(dart);
      expect(constant, isNotNull, reason: 'defaultPercentile fehlt in Dart.');
      final fraction = double.parse(constant!.group(1)!);
      expect(fraction, 0.10);

      expect(
        sqlOnly(schema),
        contains(
          'percentile_cont(${fraction.toStringAsFixed(2)}) within group',
        ),
        reason:
            'Der Verdichtungslauf rechnet in SQL, der spätere Import der '
            'Vergangenheit in Python, das Zusammenführen in Dart — EINE '
            'Implementierung ist nicht zu haben, EINE Definition schon. '
            'Driften die Zahlen auseinander, entsteht an der Naht zwischen '
            'importierter und gemessener Woche eine Stufe, die keine '
            'Preisänderung ist, und niemand könnte sie erklären. Dasselbe '
            'Muster wie beim Push-Digest.',
      );
    });

    test('die Verdichtung rechnet die Woche in deutscher Zeit', () {
      final function = RegExp(
        r'create or replace function public\.rollup_fuel_weeks\(\)(.*?)\n\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(function, isNotNull, reason: 'rollup_fuel_weeks fehlt.');
      final body = sqlOnly(function!.group(1)!);
      expect(
        RegExp(r'isoyear from .*Europe/Berlin').hasMatch(body),
        isTrue,
        reason:
            'Eine Messung Sonntag 23:30 UTC ist in Deutschland schon Montag '
            'und gehört in die Folgewoche. In UTC gerechnet landete sie in '
            'der falschen — und die Abtastzeiten sind eine Cron-Zeile, die '
            'irgendwann jemand ändert.',
      );
      expect(
        body,
        contains('delete from public.price_sample'),
        reason:
            'Die Rohschicht ist Zwischenprodukt, kein Archiv — ohne das '
            'Aufräumen wächst sie unbegrenzt weiter.',
      );
    });

    test('die Ortssuche verlangt ein JWT, das Abtasten nicht', () {
      final config = File('supabase/config.toml').readAsStringSync();
      final geocode = RegExp(
        r'\[functions\.geocode-place\]\s*\nverify_jwt = (\w+)',
      ).firstMatch(config);
      expect(
        geocode?.group(1),
        'true',
        reason:
            'Für die Ortssuche gibt es keinen Aufrufer aus der Datenbank, '
            'und sie befragt einen Fremddienst auf fremde Kosten. Ohne '
            'Prüfung wäre sie ein offener Geokodierer.',
      );

      final sample = RegExp(
        r'\[functions\.fuel-sample\]\s*\nverify_jwt = (\w+)',
      ).firstMatch(config);
      expect(
        sample?.group(1),
        'false',
        reason:
            'Der Abtast-Takt kommt aus der Datenbank (pg_cron → pg_net) '
            'und hat kein JWT. Auf true stünde er still, ohne dass '
            'irgendwo ein Fehler auftaucht — die Antwort landet nur in '
            'net._http_response.',
      );
    });

    test('die Function ist in config.toml deklariert', () {
      final config = File('supabase/config.toml').readAsStringSync();
      expect(
        config,
        contains('[functions.fuel-sample]'),
        reason:
            'Die GitHub-Integration deployt die in config.toml deklarierten '
            'Functions. Ohne den Eintrag liefe der Takt ins Leere, ohne dass '
            'irgendwo ein Fehler auftaucht.',
      );
    });
  });

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

  group('Feste Vorgaben der Gruppe (Issue #139)', () {
    final migration = File(
      'supabase/migrations/20260803090000_group_defaults.sql',
    ).readAsStringSync();

    test('die Tabelle ist gegen fremde Gruppen dicht', () {
      expect(
        schema,
        contains(
          'alter table public.group_defaults      enable row level security',
        ),
        reason: 'Ohne RLS läse jede Gruppe die Zeiten jeder anderen.',
      );
      expect(
        sqlOnly(schema),
        stringContainsInOrder([
          'create policy group_defaults_isolated on public.group_defaults',
          'group_id = auth.uid() and public.my_group_active()',
          'with check (group_id = auth.uid() and public.my_group_active())',
        ]),
        reason:
            'Ohne `with check` könnte ein Client eine Zeile mit fremder '
            'group_id einfügen; ohne my_group_active() schriebe eine '
            'archivierte Gruppe weiter.',
      );
    });

    test('höchstens eine Zeile je Gruppe', () {
      expect(
        primaryKeyOf('group_defaults'),
        contains('group_id'),
        reason:
            'Zwei Zeilen wären zwei Wahrheiten über dieselbe Abfahrtszeit, '
            'und das Repository liest mit maybeSingle — die zweite Zeile '
            'ließe es werfen. Muster: price_area.',
      );
    });

    test('die Zeiten heißen NICHT departure_time', () {
      final table = RegExp(
        r'create table public\.group_defaults \((.*?)\n\);',
        dotAll: true,
      ).firstMatch(schema);
      expect(table, isNotNull, reason: 'group_defaults fehlt im Gesamtbild.');
      final body = sqlOnly(table!.group(1)!);
      expect(body, contains('outbound_time time'));
      expect(body, contains('return_time time'));
      expect(
        body,
        isNot(contains('departure_time')),
        reason:
            'Der Name ist in notification_prefs vergeben — dort ist er die '
            'persönliche Deadline, ab der eine Meldung niemanden mehr '
            'erreicht. Zwei Bedeutungen unter einem Spaltennamen sieht man '
            'beim Lesen einer Query nicht.',
      );
    });

    test('ein leerer Treffpunkt kommt nicht in die Datenbank', () {
      expect(
        sqlOnly(schema),
        contains('char_length(btrim(meeting_point)) between 1 and 120'),
        reason:
            'Dieselbe Begründung wie bei plan_notes: Ohne `btrim` ließe der '
            'Check 120 Leerzeichen durch, und das Banner stünde vor einem '
            '„Treffpunkt " ohne Inhalt.',
      );
    });

    test('es gibt keinen Seed und keinen Trigger-Eintrag', () {
      expect(
        sqlOnly(migration),
        isNot(contains('insert into public.group_defaults')),
        reason:
            'Keine Zeile = alles NULL = Feature aus. Eine erfundene '
            'Vorgabezeit stünde einer Gruppe im Banner, die sie nie gesetzt '
            'hat — und niemand fände, woher sie kommt.',
      );
      final trigger = RegExp(
        r'create or replace function public\.handle_new_group\(\)(.*?)\n\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(trigger, isNotNull, reason: 'handle_new_group fehlt.');
      expect(
        sqlOnly(trigger!.group(1)!),
        isNot(contains('group_defaults')),
        reason: 'Auch der Signup-Trigger legt keine Zeile an.',
      );
    });

    test('die Migration hebt die Mindestversion NICHT', () {
      expect(
        sqlOnly(migration),
        isNot(contains("value = '")),
        reason:
            'Rein additiv: Ein veröffentlichter Client liest die neue Tabelle '
            'nicht und läuft unverändert weiter. Heben würde nur jeden '
            'veralteten Client auf den Sperr-Schirm werfen.',
      );
    });
  });

  group('Gruppen-Schalter für die Auto-Zuordnung (#213)', () {
    final migration = File(
      'supabase/migrations/20260809110000_car_assignment_switch.sql',
    ).readAsStringSync();

    test('bestehende Gruppen behalten die Zuordnung', () {
      expect(
        sqlOnly(migration),
        stringContainsInOrder([
          "insert into public.settings",
          "'car_assignment_enabled', 1",
          'from public.groups',
        ]),
        reason:
            'Sie benutzen das Feature seit v0.64.0. Eine neue Vorgabe darf '
            'ihnen nichts wegnehmen — das wäre kein Standard, sondern ein '
            'Entzug.',
      );
      expect(
        sqlOnly(migration),
        contains('on conflict (group_id, key) do nothing'),
        reason:
            'Eine Gruppe, die den Schalter schon gesetzt hat, darf die '
            'Migration nicht überschreiben — ein zweiter Lauf würde ihre '
            'Entscheidung zurückdrehen.',
      );
    });

    test('neue Gruppen starten OHNE Zuordnung', () {
      final trigger = RegExp(
        r'create or replace function public\.handle_new_group\(\)(.*?)\n\$\$;',
        dotAll: true,
      ).firstMatch(schema);
      expect(trigger, isNotNull, reason: 'handle_new_group fehlt.');
      expect(
        sqlOnly(trigger!.group(1)!),
        isNot(contains('car_assignment_enabled')),
        reason:
            'Keine Zeile = aus, und das ist die Vorgabe einer frisch '
            'angelegten Gruppe. Seedete der Trigger eine 0, wäre es dasselbe '
            'Ergebnis über einen zweiten Weg — und beim nächsten Wechsel der '
            'Vorgabe müsste man an zwei Stellen denken.',
      );
    });

    test('die Migration hebt die Mindestversion NICHT', () {
      expect(
        sqlOnly(migration),
        isNot(contains('min_supported_version')),
        reason:
            'Es fällt nichts weg und nichts wird umbenannt, und '
            '`saveSettings` ist ein Upsert je Schlüssel: Ein alter Client '
            'kennt den Schalter nicht, schreibt ihn nicht und lässt die '
            'Zeile stehen. Heben würde jeden veralteten Client aussperren, '
            'ohne dass irgendwo falsche Daten stünden.',
      );
    });
  });
}
