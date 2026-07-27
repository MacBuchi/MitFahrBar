/// providers.dart – Zentrale Provider-Registry des Data-Layers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/export_file.dart';
import '../core/import_file.dart';
import '../core/fairness.dart';
import '../core/push_messaging.dart';
import '../core/share_text.dart';
import '../core/supabase_config.dart';
import '../core/update_check.dart';
import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
import '../models/trip.dart';
import 'admin_repository.dart';
import 'app_config_repository.dart';
import 'auth_repository.dart';
import 'carpool_repository.dart';
import 'device_identity.dart';
import 'fake_repository.dart';
import 'feedback_repository.dart';
import 'group_repository.dart';
import 'push_repository.dart';
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

/// Das Push-Token dieses Geräts. Ebenfalls als Provider, damit Tests den
/// Plattform-Pfad ersetzen können — im Test gibt es weder FCM noch einen
/// Berechtigungsdialog. `ask` steuert, ob gefragt oder nur nachgesehen wird.
typedef PushTokenSource = Future<String?> Function({required bool ask});

final pushTokenProvider = Provider<PushTokenSource>((ref) => pushToken);

/// Verdrahtet den Tipp auf eine Benachrichtigung mit dem Router. Ebenfalls
/// als Provider: Ohne Override griffe der Test auf FirebaseMessaging zu, das
/// es dort nicht gibt.
typedef PushTapListener = Future<void> Function(void Function() onTap);

final pushTapListenerProvider = Provider<PushTapListener>(
  (ref) => listenForPushTaps,
);

/// Nachrichten, die eintreffen, während die App vorne ist — sie zeigt kein
/// System an, das muss die App selbst tun. Als Provider aus demselben Grund
/// wie die beiden oben: Im Test gibt es kein FirebaseMessaging.
typedef PushMessageListener =
    Future<void> Function(void Function(String title, String body) onMessage);

final pushMessageListenerProvider = Provider<PushMessageListener>(
  (ref) => listenForPushMessages,
);

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabasePushRepository(ref.watch(supabaseClientProvider))
      : NoopPushRepository(),
);

/// Wo die Geräte-Zuordnung liegt. Im Demo-Modus und in Tests flüchtig — dort
/// gibt es nichts zu behalten.
final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>(
  (ref) => SupabaseConfig.isConfigured
      ? SharedPrefsDeviceIdentityStore()
      : InMemoryDeviceIdentityStore(),
);

/// Ob die Geräte-Zuordnung überhaupt greift.
///
/// **Im Demo-Modus aus.** Dort gibt es kein Gerät, dem man etwas zustellen
/// könnte, und keine Gruppe, in der man sich vertippen könnte — die Frage
/// hätte keine Folge. Sie stünde aber als modaler Dialog über der Übersicht,
/// und genau davon lebt der README-Screenshot. Ohne diesen Riegel entscheidet
/// ein Wettlauf darüber, ob das Bild die App zeigt oder einen Dialog: Die
/// Startabfrage wartet auf die Push-Abfrage im Provider, und je nachdem, wie
/// schnell die zurückkommt, ist der Dialog beim Auslösen schon da oder nicht.
///
/// In Tests standardmäßig ebenfalls **aus** (`pumpApp` überschreibt), aus
/// demselben Grund wie beim Splash: Sonst träfe jeder Flow-Test zuerst auf
/// Dialog oder Banner. `SupabaseConfig.isConfigured` ist im Test nämlich
/// `true` — der eingecheckte Default ist die echte Projekt-URL, erst ein
/// `--dart-define` auf den Platzhalter schaltet den Demo-Modus.
final identityEnabledProvider = Provider<bool>(
  (ref) => SupabaseConfig.isConfigured,
);

/// Wer an diesem Gerät sitzt (#121) — **kein Login**, siehe
/// `data/device_identity.dart`.
final deviceIdentityProvider =
    AsyncNotifierProvider<DeviceIdentityNotifier, DeviceIdentity>(
      DeviceIdentityNotifier.new,
    );

class DeviceIdentityNotifier extends AsyncNotifier<DeviceIdentity> {
  @override
  Future<DeviceIdentity> build() async {
    if (!ref.watch(identityEnabledProvider)) return DeviceIdentity.skipped;

    final store = ref.watch(deviceIdentityStoreProvider);
    final stored = await store.load();
    if (stored.asked || stored.chosen) return stored;

    // Wer heute schon Push nutzt, hat die Frage längst beantwortet — dann
    // steht die Person in `push_devices`. Ohne diesen Griff fragte die App
    // die halbe Gruppe nach etwas, das sie schon gesagt hat.
    //
    // `ask: false`: Ein ungefragter Berechtigungsdialog wird weggetippt, und
    // Android fragt danach nie wieder.
    try {
      final token = await ref.read(pushTokenProvider)(ask: false);
      if (token == null) return stored;
      final state = await ref.read(pushRepositoryProvider).stateFor(token);
      final personId = state.personId;
      if (personId == null) return stored;
      final adopted = DeviceIdentity(personId: personId, asked: true);
      await store.save(adopted);
      return adopted;
    } catch (_) {
      // Kein Netz, kein Firebase, kein Problem: Dann wird eben gefragt.
      return stored;
    }
  }

  /// Eine Person übernehmen — oder mit `null` bewusst überspringen. Beides
  /// zählt als beantwortet, damit die Startabfrage nicht wiederkommt.
  Future<void> choose(String? personId) async {
    final next = DeviceIdentity(personId: personId, asked: true);
    state = AsyncData(next);
    await ref.read(deviceIdentityStoreProvider).save(next);
  }
}

/// Die gewählte Person als Objekt — `null`, solange keine gewählt ist oder
/// die Auswahl auf eine gelöschte Person zeigt.
final myPersonProvider = Provider<Person?>((ref) {
  final id = ref.watch(deviceIdentityProvider).value?.personId;
  if (id == null) return null;
  final persons = ref.watch(personsProvider).value;
  if (persons == null) return null;
  for (final person in persons) {
    if (person.id == id) return person;
  }
  return null;
});

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

/// Die Gruppen eines Verwalter-Kontos, älteste zuerst (leer = keine).
final adminGroupsProvider = FutureProvider<List<AdminGroup>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adminRepositoryProvider).myAdminGroups();
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

/// Die Gruppe des aktuellen Logins (Name, Status) — Gate für die App.
final myGroupProvider = FutureProvider<Group?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).myGroup();
});

final personsProvider = FutureProvider<List<Person>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadPersons();
});

final tripsProvider = FutureProvider<List<Trip>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadTrips();
});

/// Die Uhr der App — überall dort, wo Fachlogik vom „Heute" abhängt.
///
/// In Tests überschreibbar; `pumpApp` stellt sie auf einen festen Mittwoch.
/// Der Grund ist ein realer Ausfall (25.07.2026, ein Samstag): Der Planer
/// plant am Wochenende richtigerweise die kommende Woche, deren Tage noch
/// nicht bestätigbar sind — die Plan-Flow-Tests hingen aber an der echten
/// Wanduhr und kippten deshalb an genau zwei Wochentagen. Eine Suite, die
/// samstags anderes prüft als montags, ist keine.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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
  var _overrides = <DateTime, Set<String>>{};
  var _dates = const <DateTime>[];
  var _trips = const <Trip>[];
  var _settings = const AppSettings();
  var _seats = const <String, int>{};

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Future<List<PlannedDay>> build() async {
    ref.watch(currentUserIdProvider);
    _dates = planningWeek(ref.read(nowProvider)());
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
    _overrides = {
      for (final e in raw.overrides.entries) _day(e.key): {...e.value},
    };
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

  /// Verfügbarkeit direkt setzen; `null` heißt „kann nicht".
  ///
  /// Der Tipp im Raster schaltet weiter ([cycleRide]), die Rückfrage bei einer
  /// fremden Zeile (#121) setzt direkt — beide landen hier. Eine zweite
  /// Schreibstelle hieße zwei Fassungen der optimistischen Einrechnung samt
  /// `invalidateSelf` im Fehlerfall, und die driften.
  Future<void> setRide(DateTime date, String personId, PlanRide? ride) {
    final day = _day(date);
    final rides = {...(_availability[day] ?? const <String, PlanRide>{})};
    return _apply(
      () {
        if (ride == null) {
          rides.remove(personId);
        } else {
          rides[personId] = ride;
        }
        _availability[day] = rides;
      },
      ref.read(carpoolRepositoryProvider).setAvailability(date, personId, ride),
    );
  }

  /// Ein Tap im Raster: kann nicht → dabei → nur eine Richtung → kann nicht.
  Future<void> cycleRide(DateTime date, String personId) =>
      setRide(date, personId, switch (_availability[_day(date)]?[personId]) {
        null => PlanRide.full,
        PlanRide.full => PlanRide.oneWay,
        PlanRide.oneWay => null,
      });

  /// Fahrer-Menge übersteuern (Issue #62); leer kehrt zum Vorschlag zurück.
  Future<void> setDrivers(DateTime date, Set<String> driverIds) {
    final day = _day(date);
    return _apply(() {
      if (driverIds.isEmpty) {
        _overrides.remove(day);
      } else {
        _overrides[day] = {...driverIds};
      }
    }, ref.read(carpoolRepositoryProvider).setPlanDrivers(date, driverIds));
  }
}

/// Der Tag für das Banner „nächste Fahrt" auf der Übersicht (#122).
///
/// Reine Ableitung aus [weekPlanProvider] — keine eigene Ladung. Der Preis
/// steht trotzdem an: Weil die Übersicht das jetzt beobachtet, lädt der
/// Wochenplan schon beim App-Start und nicht erst beim Öffnen des Planers.
/// Das ist eine Anfrage mehr und der Gegenwert des Banners.
final nextRideProvider = Provider<AsyncValue<PlannedDay?>>((ref) {
  final now = ref.watch(nowProvider);
  return ref.watch(weekPlanProvider).whenData((week) => nextRide(week, now()));
});

/// Die Anmerkungen der Planwoche, nach Kalendertag (Issue #127).
///
/// Eine Anfrage für die ganze Woche, dieselbe Spanne wie [weekPlanProvider] —
/// daraus speisen sich der Zähler je Tag im Planer **und** der am Banner
/// „nächste Fahrt". Weil der nächste Fahrtag per Konstruktion in dieser Woche
/// liegt ([nextRideProvider] filtert dieselbe Liste), kostet das Banner
/// dadurch keine zweite Anfrage.
///
/// Die Schlüssel sind auf Tagesbeginn normiert — sonst fände ein Nachschlagen
/// mit `PlannedDay.date` seine Zeile nicht (dieselbe Falle wie im
/// [WeekPlanNotifier]).
final weekNotesProvider = FutureProvider<Map<DateTime, List<PlanNote>>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final dates = planningWeek(ref.read(nowProvider)());
  final notes = await ref
      .watch(carpoolRepositoryProvider)
      .loadNotes(dates.first, days: 7);
  final byDay = <DateTime, List<PlanNote>>{};
  for (final note in notes) {
    final day = DateTime(note.date.year, note.date.month, note.date.day);
    (byDay[day] ??= <PlanNote>[]).add(note);
  }
  return byDay;
});

/// Die Anmerkungen EINES Tages, älteste zuerst — für den Anmerkungs-Schirm.
///
/// Bewusst nicht aus [weekNotesProvider] abgeleitet: Der deckt nur die zu
/// planende Woche ab, der Schirm ist aber über eine Adresse (`/notes/:date`)
/// direkt erreichbar. Schlüssel auf Tagesbeginn normiert, sonst entsteht je
/// Uhrzeit ein eigener Cache-Eintrag; `autoDispose` räumt verlassene Tage weg.
final dayNotesProvider = FutureProvider.autoDispose
    .family<List<PlanNote>, DateTime>((ref, day) {
      ref.watch(currentUserIdProvider);
      return ref.watch(carpoolRepositoryProvider).loadNotes(day, days: 1);
    });

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
