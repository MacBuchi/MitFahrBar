/// router.dart – Navigation mit Auth-Guard (redirect + refreshListenable)
/// und Gruppen-Gate (pending/aktiv) im AppShell.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../data/providers.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/pending_screen.dart';
import '../features/console/console_login_screen.dart';
import '../features/console/console_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/help/help_screen.dart';
import '../features/history/history_screen.dart';
import '../features/import/import_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/persons/persons_screen.dart';
import '../features/prices/prices_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/trip_editor/trip_editor_screen.dart';
import '../features/trip_editor/trip_editor_seed.dart';
import 'tokens.dart';

/// Stößt den Router-Redirect an, sobald sich der Auth-Zustand ändert.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  // `passwordRecovery` bewusst nicht durchlassen: Ein eingelöster Reset-Code
  // erzeugt eine gültige Verwalter-Sitzung, BEVOR das neue Passwort gesetzt
  // ist. Reagierte der Router darauf, risse der Redirect (Admin-Sitzung →
  // /console) den Konsolen-Login mitten im Zurücksetzen weg — und bei einem
  // Fehlschlag säße jemand angemeldet in der Konsole, ohne sein Passwort zu
  // kennen. Der Login-Screen bleibt deshalb stehen, bis `updateUser` das
  // Passwort wirklich geändert hat; dessen Ereignis öffnet die Konsole dann
  // (siehe AuthRepository.resetAdminPasswordWithCode).
  final refresh = _AuthRefresh(
    authRepository.onAuthStateChange.where((e) => !isPasswordRecovery(e)),
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = authRepository.loggedIn;
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/login' || loc == '/console/login';
      if (!loggedIn) {
        if (onAuthPage) return null;
        // Wer die Konsole ansteuert, landet auf deren Anmeldung, nicht auf
        // dem Gruppen-Login.
        return loc.startsWith('/console') ? '/console/login' : '/login';
      }
      // Verwalter-Sitzungen bleiben in der Konsole — sie sehen ohnehin
      // keine Gruppendaten (anderer uid, RLS blockt), aber der Redirect
      // erspart die verwirrende Leer-Ansicht.
      if (authRepository.isAdminSession) {
        return loc == '/console' ? null : '/console';
      }
      if (onAuthPage || loc.startsWith('/console')) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/console/login',
        builder: (context, state) => const ConsoleLoginScreen(),
      ),
      GoRoute(
        path: '/console',
        builder: (context, state) => const ConsoleScreen(),
      ),
      GoRoute(path: '/help', builder: (context, state) => const HelpScreen()),
      GoRoute(
        path: '/import',
        builder: (context, state) => const ImportScreen(),
      ),
      GoRoute(
        path: '/persons',
        builder: (context, state) => const PersonsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/prices',
        builder: (context, state) => const PricesScreen(),
      ),
      GoRoute(
        path: '/trip/new',
        // `extra` trägt die Vorbelegung aus dem Eintragen-je-Auto-Ablauf
        // des Planers (Issue #62) — bewusst kein URL-Parameter: Die Menge
        // an IDs gehört nicht in eine teilbare Adresse, und ein Reload
        // ohne extra landet schlicht im leeren Editor.
        builder: (context, state) =>
            TripEditorScreen(seed: state.extra as TripEditorSeed?),
      ),
      GoRoute(
        path: '/trip/:id',
        builder: (context, state) =>
            TripEditorScreen(tripId: state.pathParameters['id']),
      ),
      GoRoute(
        // Anmerkungen eines Tages (#127). Das Datum steht als
        // ISO-Kalendertag im Pfad — anders als beim Fahrten-Editor ist das
        // hier richtig: Ein Reload oder ein geteilter Link soll denselben
        // Tag zeigen. `tryParse` statt `parse`, weil eine getippte Adresse
        // alles enthalten kann; der Screen erklärt den Fall, statt zu
        // scheitern.
        path: '/notes/:date',
        builder: (context, state) => NotesScreen(
          date: DateTime.tryParse(state.pathParameters['date'] ?? ''),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/plan',
                builder: (context, state) => const PlanScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// App-Rahmen mit Gruppen-Gate: nur eine aktive Gruppe sieht die Tabs,
/// pending/abgelehnt sieht den Warte-Screen.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(myGroupProvider);

    return switch (group) {
      AsyncData(value: final g) when g != null && g.isActive => Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Übersicht',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month),
              label: 'Woche',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'Historie',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Statistik',
            ),
          ],
        ),
      ),
      AsyncData(value: final g) when g != null => PendingScreen(
        status: g.status,
      ),
      AsyncData() => const _NoGroupScreen(),
      AsyncError(:final error) => _GateErrorScreen(error: error),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Das Gruppen-Gate konnte nicht gelesen werden — meist schlicht: kein Netz.
///
/// Bis v0.59.1 stand hier `Text('Fehler: $error')` ohne Rahmen: Wer die App
/// ohne Empfang öffnete, sah nackten Ausnahmetext samt Projekt-URL und
/// Gruppen-Kennung, ohne Navigation und ohne Weg zurück (Issue #169, auf dem
/// Pixel 7 Pro im Flugmodus reproduziert). Drei Dinge daran waren schlecht,
/// und alle drei sind hier beantwortet:
///
/// * **Es gab keinen Ausweg.** `myGroupProvider` hängt an
///   `currentUserIdProvider`, und der ändert sich bewusst nur bei echtem
///   An-/Abmelden — kommt das Netz zurück, läuft von allein *nichts* neu. Ohne
///   den Knopf hier half nur, die App zu beenden. Derselbe Fehler wie beim
///   toten Update-Knopf in 0.37.0, weshalb der Regressionstest ihn **tippt**
///   und sich nicht damit begnügt, ihn zu finden.
/// * **Der Rohtext gehört nicht auf den Schirm.** Er sagt der Gruppe nichts
///   und trägt Adressen nach außen; die Fehlersenke (#136) hat ihn ohnehin
///   längst — `wireErrorReporting` meldet Provider-Fehler nach
///   `error_reports`. Auf dem Schirm steht ein Satz, im Bericht der Fehler.
/// * **Kein Netz ist kein Defekt.** Ein `SocketException`/`ClientException`
///   bekommt deshalb seinen eigenen Text; alles andere bleibt beim
///   allgemeinen. Unterschieden wird über die String-Form, wie schon bei
///   [isPasswordRecovery] — die Typen stammen aus `http`/`dart:io` und wären
///   im Web-Build nicht dieselben.
class _GateErrorScreen extends ConsumerWidget {
  const _GateErrorScreen({required this.error});

  final Object error;

  /// Netzausfälle melden sich je nach Plattform als `SocketException`
  /// (mobil), `ClientException` (http-Paket) oder `Failed to fetch` (Web).
  static bool looksOffline(Object error) {
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup') ||
        text.contains('Failed to fetch');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = looksOffline(error);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  offline ? Icons.wifi_off_outlined : Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  offline ? 'Keine Verbindung' : 'Das hat nicht geklappt',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  offline
                      ? 'MitFahrBar erreicht gerade den Server nicht. Sobald '
                            'du wieder Empfang hast, geht es hier weiter.'
                      : 'Die Fahrgemeinschaft konnte nicht geladen werden. '
                            'Versuch es gleich noch einmal.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.l),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(myGroupProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut versuchen'),
                ),
                const SizedBox(height: AppSpacing.s),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eingeloggt, aber kein Gruppen-Datensatz (sollte praktisch nicht vorkommen).
class _NoGroupScreen extends ConsumerWidget {
  const _NoGroupScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Diesem Zugang ist keine Gruppe zugeordnet.',
                textAlign: TextAlign.center,
              ),
            ),
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Abmelden'),
            ),
          ],
        ),
      ),
    );
  }
}
