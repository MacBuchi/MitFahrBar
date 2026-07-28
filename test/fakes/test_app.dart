/// test_app.dart – Startet die ECHTE App gegen In-Memory-Fakes.
///
/// Flow-Tests laufen dadurch durch Router, Gates und Screens wie in
/// Produktion; nur das Backend ist ersetzt.
library;

import 'package:mitfahrbar/app.dart';
import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fake_admin_repository.dart';
import 'fake_auth_repository.dart';
import 'fake_backend.dart';

/// Startet die App und wartet, bis die erste Ansicht steht.
///
/// [overrides] hängt hinten an und sticht deshalb die Standard-Fakes —
/// gedacht für Provider, die auf die Plattform zugreifen (z. B. das
/// Ablegen einer Datei), die es im Test nicht gibt.
///
/// [splash] ist standardmäßig aus: Sonst müsste jeder Flow-Test erst die
/// Anfahr-Animation abwarten, bevor er ans Login kommt. Nur der
/// Splash-Flow-Test schaltet sie ein.
/// Das „Heute" aller Flow-Tests: ein Mittwoch mitten in der Woche, damit
/// die geplante Woche den Testtag enthält und Eintragen möglich ist.
/// Wer in einem Test `planningWeek()` braucht, ruft `planningWeek(testToday)`
/// auf — sonst rechnet der Test mit einer anderen Woche als die App.
final DateTime testToday = DateTime(2026, 7, 22);

/// [identity] schaltet die Geräte-Zuordnung (#121) EIN und gibt ihren
/// Startzustand vor. Standardmäßig ist sie **aus** — aus demselben Grund wie
/// beim Splash: `SupabaseConfig.isConfigured` ist im Test `true` (der
/// eingecheckte Default ist die echte Projekt-URL), also träfe sonst jeder
/// Flow-Test zuerst auf die Startabfrage oder das Banner statt auf seinen
/// eigenen Inhalt.
Future<void> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  List<Override> overrides = const [],
  bool splash = false,
  DeviceIdentity? identity,
}) async {
  await initializeDateFormatting('de');
  addTearDown(backend.dispose);
  // „Bewegung reduzieren" wie im System: Die Dauerschleifen der Gesichter
  // ruhen, sonst käme kein pumpAndSettle je zur Ruhe. Bewusst nicht beim
  // Splash-Test gesetzt — der prüft ja gerade eine Animation und steuert
  // die Zeit von Hand (auf dem Login gibt es keine Gesichter).
  if (!splash) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        splashEnabledProvider.overrideWithValue(splash),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
        carpoolRepositoryProvider.overrideWithValue(
          FakeRoutingCarpoolRepository(backend),
        ),
        groupRepositoryProvider.overrideWithValue(FakeGroupRepository(backend)),
        adminRepositoryProvider.overrideWithValue(FakeAdminRepository(backend)),
        feedbackRepositoryProvider.overrideWithValue(
          FakeFeedbackRepository(backend),
        ),
        // Ohne diesen Fake liefe der Sperr-Schirm gegen einen nicht
        // initialisierten Supabase-Client — und jeder Flow-Test scheiterte
        // daran statt an seinem eigentlichen Inhalt.
        appConfigRepositoryProvider.overrideWithValue(
          FakeAppConfigRepository(backend),
        ),
        // Im Test gibt es weder FCM noch einen Berechtigungsdialog. Ohne
        // diese beiden Overrides griffe schon der App-Start auf ein nicht
        // initialisiertes Firebase zu — der Fehler landete im Log und der
        // Screen zeigte sich dauerhaft als „nicht eingerichtet".
        pushRepositoryProvider.overrideWithValue(FakePushRepository(backend)),
        // Der Ausgangskorb (#132) hängt an der App-Wurzel und liefe sonst in
        // jedem Flow-Test gegen das echte Netz — `SupabaseConfig.isConfigured`
        // ist im Test `true`. Was er schreibt, steht in `backend.outbox`.
        pushOutboxRepositoryProvider.overrideWithValue(
          FakePushOutboxRepository(backend),
        ),
        pushTokenProvider.overrideWithValue(
          ({required bool ask}) async => 'test-token',
        ),
        pushTapListenerProvider.overrideWithValue((onTap) async {}),
        // Der Fake merkt sich den Empfänger, damit ein Test eine Nachricht
        // zustellen kann (`backend.deliverPush`). Ohne Override griffe die
        // App beim Start auf FirebaseMessaging zu.
        pushMessageListenerProvider.overrideWithValue((onMessage) async {
          backend.pushMessageSink = onMessage;
        }),
        // Kein Netzzugriff im Test: standardmäßig kein Update und keine
        // Release-Notes (der Über-Dialog blendet den Abschnitt dann aus).
        updateInfoProvider.overrideWith((ref) => Future.value(backend.update)),
        currentVersionProvider.overrideWith((ref) => Future.value('1.0.0')),
        currentReleaseNotesProvider.overrideWith((ref) => Future.value(null)),
        // Feste Uhr: Tests laufen immer an [testToday], egal an welchem
        // Wochentag die CI läuft. Ohne das kippten die Plan-Flow-Tests
        // samstags — der Planer zeigt am Wochenende die kommende Woche,
        // und deren Tage sind noch nicht bestätigbar (25.07.2026).
        nowProvider.overrideWithValue(() => testToday),
        identityEnabledProvider.overrideWithValue(identity != null),
        deviceIdentityStoreProvider.overrideWithValue(
          InMemoryDeviceIdentityStore(identity ?? DeviceIdentity.unknown),
        ),
        ...overrides,
      ],
      child: const FahrgemeinschaftApp(),
    ),
  );
  if (splash) {
    // Nicht settlen: pumpAndSettle spulte die Animation komplett ab, und
    // der Test fände einen Splash vor, der schon vorbei ist. Die Zeit
    // steuert der Test selbst.
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
}
