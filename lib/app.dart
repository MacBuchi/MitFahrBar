/// app.dart – MaterialApp.router, Theme und Locale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'features/banners/update_required_screen.dart';
import 'features/splash/splash_overlay.dart';

class FahrgemeinschaftApp extends ConsumerWidget {
  const FahrgemeinschaftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MitFahrBar',
      routerConfig: router,
      // Der Sperr-Schirm liegt über allem, auch über dem Login: Wer zu alt
      // ist, soll sich gar nicht erst anmelden. Solange der Check lädt, läuft
      // die App normal weiter — ein Ladezustand darf nicht wie eine Sperre
      // aussehen. Der Splash liegt noch einmal darüber: erst der Auftritt,
      // dann die Pflichten.
      builder: (context, child) {
        final required = ref.watch(updateRequiredProvider).value;
        return SplashGate(
          child: required == null
              ? (child ?? const SizedBox.shrink())
              : UpdateRequiredScreen(info: required),
        );
      },
      theme: lightTheme(),
      darkTheme: darkTheme(),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
    );
  }
}
