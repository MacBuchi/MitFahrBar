/// price_archive_license_test.dart – Hält die Begründung fest, mit der die
/// CC-BY-NC-SA-Lizenz des Tankerkönig-Preisarchivs eingehalten wird.
///
/// Die Wochenwerte aus dem historischen Archiv stehen unter **CC BY-NC-SA
/// 4.0**, nicht unter der CC BY 4.0 der Live-API. Die ShareAlike-Klausel
/// greift bei *Weitergabe* — und die Zusage des Projekts lautet, dass es
/// keine gibt: Die Werte bleiben in der Gruppendatenbank. Bisher stand das
/// als Satz in README und CLAUDE.md und war von nichts erzwungen; hier
/// stehen die vier Tatsachen, auf denen er ruht.
///
/// Begründung im Ganzen: `doc/entscheidung-preisarchiv-lizenz.md`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = File('supabase/schema.sql').readAsStringSync();

  /// [sql] ohne `--`-Kommentare — dieselbe Notwendigkeit wie `sqlOnly` in
  /// `schema_test.dart`: Der Abschnitt begründet seine eigenen Rücknahmen
  /// ausführlich und nennt dabei zwangsläufig genau die Rechte, deren
  /// Abwesenheit hier geprüft wird.
  String sqlOnly(String sql) => sql
      .split('\n')
      .map((line) {
        final comment = line.indexOf('--');
        return comment == -1 ? line : line.substring(0, comment);
      })
      .join('\n');

  final sql = sqlOnly(schema);

  /// Position der ersten Zeile, die [needle] enthält — oder -1.
  int lineOf(String needle) =>
      sql.split('\n').indexWhere((l) => l.contains(needle));

  group('Preisarchiv: CC BY-NC-SA', () {
    // ------------------------------------------------------------ Rohschicht
    test('price_sample ist für Clients gar nicht erreichbar', () {
      expect(
        sql,
        contains('revoke all on public.price_sample from anon, authenticated;'),
        reason:
            'Die Rohschicht liegt dem Archiv am nächsten. Der Sammel-Grant '
            'weiter oben gibt jeder Tabelle select/insert/update/delete — '
            'ohne diese Rücknahme steht sie jedem angemeldeten Client offen.',
      );
      expect(
        RegExp(
          r'^grant .* on public\.price_sample ',
          multiLine: true,
        ).hasMatch(sql),
        isFalse,
        reason:
            'price_sample bekommt nach der Rücknahme nichts zurück. Sie ist '
            'Zwischenprodukt des Verdichtungslaufs; für einen Client gibt es '
            'darin nichts zu suchen.',
      );
      expect(
        RegExp(r'create policy \w+ on public\.price_sample').hasMatch(sql),
        isFalse,
        reason:
            'Null Policies wie bei push_outbox — der Riegel darf nicht daran '
            'hängen, dass niemand später eine ergänzt.',
      );
    });

    // ---------------------------------------------------------- Wochenwerte
    test('price_week darf die eigene Gruppe nur LESEN', () {
      expect(
        sql,
        contains('revoke all on public.price_week from anon, authenticated;'),
        reason: 'Ohne die Rücknahme könnte ein Gerät die Historie fälschen.',
      );

      final grants = RegExp(
        r'^grant (.+) on public\.price_week to (.+);$',
        multiLine: true,
      ).allMatches(sql).map((m) => '${m.group(1)} → ${m.group(2)}').toList();
      expect(
        grants,
        ['select → authenticated'],
        reason:
            'Genau ein Grant zurück, und zwar nur lesend und nur für '
            'Angemeldete. `anon` darf nichts: Die Werte stammen aus dem '
            'Archiv, ein öffentlicher Lesepfad wäre eine Weitergabe und '
            'zöge die ShareAlike-Pflicht nach sich.',
      );

      final policies = RegExp(
        r'create policy (\w+) on public\.price_week\s+for (\w+)',
      ).allMatches(sql).map((m) => '${m.group(1)}: ${m.group(2)}').toList();
      expect(
        policies,
        ['price_week_read: select'],
        reason:
            'Eine einzige Policy, und die liest nur. Ein `for all` gäbe der '
            'Gruppe auch das Schreiben — eine gefälschte Preiskurve fiele '
            'niemandem auf.',
      );
      expect(
        sql,
        contains('using (group_id = auth.uid() and public.my_group_active())'),
        reason:
            'Die Policy trägt die Mandantentrennung; ohne sie sähe jede '
            'Gruppe die Werte jeder anderen.',
      );
    });

    // ----------------------------------------------------------- Reihenfolge
    test('die Rücknahmen stehen NACH dem Sammel-Grant', () {
      // Der eigentliche Riegel, und der einzige, der lautlos brechen kann:
      // Rutschte eine Rücknahme über den Sammel-Grant, liefe das Schema
      // sauber durch, die Policy bliebe sichtbar stehen — und die Tabelle
      // wäre trotzdem offen. Dieselbe Klasse wie die Reihenfolge in der
      // #108-Migration, deshalb auch hier ein Positionsvergleich statt
      // einer Vorkommensprüfung.
      final blanket = lineOf('on all tables in schema public to anon');
      expect(blanket, isNot(-1), reason: 'Sammel-Grant nicht gefunden');

      for (final table in ['price_sample', 'price_week']) {
        expect(
          lineOf('revoke all on public.$table from anon, authenticated;'),
          greaterThan(blanket),
          reason:
              'Die Rücknahme für $table steht VOR dem Sammel-Grant und ist '
              'damit wirkungslos — der Grant hebt sie gleich wieder auf.',
        );
      }

      expect(
        lineOf('grant select on public.price_week to authenticated;'),
        greaterThan(
          lineOf('revoke all on public.price_week from anon, authenticated;'),
        ),
        reason:
            'Das Lesen muss NACH der Rücknahme wieder erteilt werden, sonst '
            'nimmt die Rücknahme es gleich mit und der Preis-Screen bleibt '
            'leer.',
      );
    });

    // -------------------------------------------------------- Kein Ausgang
    test('der CSV-Export führt keine Preisdaten aus', () {
      // Der Export ist die einzige Stelle, an der Daten die App verlassen.
      // Er kennt Fahrten und Personen — Preise gehören nicht hinein, sonst
      // wäre die Datei eine Weitergabe der Archivwerte.
      final export = File('lib/core/csv_export.dart').readAsStringSync();
      for (final needle in ['price', 'Preis', 'fuel', 'Sprit']) {
        expect(
          export.contains(needle),
          isFalse,
          reason:
              '„$needle" steht in csv_export.dart. Preisdaten im Export '
              'wären eine Weitergabe der Archivwerte — dann greift die '
              'ShareAlike-Klausel, und das MIT-LICENSE des Projekts trägt '
              'sie nicht mehr. Siehe doc/entscheidung-preisarchiv-lizenz.md.',
        );
      }
    });

    // ------------------------------------------------------ Namensnennung
    test('beide Lizenzen sind getrennt genannt', () {
      // BY verlangt die Nennung — und zwar der RICHTIGEN Lizenz. Die
      // Live-API steht unter CC BY 4.0, das Archiv unter CC BY-NC-SA 4.0;
      // beides unter einem Namen zusammenzuziehen wäre schlicht falsch.
      final about = File(
        'lib/features/about/about_dialog.dart',
      ).readAsStringSync();
      final readme = File('README.md').readAsStringSync();

      for (final entry in {
        'about_dialog.dart': about,
        'README.md': readme,
      }.entries) {
        expect(
          entry.value,
          contains('CC BY-NC-SA 4.0'),
          reason:
              '${entry.key} nennt die Archiv-Lizenz nicht. Sie ist enger als '
              'die CC BY 4.0 der Live-API; wer auf die genannte aufbaut, '
              'baut sonst auf die falsche.',
        );
        expect(
          entry.value,
          contains('CC BY 4.0'),
          reason: '${entry.key} nennt die Lizenz der Live-API nicht.',
        );
      }
    });
  });
}
