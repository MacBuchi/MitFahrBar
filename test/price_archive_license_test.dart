/// price_archive_license_test.dart – Hält die Begründung fest, mit der die
/// CC-BY-NC-SA-Lizenz des Tankerkönig-Preisarchivs eingehalten wird.
///
/// Die Wochenwerte aus dem historischen Archiv stehen unter **CC BY-NC-SA
/// 4.0**, nicht unter der CC BY 4.0 der Live-API. Die ShareAlike-Klausel
/// greift bei *Weitergabe* — und die Zusage des Projekts lautet, dass es
/// keine gibt: Die Werte bleiben in der Gruppendatenbank. Bisher stand das
/// als Satz in README und CLAUDE.md und war von nichts erzwungen; hier
/// stehen die Tatsachen, auf denen er ruht.
///
/// Seit dem Abschalten des Live-Takts sind es drei statt vier: Die
/// Rohschicht `price_sample` gibt es nicht mehr, und mit ihr fällt der
/// Punkt, der sie unerreichbar hielt.
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
    // Die Rohschicht `price_sample` ist mit dem Live-Takt gefallen
    // (Migration 20260822020000). Sie war der Teil, der dem Archiv am
    // nächsten lag; ihr Wegfall macht die Zusage nicht schwächer, sondern
    // kürzer: Es gibt ab hier nur noch EINE Preisschicht, und für die gilt
    // der Riegel unten. Der Test hält fest, dass sie nicht zurückkommt —
    // eine wiederbelebte Rohschicht bräuchte ihre eigenen Rücknahmen, und
    // die vergisst man genau dann.
    test('es gibt keine zweite Preisschicht mehr', () {
      expect(
        sql,
        isNot(contains('public.price_sample')),
        reason:
            'Käme sie zurück, käme der Live-Takt mit ihr — und mit ihm die '
            'Grenze, an der das System zuerst gebrochen wäre.',
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
        ['select → anon, authenticated'],
        reason:
            'Genau ein Grant zurück, und zwar nur lesend. Das select für '
            '`anon` (#254) ist KEIN öffentlicher Lesepfad: Ohne anon-Policy '
            'filtert die RLS jede Anfrage ohne Sitzung zu `[]` — am echten '
            'Postgres bewiesen (rls_e2e_test). Es gibt nur das Schweigen '
            'zurück, das jede andere Tabelle beim Abmelden längst hat; nur '
            'authenticated warf price_week dort 42501 (error_reports '
            'KW 33). Der Lizenz-Riegel gegen die Weitergabe hängt damit '
            'allein an der Policy-Prüfung direkt hierunter.',
      );

      final policies =
          RegExp(
                r'create policy (\w+) on public\.price_week\s+for (\w+) to (\w+)',
              )
              .allMatches(sql)
              .map((m) => '${m.group(1)}: ${m.group(2)} → ${m.group(3)}')
              .toList();
      expect(
        policies,
        ['price_week_read: select → authenticated'],
        reason:
            'Eine einzige Policy, sie liest nur, und sie gilt NUR für '
            'Angemeldete. Ein `for all` gäbe der Gruppe auch das Schreiben — '
            'eine gefälschte Preiskurve fiele niemandem auf. Und seit dem '
            'anon-Grant (#254) ist das `to authenticated` der EINZIGE '
            'Riegel vor einem öffentlichen Lesepfad: Die Archiv-Lizenz ist '
            'CC BY-NC-SA, öffentlich lesbare Wochenwerte wären eine '
            'Weitergabe und zögen die ShareAlike-Pflicht nach sich. Wer die '
            'Policy auf `to public` weitet oder eine anon-Policy ergänzt, '
            'öffnet genau diesen Pfad.',
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

      for (final table in ['price_week']) {
        expect(
          lineOf('revoke all on public.$table from anon, authenticated;'),
          greaterThan(blanket),
          reason:
              'Die Rücknahme für $table steht VOR dem Sammel-Grant und ist '
              'damit wirkungslos — der Grant hebt sie gleich wieder auf.',
        );
      }

      expect(
        lineOf('grant select on public.price_week to anon, authenticated;'),
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
    test('der CSV-Export führt keine ARCHIV-Preise aus', () {
      // Der Export ist die einzige Stelle, an der Daten die App verlassen.
      // Eine Datei mit den Wochenwerten wäre eine Weitergabe der
      // Archivwerte — dann greift die ShareAlike-Klausel, und das
      // MIT-LICENSE des Projekts trägt sie nicht mehr.
      //
      // Geprüft wird seit #272 auf die **Archiv-Begriffe**, nicht mehr auf
      // das Wort „price". Der Grund ist eine Unterscheidung, die vorher
      // nicht nötig war: Seit die Sicherung auch die Parameter mitnimmt,
      // stehen in csv_export.dart die Schlüssel `diesel_price_per_liter`
      // und Freunde. Das sind die Konstanten, die die Gruppe im
      // Parameter-Schirm selbst eintippt — ihre eigenen Zahlen, nicht die
      // von Tankerkönig. Sie zu exportieren gibt nichts weiter, was dem
      // Archiv gehört.
      //
      // Netto ist die Prüfung damit **strenger** als vorher: Sie sieht
      // zusätzlich in export_action.dart, wo die Daten eingesammelt werden.
      // Dort hätte man die Wochenwerte laden und in eine der Dateien
      // schreiben können, ohne dass dieser Test je etwas gemerkt hätte.
      const forbidden = [
        'PricePoint',
        'PriceSeries',
        'price_week',
        'priceWeeksProvider',
        'price_series.dart',
        'buildPriceCsv',
      ];
      const files = [
        'lib/core/csv_export.dart',
        'lib/features/export/export_action.dart',
      ];

      /// Nur der Code, ohne ganze Kommentarzeilen — dieselbe Notwendigkeit
      /// wie `sqlOnly`: Beide Dateien begründen inzwischen selbst, warum es
      /// keine Preis-Datei gibt, und nennen dabei zwangsläufig genau die
      /// Begriffe, deren Abwesenheit hier geprüft wird.
      ///
      /// Bewusst nur **ganze** Zeilen, nicht ab dem ersten `//`: In Dart
      /// steckt das auch in jedem `https://`-Literal, und dort abzuschneiden
      /// verstecke echten Code hinter einer URL.
      String codeOnly(String dart) => dart
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      for (final path in files) {
        final code = codeOnly(File(path).readAsStringSync());
        for (final needle in forbidden) {
          expect(
            code.contains(needle),
            isFalse,
            reason:
                '„$needle" steht im Code von $path. Die Wochenwerte des '
                'Archivs im Export wären eine Weitergabe — dann greift die '
                'ShareAlike-Klausel der CC BY-NC-SA, und das MIT-LICENSE des '
                'Projekts trägt sie nicht mehr. Verloren geht dadurch nichts: '
                'Der nächtliche Nachfüll-Lauf holt fehlende Wochen von selbst '
                'aus dem Archiv. Siehe doc/entscheidung-preisarchiv-lizenz.md.',
          );
        }
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
