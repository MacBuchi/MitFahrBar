/// error_report_repository.dart – Schreibt gefangene Fehler nach
/// `public.error_reports` (Issue #136).
///
/// MitFahrBar wird an den Stores vorbei ausgeliefert — keine Play-Vitals,
/// keine Crash-Statistik. Ein gefangener Fehler zeigt eine SnackBar und
/// verschwindet; wer abstürzt, meldet nicht, der deinstalliert. Die Senke
/// ist bewusst KEIN Crash-Dienst (kein Sentry, Issue #18): eigene Tabelle
/// im eigenen Projekt, insert-only, gelesen nur vom Feedback-Bot
/// (Wochen-Digest, 90-Tage-Löschung). Muster von PilzBuddy.
///
/// Bewusst genügsam: kein `logRing` im automatischen Bericht (der bleibt
/// dem bewussten Feedback-Weg vorbehalten) und keine Personennamen — die
/// Felder können sie strukturell nicht tragen. `group_id` schreibt die
/// Datenbank selbst (Default + Trigger), nie der Client.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';

/// Gekürzt auf die Längen-Checks des Schemas. Ein Fehlertext kann in
/// Ausnahmefällen Serverdetails tragen — die Grenzen halten das klein.
String? _clip(String? value, int max) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
}

/// Was NICHT gemeldet wird: der Alltag eines Handys im Auto. Funkloch und
/// Zeitüberschreitung sind hier Normalbetrieb — als Berichte ersäuften sie
/// den Wochen-Digest (PilzBuddy: 193 Zeilen für abgebrochene Kachel-Jobs).
///
/// `AuthException` bleibt bewusst MELDEWÜRDIG: Ein vertipptes Passwort
/// erzeugt keinen `log.e`-Aufruf, wohl aber eine kaputte Auth-Config —
/// genau die Fehlerklasse, die am 23.07.2026 die Registrierung still
/// brach. Nur die Netz-Variante ist Rauschen.
bool worthReporting(Object? error) {
  if (error == null) return true; // bewusstes log.e ohne Objekt
  if (error is TimeoutException) return false;
  if (error is http.ClientException) return false;
  if (error is AuthRetryableFetchException) return false;
  // SocketException per Text: `dart:io` gibt es auf Web nicht, ein
  // Typ-Check bräche den PWA-Build.
  final text = error.toString();
  return !text.contains('SocketException') &&
      !text.contains('Failed host lookup');
}

/// Reine Aufbereitung, getrennt vom Netzzugriff — testbar wie
/// `chart_data.dart`. Die Schlüssel sind zugleich die PII-Zusage: Es gibt
/// schlicht kein Feld, in dem ein Personenname stehen könnte.
Map<String, Object?> buildErrorReportRow({
  required String context,
  Object? error,
  StackTrace? stackTrace,
  String? appVersion,
  required String platform,
}) {
  return {
    // Der DB-Check verlangt 1–100 Zeichen — ein leerer Kontext würde den
    // Bericht kosten, nicht den Fehler.
    'context': _clip(context, 100) ?? 'unbekannt',
    'error_type': _clip(error?.runtimeType.toString(), 100) ?? 'LogError',
    'message': _clip(error?.toString(), 1000),
    'stack': _clip(stackTrace?.toString(), 4000),
    'app_version': _clip(appVersion, 40),
    'platform': _clip(platform, 20),
  };
}

class ErrorReportRepository {
  ErrorReportRepository(this._client);

  final SupabaseClient _client;

  /// Obergrenze je App-Lauf: Eine Absturzschleife darf die Tabelle nicht
  /// fluten. Der Digest zählt ohnehin nur — ab hier sagt mehr nichts Neues.
  static const maxPerRun = 20;
  int _sent = 0;

  static String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> report(
    String context,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    if (_sent >= maxPerRun) return;
    _sent++;
    final version = await PackageInfo.fromPlatform()
        .then<String?>((info) => info.version)
        // Version ist nice-to-have; ohne sie ist der Bericht immer noch
        // wertvoll, deshalb schlucken statt den Bericht fallen zu lassen.
        .catchError((Object _) => null);

    await _client
        .from('error_reports')
        .insert(
          buildErrorReportRow(
            context: context,
            error: error,
            stackTrace: stackTrace,
            appVersion: version,
            platform: _platform,
          ),
        );
  }
}

/// Meldet Provider-Fehler — die Lücke, die kein globaler Handler sieht:
/// Riverpod verwandelt sie in `AsyncError`-State, der Screen zeigt eine
/// Meldung, und `PlatformDispatcher.onError` erfährt nie davon.
class ErrorReportObserver extends ProviderObserver {
  ErrorReportObserver(this._forward);

  final void Function(String context, Object? error, StackTrace? stack)
  _forward;

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    _forward(
      provider.name ?? provider.runtimeType.toString(),
      error,
      stackTrace,
    );
  }
}

/// Verdrahtet die Senke hinter Logger und Providern. Wird NUR in `main()`
/// gerufen, wenn Supabase konfiguriert ist — in Tests und im Demo-Modus
/// bleibt der Sink leer und `flutter test` netzfrei.
ErrorReportObserver wireErrorReporting(SupabaseClient client) {
  final repository = ErrorReportRepository(client);
  void forward(String context, Object? error, StackTrace? stack) {
    if (!worthReporting(error)) return;
    unawaited(
      repository.report(context, error, stack).catchError((Object _) {
        // Die Senke darf nie selbst zum Fehler werden — und ihr Fehlschlag
        // nie über log.e laufen, sonst meldete er sich selbst (Schleife).
      }),
    );
  }

  setLogErrorSink(forward);
  return ErrorReportObserver(forward);
}
