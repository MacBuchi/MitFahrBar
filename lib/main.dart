/// main.dart – Bootstrap: Error-Handler, Supabase-Init, runApp.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/licenses.dart';
import 'core/log.dart';
import 'core/push_messaging.dart';
import 'core/supabase_config.dart';
import 'data/error_report_repository.dart';
import 'data/exit_info_repository.dart';
import 'data/exit_reporting.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();

  FlutterError.onError = (details) {
    log.e('FlutterError', error: details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.e('Uncaught', error: error, stackTrace: stack);
    return true;
  };

  await initializeDateFormatting('de');
  // Vor runApp, damit ein Tipp auf eine Benachrichtigung aus dem kalten Start
  // heraus ankommt. Schluckt jeden Fehler: Ein kaputtes Firebase-Projekt darf
  // die App nicht am Starten hindern (Issue #101).
  await initPushMessaging();
  // Fehler-Senke (#136): Logger- und Provider-Fehler melden nach
  // `error_reports` — nur im echten Betrieb; im Demo-Modus und in Tests
  // bleibt der Sink leer und die App netzfrei.
  final observers = <ProviderObserver>[];
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    // Dieselbe Instanz für Sink und Exit-Reporter: ein gemeinsamer
    // maxPerRun-Deckel je App-Lauf.
    final reports = ErrorReportRepository(Supabase.instance.client);
    observers.add(wireErrorReporting(reports));
    // #144: Warum die App beim letzten Mal starb (ANR, Crash,
    // Speicher-Kill) — bewusst ohne await: Der Start darf darauf nicht
    // warten, und scheitern darf es sowieso. Auf Web/iOS ein No-Op.
    unawaited(
      ExitReporter(
        exits: ExitInfoRepository(),
        reports: reports,
      ).reportPending(),
    );
  }

  runApp(
    ProviderScope(observers: observers, child: const FahrgemeinschaftApp()),
  );
}
