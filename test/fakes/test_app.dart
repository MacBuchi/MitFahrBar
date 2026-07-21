/// test_app.dart – Startet die ECHTE App gegen In-Memory-Fakes.
///
/// Flow-Tests laufen dadurch durch Router, Gates und Screens wie in
/// Produktion; nur das Backend ist ersetzt.
library;

import 'package:fahrgemeinschaft/app.dart';
import 'package:fahrgemeinschaft/core/update_check.dart';
import 'package:fahrgemeinschaft/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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
Future<void> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  List<Override> overrides = const [],
  bool splash = false,
}) async {
  await initializeDateFormatting('de');
  addTearDown(backend.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        splashEnabledProvider.overrideWithValue(splash),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
        carpoolRepositoryProvider.overrideWithValue(
          FakeRoutingCarpoolRepository(backend),
        ),
        groupRepositoryProvider.overrideWithValue(FakeGroupRepository(backend)),
        feedbackRepositoryProvider.overrideWithValue(
          FakeFeedbackRepository(backend),
        ),
        // Ohne diesen Fake liefe der Sperr-Schirm gegen einen nicht
        // initialisierten Supabase-Client — und jeder Flow-Test scheiterte
        // daran statt an seinem eigentlichen Inhalt.
        appConfigRepositoryProvider.overrideWithValue(
          FakeAppConfigRepository(backend),
        ),
        // Kein Netzzugriff im Test: standardmäßig kein Update.
        updateInfoProvider.overrideWith((ref) => Future.value(backend.update)),
        currentVersionProvider.overrideWith((ref) => Future.value('1.0.0')),
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
