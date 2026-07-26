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
import '../features/notifications/notifications_screen.dart';
import '../features/persons/persons_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/trip_editor/trip_editor_screen.dart';
import '../features/trip_editor/trip_editor_seed.dart';

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
      AsyncError(:final error) => Scaffold(
        body: Center(child: Text('Fehler: $error')),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
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
