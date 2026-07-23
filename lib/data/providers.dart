/// providers.dart – Zentrale Provider-Registry des Data-Layers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/export_file.dart';
import '../core/import_file.dart';
import '../core/fairness.dart';
import '../core/share_text.dart';
import '../core/supabase_config.dart';
import '../core/update_check.dart';
import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/plan_ride.dart';
import '../models/trip.dart';
import 'admin_repository.dart';
import 'app_config_repository.dart';
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

/// Wie ein Text weitergegeben wird (Teilen-Menü bzw. Zwischenablage).
/// Als Provider, damit Tests den Plattform-Pfad ersetzen können — im Test
/// hängt der echte Aufruf, statt zu scheitern.
typedef TextSharer =
    Future<ShareOutcome> Function(String text, {String? subject});

final textSharerProvider = Provider<TextSharer>((ref) => shareText);

/// Ob die Anfahr-Animation beim Start läuft (`features/splash/`). Als
/// Provider, damit `pumpApp` sie stilllegen kann — sonst müsste jeder
/// Flow-Test erst 3 Sekunden Splash abwarten, bevor er ans Login kommt.
final splashEnabledProvider = Provider<bool>((ref) => true);

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

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseAdminRepository(ref.watch(supabaseClientProvider))
      : NoopAdminRepository(),
);

/// Die verknüpfte Gruppe eines Verwalter-Kontos (`null` = unverknüpft).
final adminGroupProvider = FutureProvider<AdminGroup?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adminRepositoryProvider).myAdminGroup();
});

final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabaseAppConfigRepository(ref.watch(supabaseClientProvider))
      : NoopAppConfigRepository(),
);

/// Kleinste noch unterstützte App-Version — `null`, wenn unbekannt. Hängt
/// bewusst **nicht** an `currentUserIdProvider`: Der Wert gilt gruppen- und
/// anmeldungsunabhängig, und der Sperr-Schirm soll schon vor dem Login greifen.
final minSupportedVersionProvider = FutureProvider<String?>(
  (ref) => ref.watch(appConfigRepositoryProvider).minSupportedVersion(),
);

/// Das Update, das **erzwungen** werden muss — sonst `null`.
///
/// Hintergrund (Issue #19): Migrationen laufen automatisch beim Push auf
/// `main`, ein installiertes APK bleibt aber, wo es ist. Die Datenbank kann
/// dem Client also davonlaufen, und der scheitert dann still oder zeigt
/// Teildaten. Besser ein ehrlicher Schirm als eine App, die halb funktioniert.
///
/// Liegt hier und nicht in `core/update_check.dart`, weil er einen
/// Core-Provider mit einem Data-Provider verknüpft — `core/` darf `data/`
/// nicht kennen.
///
/// Drei Sicherungen, die zusammengehören; jede einzelne wegzulassen macht aus
/// dem Schutz eine Falle:
///
/// 1. **Kein Update verfügbar ⇒ nie sperren.** Damit ist zugesichert, dass
///    der neueste Client nie ausgesperrt wird — es gibt immer einen Weg
///    heraus. Ohne das sperrte ein Tippfehler in der Mindestversion
///    (`99.0.0`) alle aus, und die einzige Korrektur wäre eine weitere
///    Migration.
/// 2. **Mindestversion unbekannt ⇒ nie sperren.** `null` heißt offline,
///    Tabelle fehlt oder Zeile fehlt. Eine Sperre aus einem Netzwerkfehler
///    wäre schlimmer als der veraltete Client, den sie verhindern soll.
/// 3. **Gleichstand ist erlaubt.** Gesperrt wird nur *unterhalb* der
///    Mindestversion; `isNewerVersion` liefert bei Gleichstand `false`.
final updateRequiredProvider = FutureProvider<UpdateInfo?>((ref) async {
  final update = await ref.watch(updateInfoProvider.future);
  if (update == null) return null;
  final minimum = await ref.watch(minSupportedVersionProvider.future);
  if (minimum == null) return null;
  final current = await ref.watch(currentVersionProvider.future);
  return isNewerVersion(minimum, current) ? update : null;
});

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
///
/// Als Notifier statt FutureProvider, damit Tippen im Raster **sofort**
/// sichtbar wird: Die Änderung wird lokal eingerechnet (`planWeek` ist
/// reine, schnelle Rechnung) und erst danach zum Server geschrieben.
/// Vorher waren es zwei serielle Netz-Roundtrips pro Tap — der Planer
/// fühlte sich träge an. Schlägt der Schreib fehl, holt `invalidateSelf`
/// die Server-Wahrheit zurück, und der Fehler geht an den Aufrufer
/// (SnackBar im Screen).
final weekPlanProvider =
    AsyncNotifierProvider<WeekPlanNotifier, List<PlannedDay>>(
      WeekPlanNotifier.new,
    );

class WeekPlanNotifier extends AsyncNotifier<List<PlannedDay>> {
  /// Server-Rohzustand, an dem die optimistischen Änderungen ansetzen —
  /// Schlüssel auf Tagesbeginn normiert, damit Taps ihre Zeile finden.
  var _availability = <DateTime, Map<String, PlanRide>>{};
  var _overrides = <DateTime, String>{};
  var _dates = const <DateTime>[];
  var _trips = const <Trip>[];
  var _settings = const AppSettings();
  var _seats = const <String, int>{};

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Future<List<PlannedDay>> build() async {
    ref.watch(currentUserIdProvider);
    _dates = planningWeek();
    final raw = await ref
        .watch(carpoolRepositoryProvider)
        .loadPlan(_dates.first, days: 7);
    // Per watch: Ändern sich Fahrten, Personen oder Parameter, rechnet der
    // Notifier von allein neu — wie vorher der FutureProvider.
    _trips = await ref.watch(tripsProvider.future);
    _settings = await ref.watch(settingsProvider.future);
    final persons = await ref.watch(personsProvider.future);
    _seats = {for (final p in persons) p.id: p.seats};
    // Verfügbarkeiten **inaktiver** Personen bleiben draußen — dieselbe
    // Regel wie in Rangliste und Fahrten-Editor. Wer inaktiv gestellt
    // wird, kann noch Einträge aus seiner aktiven Zeit haben; die zählten
    // sonst unsichtbar als Kopf (Tagesgröße, Sitzplatz-Prüfung, vollstes
    // Auto) und würden beim „Eintragen" sogar als Mitfahrt gebucht — das
    // verschöbe rückwirkend die Punkte (am Tages-Hajo gefunden,
    // 2026-07-22: das Raster zeigt Inaktive nicht, der Zähler sah sie).
    final active = {
      for (final p in persons)
        if (p.active) p.id,
    };
    _availability = {
      for (final e in raw.availability.entries)
        _day(e.key): {
          for (final r in e.value.entries)
            if (active.contains(r.key)) r.key: r.value,
        },
    };
    _overrides = {for (final e in raw.overrides.entries) _day(e.key): e.value};
    return _plan();
  }

  List<PlannedDay> _plan() => planWeek(
    dates: _dates,
    availability: _availability,
    overrides: _overrides,
    trips: _trips,
    settings: _settings,
    seats: _seats,
  );

  /// Erst lokal zeigen, dann schreiben; bei Fehler Server-Wahrheit zurück
  /// und den Fehler nach oben reichen.
  Future<void> _apply(void Function() mutate, Future<void> write) async {
    mutate();
    state = AsyncData(_plan());
    try {
      await write;
    } catch (_) {
      ref.invalidateSelf();
      rethrow;
    }
  }

  /// Ein Tap im Raster: kann nicht → dabei → nur eine Richtung → kann nicht.
  Future<void> cycleRide(DateTime date, String personId) {
    final day = _day(date);
    final rides = {...(_availability[day] ?? const <String, PlanRide>{})};
    final next = switch (rides[personId]) {
      null => PlanRide.full,
      PlanRide.full => PlanRide.oneWay,
      PlanRide.oneWay => null,
    };
    return _apply(
      () {
        if (next == null) {
          rides.remove(personId);
        } else {
          rides[personId] = next;
        }
        _availability[day] = rides;
      },
      ref.read(carpoolRepositoryProvider).setAvailability(date, personId, next),
    );
  }

  /// Fahrer übersteuern; `null` kehrt zum Vorschlag zurück.
  Future<void> setDriver(DateTime date, String? driverId) {
    final day = _day(date);
    return _apply(() {
      if (driverId == null) {
        _overrides.remove(day);
      } else {
        _overrides[day] = driverId;
      }
    }, ref.read(carpoolRepositoryProvider).setPlanDriver(date, driverId));
  }
}

/// Gespeicherte Verfügbarkeit EINES Tages (Person → wie sie mitfährt),
/// gefiltert auf aktive Personen — dieselbe Regel wie im [WeekPlanNotifier]
/// (Issue #54). Der Fahrten-Editor belegt damit bei einer NEUEN Fahrt die
/// Teilnehmer-Auswahl vor (Issue #65). Bewusst nicht über [weekPlanProvider]:
/// Der deckt nur die zu planende Woche ab, der Editor aber jedes vergangene
/// Datum. Der Schlüssel muss auf Tagesbeginn normiert sein, sonst entsteht
/// je Uhrzeit ein eigener Cache-Eintrag; `autoDispose` räumt verlassene Tage
/// beim Datumswechsel weg.
final dayAvailabilityProvider = FutureProvider.autoDispose
    .family<Map<String, PlanRide>, DateTime>((ref, day) async {
      ref.watch(currentUserIdProvider);
      final plan = await ref
          .watch(carpoolRepositoryProvider)
          .loadPlan(day, days: 1);
      final persons = await ref.watch(personsProvider.future);
      final active = {
        for (final p in persons)
          if (p.active) p.id,
      };
      // Nur ein Tag abgefragt — alles Zurückgekommene gehört zu [day];
      // so hängt nichts am Schlüsselformat der Antwort.
      return {
        for (final rides in plan.availability.values)
          for (final e in rides.entries)
            if (active.contains(e.key)) e.key: e.value,
      };
    });
