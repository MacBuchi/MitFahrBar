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
Future<void> pumpApp(WidgetTester tester, FakeBackend backend) async {
  await initializeDateFormatting('de');
  addTearDown(backend.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(backend)),
        carpoolRepositoryProvider.overrideWithValue(
          FakeRoutingCarpoolRepository(backend),
        ),
        groupRepositoryProvider.overrideWithValue(FakeGroupRepository(backend)),
        feedbackRepositoryProvider.overrideWithValue(
          FakeFeedbackRepository(backend),
        ),
        // Kein Netzzugriff im Test: standardmäßig kein Update.
        updateInfoProvider.overrideWith((ref) => Future.value(backend.update)),
        currentVersionProvider.overrideWith((ref) => Future.value('1.0.0')),
      ],
      child: const FahrgemeinschaftApp(),
    ),
  );
  await tester.pumpAndSettle();
}
