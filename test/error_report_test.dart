/// error_report_test.dart – Fehler-Senke (#136): Aufbereitung, Filter und
/// der Logger-Hook.
///
/// Die PII-Zusage ist hier STRUKTURELL verankert: Der Test nagelt die
/// Feldliste des Berichts fest. Ein Feld, das Personennamen tragen könnte
/// (Log-Ring, Breadcrumbs, freie Metadaten), kann nur dazukommen, wenn
/// jemand diesen Test bewusst ändert — und dabei die Begründung liest.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mitfahrbar/core/log.dart';
import 'package:mitfahrbar/data/error_report_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('buildErrorReportRow', () {
    test('trägt genau die Felder des Schemas — und keins für Namen', () {
      final row = buildErrorReportRow(
        context: 'Test',
        error: Exception('kaputt'),
        stackTrace: StackTrace.current,
        appVersion: '1.0.0',
        platform: 'android',
      );
      expect(
        row.keys.toSet(),
        {
          'context',
          'error_type',
          'message',
          'stack',
          'app_version',
          'platform',
        },
        reason:
            'Diese Liste IST die Datenschutz-Zusage aus dem Hilfe-Screen '
            '(„nie Namen oder Fahrten"). Wer ein Feld ergänzt, prüft zuerst, '
            'ob dort je ein Personenname stehen könnte — der logRing zum '
            'Beispiel bleibt deshalb draußen.',
      );
      expect(
        row.containsKey('group_id'),
        isFalse,
        reason:
            'group_id schreibt die Datenbank (Default + Trigger). Schriebe '
            'der Client sie, liefe ein Verwalter-Konto in den Fremdschlüssel '
            'und der Bericht ginge verloren.',
      );
    });

    test('kürzt auf die Längen-Checks des Schemas', () {
      final row = buildErrorReportRow(
        context: 'x' * 300,
        error: Exception('y' * 3000),
        appVersion: '1',
        platform: 'android',
      );
      expect((row['context'] as String).length, 100);
      expect(
        (row['message'] as String).length,
        1000,
        reason:
            'Länger lehnte der DB-Check die Zeile ab — gekürzt ankommen '
            'schlägt vollständig verloren gehen.',
      );
    });

    test('ein log.e ohne Fehlerobjekt bleibt meldefähig', () {
      final row = buildErrorReportRow(
        context: 'csv export failed: irgendwas',
        platform: 'web',
      );
      expect(row['error_type'], 'LogError');
      expect(row['message'], isNull);
    });

    test('leerer Kontext fällt nicht am DB-Check', () {
      final row = buildErrorReportRow(context: '  ', platform: 'web');
      expect(
        row['context'],
        'unbekannt',
        reason:
            'Der Check verlangt 1–100 Zeichen — ein leerer Kontext würde '
            'den Bericht kosten, nicht den Fehler.',
      );
    });
  });

  group('worthReporting', () {
    test('Funkloch und Zeitüberschreitung sind Normalbetrieb', () {
      expect(worthReporting(TimeoutException('langsam')), isFalse);
      expect(worthReporting(http.ClientException('Netz weg')), isFalse);
      expect(
        worthReporting(Exception('SocketException: Connection failed')),
        isFalse,
        reason:
            'Ein Handy im Auto verliert ständig das Netz — als Berichte '
            'ersäufte das den Wochen-Digest (PilzBuddy: 193 Zeilen für '
            'abgebrochene Kachel-Jobs).',
      );
      expect(worthReporting(AuthRetryableFetchException()), isFalse);
    });

    test('echte Fehler bleiben meldewürdig — auch AuthException', () {
      expect(
        worthReporting(const PostgrestException(message: 'kaputt')),
        isTrue,
      );
      expect(
        worthReporting(const AuthException('invalid')),
        isTrue,
        reason:
            'Eine kaputte Auth-Config ist genau die Klasse, die am '
            '23.07.2026 die Registrierung still brach — nur die '
            'Netz-Variante (AuthRetryableFetchException) ist Rauschen.',
      );
      expect(
        worthReporting(null),
        isTrue,
        reason: 'Ein bewusstes log.e ohne Objekt ist eine bewusste Meldung.',
      );
    });
  });

  group('Logger-Hook', () {
    final captured = <(String, Object?, StackTrace?)>[];

    setUp(() {
      captured.clear();
      setLogErrorSink((context, error, stack) {
        captured.add((context, error, stack));
      });
    });

    tearDown(() => setLogErrorSink(null));

    test('log.e erreicht die Senke, ohne dass eine Aufrufstelle es weiß', () {
      final boom = Exception('kaputt');
      log.e('Testfall', error: boom, stackTrace: StackTrace.current);
      expect(captured, hasLength(1));
      expect(captured.single.$1, 'Testfall');
      expect(captured.single.$2, boom);
    });

    test('Warnungen bleiben lokal', () {
      log.w('nur eine Warnung');
      expect(
        captured,
        isEmpty,
        reason:
            'log.w ist „Nebensächliches still": Der Push-Init etwa warnt '
            'bei jedem Start ohne Firebase — als Bericht wäre das Dauer-'
            'Rauschen im Digest.',
      );
    });

    test('eine werfende Senke macht das Loggen nicht kaputt', () {
      setLogErrorSink((_, _, _) => throw StateError('Senke kaputt'));
      expect(
        () => log.e('Testfall'),
        returnsNormally,
        reason:
            'Die Senke darf nie selbst zum Fehler werden — sonst risse ein '
            'Ausfall von Supabase jede Fehlerbehandlung mit.',
      );
    });

    test('eine Senke, die selbst loggt, endet nicht in einer Schleife', () {
      var calls = 0;
      setLogErrorSink((_, _, _) {
        calls++;
        log.e('aus der Senke heraus');
      });
      log.e('Testfall');
      expect(
        calls,
        1,
        reason:
            'Reentranz-Riegel: Loggte die Senke selbst (etwa ihren eigenen '
            'Fehlschlag), meldete sich das sonst endlos weiter.',
      );
    });
  });
}
