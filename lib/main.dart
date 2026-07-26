/// main.dart – Bootstrap: Error-Handler, Supabase-Init, runApp.
library;

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
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  runApp(const ProviderScope(child: FahrgemeinschaftApp()));
}
