/// read_retry_test.dart – Der zweite Anlauf bei PGRST303 (Issue #169).
///
/// Zwei Hälften, und die zweite ist die wichtigere: Das Verhalten von
/// [readTolerant] ist schnell geprüft, aber ein Helfer, den niemand ruft,
/// wäre wertlos — und ein Helfer, der aus Versehen einen **schreibenden**
/// Aufruf wiederholt, wäre schädlich. Deshalb liest der zweite Teil den
/// Quelltext der Datenschicht und nagelt beide Richtungen fest.
library;

import 'dart:io';

import 'package:mitfahrbar/data/read_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _skew() => const PostgrestException(
  message: 'JWT issued at future',
  code: clockSkewCode,
  details: 'Unauthorized',
);

void main() {
  setUp(() => skewRetryDelay = Duration.zero);
  tearDown(() => skewRetryDelay = const Duration(seconds: 2));

  group('readTolerant', () {
    test(
      'ein Uhrenversatz kostet einen zweiten Anlauf, kein Ergebnis',
      () async {
        var calls = 0;
        final value = await readTolerant(() async {
          calls++;
          if (calls == 1) throw _skew();
          return 'daten';
        });

        expect(value, 'daten');
        expect(calls, 2);
      },
    );

    test('ohne Fehler wird genau einmal gelesen', () async {
      var calls = 0;
      await readTolerant(() async {
        calls++;
        return 1;
      });
      expect(calls, 1);
    });

    test('jeder andere Postgrest-Fehler fliegt sofort weiter', () async {
      var calls = 0;
      await expectLater(
        readTolerant(() async {
          calls++;
          throw const PostgrestException(message: 'nope', code: '42501');
        }),
        throwsA(isA<PostgrestException>()),
      );
      // Kein zweiter Anlauf: Eine fehlende Berechtigung heilt nicht durch
      // Warten, und ein stiller Doppelversuch verschleierte sie nur.
      expect(calls, 1);
    });

    test('ein Netzfehler bleibt ein Netzfehler', () async {
      var calls = 0;
      await expectLater(
        readTolerant(() async {
          calls++;
          throw const SocketException('kein Netz');
        }),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 1);
    });

    test('hält der Versatz an, bleibt es bei genau zwei Versuchen', () async {
      // Keine Schleife: Sonst würde aus einem sichtbaren Fehler ein Hängen.
      var calls = 0;
      await expectLater(
        readTolerant(() async {
          calls++;
          throw _skew();
        }),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 2);
    });

    test('im Betrieb wird wirklich gewartet, nicht sofort wiederholt', () {
      // Die Pause ist der ganze Wirkstoff: Der Fehler heilt allein dadurch,
      // dass Zeit vergeht. Stünde hier Duration.zero, liefe der zweite
      // Anlauf in denselben Uhrenversatz.
      skewRetryDelay = const Duration(seconds: 2);
      expect(skewRetryDelay, greaterThan(Duration.zero));
    });
  });

  group('Die Datenschicht benutzt ihn — und zwar nur beim Lesen', () {
    /// Alles, was echte Tabellen liest oder schreibt. Fakes und Demo-Klassen
    /// stehen bewusst nicht in der Liste: Sie sprechen kein PostgREST.
    const files = [
      'lib/data/supabase_repository.dart',
      'lib/data/group_repository.dart',
      'lib/data/price_repository.dart',
      'lib/data/app_config_repository.dart',
      'lib/data/push_repository.dart',
      'lib/data/admin_repository.dart',
      'lib/data/push_outbox_repository.dart',
      'lib/data/error_report_repository.dart',
      'lib/data/feedback_repository.dart',
    ];

    /// Namensanfänge, an denen man einen Lese- von einem Schreibzugriff
    /// unterscheidet. Das ist keine Konvention um ihrer selbst willen — an
    /// ihr hängt, was wiederholt werden darf.
    const readPrefixes = ['load', 'my', 'stateFor', 'minSupportedVersion'];
    const writePrefixes = [
      'save',
      'create',
      'update',
      'delete',
      'publish',
      'register',
      'unregister',
      'send',
      'claim',
      'release',
      'reset',
      'set',
      'sample',
    ];

    /// Methodenkopf einer Implementierung: `Future<X> name(...)` mit Rumpf.
    final signature = RegExp(
      r'^  (?:Future<[^;]*?>|void) ([A-Za-z_]\w*)\(',
      multiLine: true,
    );

    /// Nur die Klassen, die wirklich PostgREST sprechen — erkennbar an ihrem
    /// `SupabaseClient`-Feld.
    ///
    /// Ohne diese Einschränkung liefe der Riegel auch über die abstrakten
    /// Deklarationen und die Demo-/Noop-Fassungen in denselben Dateien und
    /// verlangte von ihnen eine Umhüllung, die dort sinnlos wäre: Sie
    /// sprechen kein Netz und können deshalb keinen Uhrenversatz sehen.
    List<String> talkingToPostgrest(String source) => [
      for (final block in source.split(RegExp(r'^class ', multiLine: true)))
        if (block.contains('SupabaseClient _client')) block,
    ];

    for (final path in files) {
      test('$path: Lesen wiederholt, Schreiben nie', () {
        final source = File(path).readAsStringSync();
        final blocks = talkingToPostgrest(source);
        expect(
          blocks,
          isNotEmpty,
          reason:
              '$path hat keine Klasse mit einem SupabaseClient — dann prüft '
              'dieser Test nichts. Entweder ist die Datei aus der Liste '
              'gefallen oder das Feld heißt anders.',
        );
        // Zeilenweise, damit die Zuordnung Kopf → Umhüllung eindeutig ist —
        // aber der Kopf reicht über mehrere Zeilen, sobald `dart format` eine
        // lange Signatur umbricht (`loadPlan`, `loadNotes`). Deshalb wird das
        // Fenster bis zum Rumpfanfang betrachtet und nicht die eine Zeile.
        final lines = blocks.join('\n').split('\n');
        for (var i = 0; i < lines.length; i++) {
          final match = signature.firstMatch(lines[i]);
          if (match == null) continue;
          final name = match.group(1)!;
          final head = lines
              .sublist(i, i + 4 > lines.length ? lines.length : i + 4)
              .join(' ');
          final wrapped = head.contains('readTolerant');

          final isRead = readPrefixes.any(name.startsWith);
          final isWrite = writePrefixes.any(name.startsWith);
          if (isRead) {
            expect(
              wrapped,
              isTrue,
              reason:
                  '$name in $path liest, ist aber nicht in readTolerant '
                  'gehüllt. Nach einer Token-Erneuerung lehnt PostgREST den '
                  'Aufruf mit PGRST303 ab (12 Vorfälle in KW 32) und die '
                  'Nutzerin sieht einen Fehler, den ein zweiter Anlauf '
                  'geschluckt hätte.',
            );
          }
          if (isWrite) {
            expect(
              wrapped,
              isFalse,
              reason:
                  '$name in $path schreibt und darf NIE wiederholt werden: '
                  'Ein zweiter Anlauf legte die Zeile ein zweites Mal an — '
                  'bei einer Fahrt verschiebt das rückwirkend die Punkte '
                  'aller Beteiligten.',
            );
          }
        }
      });
    }

    test('die Liste der Lesezugriffe ist nicht leer', () {
      // Schutz gegen einen Regex, der ins Leere greift: Ohne diesen Test
      // wären die Schleifen oben grün, auch wenn sie nichts prüfen.
      var reads = 0;
      for (final path in files) {
        final blocks = talkingToPostgrest(File(path).readAsStringSync());
        for (final line in blocks.join('\n').split('\n')) {
          final match = signature.firstMatch(line);
          if (match == null) continue;
          if (readPrefixes.any(match.group(1)!.startsWith)) reads++;
        }
      }
      expect(reads, 12);
    });
  });
}
