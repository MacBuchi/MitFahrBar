/// providers.dart – Zentrale Provider-Registry des Data-Layers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/export_file.dart';
import '../core/import_file.dart';
import '../core/fairness.dart';
import '../core/supabase_config.dart';
import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'auth_repository.dart';
import 'carpool_repository.dart';
import 'fake_repository.dart';
import 'feedback_repository.dart';
import 'group_repository.dart';
import 'supabase_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Wie eine erzeugte Datei beim Nutzer ankommt (Download bzw. Teilen-Menü).
/// Als Provider, damit Tests den Plattform-Pfad ersetzen können — im Test
/// gibt es weder Browser noch Teilen-Menü.
typedef FileSaver =
    Future<void> Function({required String name, required String content});

final fileSaverProvider = Provider<FileSaver>((ref) => saveTextFile);

/// Dateiauswahl fürs Einlesen — `null` heißt abgebrochen. Ebenfalls als
/// Provider, damit Tests eine Datei vortäuschen können; im Test gibt es
/// keinen Dateidialog.
typedef FilePicker = Future<String?> Function();

final filePickerProvider = Provider<FilePicker>((ref) => pickCsvText);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseAuthRepository(ref.watch(supabaseClientProvider))
      : AlwaysLoggedInAuthRepository(),
);

final carpoolRepositoryProvider = Provider<CarpoolRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseCarpoolRepository(ref.watch(supabaseClientProvider))
      : demoRepository(),
);

final groupRepositoryProvider = Provider<GroupRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseGroupRepository(ref.watch(supabaseClientProvider))
      : DemoGroupRepository(),
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseFeedbackRepository(ref.watch(supabaseClientProvider))
      : NoopFeedbackRepository(),
);

/// Auth-Zustand als Stream — steuert den Router-Redirect.
final authStateProvider = StreamProvider<dynamic>(
  (ref) => ref.watch(authRepositoryProvider).onAuthStateChange,
);

/// Stabile Kennung des angemeldeten Zugangs. Daten-Provider hängen hieran
/// statt am Event-Stream, damit sie nur bei echtem An-/Abmelden neu laden.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).currentUserId;
});

/// Die Gruppe des aktuellen Logins (Status/Admin) — Gate für die App.
final myGroupProvider = FutureProvider<Group?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).myGroup();
});

/// Offene Gruppen-Anfragen (für den Admin-Screen).
final pendingGroupsProvider = FutureProvider<List<Group>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).pendingGroups();
});

final personsProvider = FutureProvider<List<Person>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadPersons();
});

final tripsProvider = FutureProvider<List<Trip>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadTrips();
});

final settingsProvider = FutureProvider<AppSettings>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadSettings();
});

/// Statistik aller Personen, abgeleitet aus Fahrten + Parametern.
final statsProvider = FutureProvider<Map<String, PersonStats>>((ref) async {
  final trips = await ref.watch(tripsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  return computeStats(trips, settings);
});

/// Fairness-Ranking über alle aktiven Personen (Dashboard-Ansicht).
final activeRankingProvider = FutureProvider<List<RankedCandidate>>((
  ref,
) async {
  final persons = await ref.watch(personsProvider.future);
  final stats = await ref.watch(statsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final activeIds = [
    for (final p in persons)
      if (p.active) p.id,
  ];
  return rankPresent(activeIds, stats, settings);
});

/// Wochenplan der zu planenden Woche, inklusive Fahrer-Vorschlägen.
final weekPlanProvider = FutureProvider<List<PlannedDay>>((ref) async {
  ref.watch(currentUserIdProvider);
  final dates = planningWeek();
  final raw = await ref
      .watch(carpoolRepositoryProvider)
      .loadPlan(dates.first, days: 7);
  final trips = await ref.watch(tripsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final persons = await ref.watch(personsProvider.future);
  return planWeek(
    dates: dates,
    availability: raw.availability,
    overrides: raw.overrides,
    trips: trips,
    settings: settings,
    seats: {for (final p in persons) p.id: p.seats},
  );
});
