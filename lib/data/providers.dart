/// providers.dart – Zentrale Provider-Registry des Data-Layers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fairness.dart';
import '../core/supabase_config.dart';
import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'auth_repository.dart';
import 'carpool_repository.dart';
import 'fake_repository.dart';
import 'supabase_repository.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authRepositoryProvider = Provider<AuthRepository>((ref) =>
    SupabaseConfig.isConfigured
        ? SupabaseAuthRepository(ref.watch(supabaseClientProvider))
        : AlwaysLoggedInAuthRepository());

final carpoolRepositoryProvider = Provider<CarpoolRepository>((ref) =>
    SupabaseConfig.isConfigured
        ? SupabaseCarpoolRepository(ref.watch(supabaseClientProvider))
        : demoRepository());

/// Auth-Zustand als Stream — steuert Router-Redirect und Daten-Reload.
final authStateProvider = StreamProvider<dynamic>(
    (ref) => ref.watch(authRepositoryProvider).onAuthStateChange);

final personsProvider = FutureProvider<List<Person>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(carpoolRepositoryProvider).loadPersons();
});

final tripsProvider = FutureProvider<List<Trip>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(carpoolRepositoryProvider).loadTrips();
});

final settingsProvider = FutureProvider<AppSettings>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(carpoolRepositoryProvider).loadSettings();
});

/// Statistik aller Personen, abgeleitet aus Fahrten + Parametern.
final statsProvider = FutureProvider<Map<String, PersonStats>>((ref) async {
  final trips = await ref.watch(tripsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  return computeStats(trips, settings);
});

/// Fairness-Ranking über alle aktiven Personen (Dashboard-Ansicht).
final activeRankingProvider =
    FutureProvider<List<RankedCandidate>>((ref) async {
  final persons = await ref.watch(personsProvider.future);
  final stats = await ref.watch(statsProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final activeIds = [
    for (final p in persons)
      if (p.active) p.id,
  ];
  return rankPresent(activeIds, stats, settings);
});
