/// app.dart – MaterialApp.router, Theme und Locale.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push_messaging.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/tokens.dart';
import 'data/providers.dart';
import 'features/banners/update_required_screen.dart';
import 'features/splash/splash_overlay.dart';

class FahrgemeinschaftApp extends ConsumerStatefulWidget {
  const FahrgemeinschaftApp({super.key});

  @override
  ConsumerState<FahrgemeinschaftApp> createState() =>
      _FahrgemeinschaftAppState();
}

class _FahrgemeinschaftAppState extends ConsumerState<FahrgemeinschaftApp> {
  /// Damit eine eintreffende Nachricht über **jedem** Screen erscheint.
  ///
  /// Ohne diesen globalen Anker hinge die Anzeige daran, wo die Nutzerin
  /// gerade ist: Ein Handler in einem einzelnen Screen zeigte nichts, wenn
  /// sie im Planer, in der Historie oder in der Statistik steht — also fast
  /// immer. `ScaffoldMessenger` gehört deshalb hier hoch, wo es genau einen
  /// gibt.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Ein Tipp auf eine Benachrichtigung führt immer in den Planer — jede
    // Nachricht dieses Features handelt von einem Tag darin (Issue #101).
    // Auch aus dem kalten Start heraus, deshalb hier und nicht im Router.
    unawaited(
      ref.read(pushTapListenerProvider)(
        () => ref.read(routerProvider).go(pushTapRoute),
      ),
    );
    // Und was eintrifft, während die App vorne ist, zeigt sonst niemand an
    // (siehe listenForPushMessages) — bis 0.39.0 verschwanden diese
    // Nachrichten spurlos, echte Abend-Meldungen eingeschlossen.
    unawaited(
      ref.read(pushMessageListenerProvider)((title, body) {
        _messengerKey.currentState
          // Zwei Meldungen kurz nacheinander sollen einander nicht
          // wegdrücken, aber auch nicht stapeln.
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 8),
              // Derselbe Ton, in den Android das Icon im
              // Benachrichtigungs-Schatten färbt: Dieselbe Nachricht sieht
              // drinnen aus wie draußen.
              backgroundColor: AppPush.surface,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppPush.ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(body, style: const TextStyle(color: AppPush.ink)),
                ],
              ),
              action: SnackBarAction(
                label: 'Woche',
                textColor: AppPush.action,
                onPressed: () => ref.read(routerProvider).go(pushTapRoute),
              ),
            ),
          );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MitFahrBar',
      routerConfig: router,
      scaffoldMessengerKey: _messengerKey,
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
              // Eigener Navigator, und das ist die Rettungsleine selbst:
              // `child` IST der Router-Navigator, und der Sperr-Schirm
              // ERSETZT ihn. Ohne diesen Ersatz gäbe es im gesperrten
              // Zustand keinen Navigator und kein Overlay im Baum —
              // `showDialog` wirft dann „Navigator operation requested with
              // a context that does not include a Navigator", Flutter
              // schluckt die Exception, und der Update-Knopf tut sichtbar
              // NICHTS. Genau so ist es am 26.07.2026 auf einem Pixel 7
              // passiert: Der Schirm sperrte, der Knopf war tot, es half nur
              // Deinstallieren und Neuinstallieren von Hand.
              //
              // Im Normalbetrieb fiel es nie auf, weil das Update-Banner
              // innerhalb des Router-Navigators sitzt. Kaputt war
              // ausschließlich der Weg, den man nur im gesperrten Zustand
              // sieht — der einzige, auf den es dann ankommt.
              : Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => UpdateRequiredScreen(info: required),
                  ),
                ),
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
