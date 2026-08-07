/// providers.dart – Zentrale Provider-Registry des Data-Layers.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/chart_data.dart';
import '../core/export_file.dart';
import '../core/import_file.dart';
import '../core/fairness.dart';
import '../core/log.dart';
import '../core/notification_health_probe.dart';
import '../core/push_messaging.dart';
import '../core/price_series.dart';
import '../core/push_outbox.dart';
import '../core/share_text.dart';
import '../core/stats_data.dart';
import '../core/stats_insights.dart';
import '../core/supabase_config.dart';
import '../core/trip_push.dart';
import '../core/update_check.dart';
import '../models/app_settings.dart';
import '../models/group.dart';
import '../models/group_defaults.dart';
import '../models/seat_choice.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import '../models/plan_ride.dart';
import '../models/price_area.dart';
import '../models/trip.dart';
import 'admin_repository.dart';
import 'app_config_repository.dart';
import 'auth_repository.dart';
import 'carpool_repository.dart';
import 'device_identity.dart';
import 'fake_repository.dart';
import 'feedback_repository.dart';
import 'group_repository.dart';
import 'price_repository.dart';
import 'push_outbox_repository.dart';
import 'push_repository.dart';
import 'supabase_repository.dart';
import 'caching_repository.dart';
import 'offline_cache.dart';

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

/// Fragt Android, ob eine Meldung überhaupt ankommen darf (#180).
///
/// Als Provider aus demselben Grund wie [pushTokenProvider]: Im Test gibt es
/// keinen Plattform-Kanal, und der Flow-Test muss eine Blockade stellen
/// können, ohne ein Gerät zu haben.
final notificationHealthProbeProvider = Provider<NotificationHealthProbe>(
  (ref) => const NotificationHealthProbe(),
);

final pushOutboxRepositoryProvider = Provider<PushOutboxRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabasePushOutboxRepository(ref.watch(supabaseClientProvider))
      : NoopPushOutboxRepository(),
);

final priceRepositoryProvider = Provider<PriceRepository>(
  (ref) => SupabaseConfig.isConfigured
      ? SupabasePriceRepository(ref.watch(supabaseClientProvider))
      : const NoopPriceRepository(),
);

/// Der Bereich dieser Gruppe. `null` heißt: noch nicht eingerichtet.
///
/// Hängt an `currentUserIdProvider` und nicht am Auth-Ereignisstrom — sonst
/// lüde jedes Ereignis, auch ein Token-Refresh, alles neu.
final priceAreaProvider = FutureProvider<PriceArea?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(priceRepositoryProvider).loadArea();
});

/// Die gemessenen Wochenwerte. Die Lücken füllt erst `weeklySeries` beim
/// Zeichnen aus den Gruppensettings — gespeichert wird eine Konstante nie.
final priceWeeksProvider = FutureProvider<List<PricePoint>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(priceRepositoryProvider).loadWeeks();
});

/// Die Ersparnis-Kurve der Startseite — `null`, solange etwas fehlt.
///
/// **Eine Quelle für Kachel und Diagramm.** Die Zahl „Kraftstoff gespart"
/// und die Kurve darunter stehen auf derselben Seite; würde die Kachel über
/// `savedCosts` mit der Konstante rechnen und die Kurve je Woche mit dem
/// gemessenen Preis, stünden dort zwei verschiedene Summen für dasselbe.
///
/// Bewusst **erst mit** den Preisen: Mit `?? const []` rechnete die Karte
/// beim Aufbau kurz mit den Konstanten und spränge dann sichtbar auf die
/// echte Summe. Fehlen die Preise dauerhaft (Fehler), bleibt die Karte weg —
/// dieselbe Linie wie bei den anderen Diagrammen: Eine Karte, die nichts
/// weiß, sagt besser nichts.
final savingsChartProvider = Provider<SavingsChart?>((ref) {
  final trips = ref.watch(tripsProvider).value;
  final persons = ref.watch(personsProvider).value;
  final settings = ref.watch(settingsProvider).value;
  final weeks = ref.watch(priceWeeksProvider);
  if (trips == null || persons == null || settings == null) return null;
  if (!weeks.hasValue) return null;

  final window = savingsWindow(trips, now: ref.watch(nowProvider)());
  if (window == null) return null;
  final (from, to) = window;
  return weeklySavings(
    trips: trips,
    persons: persons,
    settings: settings,
    storedPrices: weeks.requireValue,
    from: from,
    to: to,
  );
});

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

/// Die Ablage des letzten bekannten Stands (#169).
final offlineCacheProvider = Provider<OfflineCache>(
  (ref) => PrefsOfflineCache(),
);

/// Woher der gezeigte Stand kam — `null` heißt „frisch vom Server".
///
/// Ein einzelnes Objekt für die ganze App: Beide Dekorierer melden hierhin,
/// die Leiste im [AppShell] hört zu.
final offlineStatusProvider = Provider<OfflineStatus>((ref) => OfflineStatus());

/// Wessen Zeilen im Zwischenspeicher liegen dürfen. `null` = kein Speicher.
///
/// Bewusst über `currentUserId` und nicht über die geladene Gruppe: Die
/// Kennung muss schon feststehen, **bevor** der erste Lesezugriff läuft —
/// sonst könnte der allererste (`myGroup`) nie aus dem Speicher bedient
/// werden, und genau der ist das Gate vor der ganzen App.
final _cacheGroupIdProvider = Provider<String? Function()>(
  (ref) =>
      () => ref.read(authRepositoryProvider).currentUserId,
);

final carpoolRepositoryProvider = Provider<CarpoolRepository>((ref) {
  if (!SupabaseConfig.isConfigured) return demoRepository();
  return CachingCarpoolRepository(
    SupabaseCarpoolRepository(ref.watch(supabaseClientProvider)),
    ref.watch(offlineCacheProvider),
    ref.watch(offlineStatusProvider),
    ref.watch(_cacheGroupIdProvider),
  );
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  if (!SupabaseConfig.isConfigured) return DemoGroupRepository();
  return CachingGroupRepository(
    SupabaseGroupRepository(ref.watch(supabaseClientProvider)),
    ref.watch(offlineCacheProvider),
    ref.watch(offlineStatusProvider),
    ref.watch(_cacheGroupIdProvider),
  );
});

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

/// Abfahrtszeiten und Treffpunkt der Gruppe (#139).
///
/// Bewusst ein eigener Provider neben [settingsProvider]: Die Vorgaben gehen
/// in Banner und Benachrichtigung ein, die Parameter in Kilometer und
/// Ersparnis — wer das eine invalidiert, soll nicht das andere neu laden.
final groupDefaultsProvider = FutureProvider<GroupDefaults>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(carpoolRepositoryProvider).loadGroupDefaults();
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

/// Fahrten je Woche für die Statistik-Seite — bewusst OHNE das Preisarchiv:
/// `savingsChartProvider` ist `null`, solange Preise fehlen; die Frage „wann
/// wurde gefahren" braucht keinen Preis, also darf ihre Karte nicht mit dem
/// Preisabruf verschwinden.
final weeklyTripBarsProvider = Provider<WeeklyTripBars?>((ref) {
  final trips = ref.watch(tripsProvider).value;
  if (trips == null) return null;
  return weeklyTripBars(trips, now: ref.watch(nowProvider)());
});

/// Die rotierten Insight-Karten der Statistik-Seite — leer, solange etwas
/// lädt. Jede Karte erscheint nur, wenn ihre Zahl berechenbar ist; die
/// „Sparsamste Woche" fehlt ohne Preise schlicht, wie alles am Preisarchiv.
final statsInsightsProvider = Provider<List<StatsInsight>>((ref) {
  final trips = ref.watch(tripsProvider).value;
  final persons = ref.watch(personsProvider).value;
  final settings = ref.watch(settingsProvider).value;
  final stats = ref.watch(statsProvider).value;
  if (trips == null || persons == null || settings == null || stats == null) {
    return const [];
  }
  final chart = ref.watch(savingsChartProvider);
  final now = ref.watch(nowProvider)();
  final names = {for (final person in persons) person.id: person.name};

  final available = <StatsInsight>[];
  void add(StatsInsight? insight) {
    if (insight != null) available.add(insight);
  }

  add(distanceInsight(stats, settings));
  if (chart != null) add(bestWeekInsight(chart));
  add(kmHeroInsight(trips, settings, names, now: now));
  add(streakInsight(trips));
  return rotateInsights(available, now: now);
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
  var _seatChoices = <DateTime, List<SeatChoice>>{};
  var _carDefaults = const <DateTime, Map<String, GroupDefaults>>{};

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
    // Sitz-Entscheidungen (#189, Stufe B2) und die Auto-Abweichungen, gegen
    // die ihre Gültigkeit geprüft wird — beide per watch: Eine geänderte
    // Auto-Zeit lässt Zusagen veralten und muss den Plan neu rechnen.
    _seatChoices = {
      for (final e
          in (await ref
                  .watch(carpoolRepositoryProvider)
                  .loadSeatChoices(_dates.first, days: 7))
              .entries)
        _day(e.key): e.value,
    };
    _carDefaults = {
      for (final e in (await ref.watch(weekCarDefaultsProvider.future)).entries)
        _day(e.key): e.value,
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
    seatChoices: _seatChoices,
    carDefaults: _carDefaults,
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

  /// Die gemerkte Entscheidung von [personId] über das Auto von [driverId] —
  /// für die Rückfrage im Planer (#189): Wer zu genau diesen Bedingungen
  /// schon entschieden hat, wird nicht noch einmal gefragt.
  ///
  /// **Bewusst am Notifier statt an einem eigenen Provider**: Hier liegt die
  /// Kopie, mit der auch gerechnet wird — inklusive der optimistischen
  /// Schreibvorgänge. Ein zweiter Ladepfad wäre beim Nachfragen einen
  /// Roundtrip hinterher und fragte genau dann doppelt.
  SeatChoice? seatChoiceFor(DateTime date, String personId, String driverId) =>
      _seatChoices[_day(date)]
          ?.where((c) => c.personId == personId && c.driverId == driverId)
          .firstOrNull;

  /// Sitz-Entscheidung setzen oder ersetzen (#189, Stufe B2) — optimistisch
  /// wie jeder Tap: Wer zustimmt, sitzt sofort im Auto, nicht erst nach dem
  /// Roundtrip.
  Future<void> setSeatChoice(SeatChoice choice) {
    final day = _day(choice.date);
    return _apply(() {
      final rows = [...(_seatChoices[day] ?? const <SeatChoice>[])]
        ..removeWhere(
          (c) => c.personId == choice.personId && c.driverId == choice.driverId,
        )
        ..add(choice);
      _seatChoices[day] = rows;
    }, ref.read(carpoolRepositoryProvider).saveSeatChoice(choice));
  }

  /// Entscheidung zurücknehmen — die Person wird wieder automatisch verteilt.
  Future<void> clearSeatChoice(
    DateTime date,
    String personId,
    String driverId,
  ) {
    final day = _day(date);
    return _apply(
      () {
        _seatChoices[day]?.removeWhere(
          (c) => c.personId == personId && c.driverId == driverId,
        );
      },
      ref
          .read(carpoolRepositoryProvider)
          .deleteSeatChoice(date, personId, driverId),
    );
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
/// Die Abweichungen der Planwoche, nach Kalendertag (#183).
///
/// Dieselbe Spanne und dieselbe Normierung wie [weekNotesProvider], und aus
/// demselben Grund: Nachgeschlagen wird mit `PlannedDay.date`, und ein Tag mit
/// Uhrzeit fände seine Zeile nicht.
///
/// Ein Tag ohne Abweichung fehlt in der Map. „Keine Abweichung" und „leere
/// Abweichung" sind dasselbe — zwei Schreibweisen dafür wären zwei Fälle im
/// Digest, und einer davon würde vergessen.
final weekPlanDefaultsProvider = FutureProvider<Map<DateTime, GroupDefaults>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final dates = planningWeek(ref.read(nowProvider)());
  return ref
      .watch(carpoolRepositoryProvider)
      .loadPlanDefaults(dates.first, days: 7);
});

/// Die Abweichungen einzelner **Autos** der Planwoche (#183, Stufe B):
/// Tag → Fahrer → Abweichung.
///
/// Die dritte Ebene über [weekPlanDefaultsProvider] und
/// [groupDefaultsProvider]; aufgelöst wird `Auto → Tag → Gruppe`, feldweise.
final weekCarDefaultsProvider =
    FutureProvider<Map<DateTime, Map<String, GroupDefaults>>>((ref) async {
      ref.watch(currentUserIdProvider);
      final dates = planningWeek(ref.read(nowProvider)());
      return ref
          .watch(carpoolRepositoryProvider)
          .loadCarDefaults(dates.first, days: 7);
    });

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

/// Hält den Ausgangskorb (#132) am Stand der Dinge.
///
/// **Warum ein Zuhörer und keine Aufrufe an den Mutationsstellen.** Der Text
/// hängt an Plan, Personen und Anmerkungen — und der Plan wiederum an
/// Fahrten, Parametern und Sitzplätzen. Eine eingetragene Fahrt verschiebt
/// über die Vorwärtssimulation die Fahrer *späterer* Tage. Wer das an jeder
/// Schreibstelle von Hand nachzieht, vergisst irgendwann eine, und niemand
/// findet es je. Hier hört einer auf das fertige Ergebnis; alles, was den
/// Plan ändert, läuft ohnehin durch [weekPlanProvider].
///
/// **Und wenn er doch einmal nicht feuert**, ist das kein Ausfall: Der
/// stündliche Job rechnet den Korb neu. Der Ereignis-Weg ist ein
/// Beschleuniger, keine Zusage — schlechter als der bisherige 10-Minuten-Takt
/// kann es dadurch nie werden.
///
/// Geschrieben wird für die ganze Woche, nie nur für den bearbeiteten Tag:
/// „ausrechnen, was betroffen ist" ist genau der Fehler, den man später nicht
/// mehr sieht. Vierzig Zeilen kosten nichts.
final pushOutboxSyncProvider = Provider<void>((ref) {
  // Ohne Anmeldung gibt es keine Gruppe, in deren Korb geschrieben würde.
  if (ref.watch(currentUserIdProvider) == null) return;

  final week = ref.watch(weekPlanProvider).valueOrNull;
  final persons = ref.watch(personsProvider).valueOrNull;
  final notes = ref.watch(weekNotesProvider).valueOrNull;
  // Die Vorgaben (#139) stehen im Text, deshalb hängt der Korb auch an ihnen:
  // Wer die Abfahrtszeit ändert, soll sie in der nächsten Meldung lesen.
  // Ausgelöst wird dadurch nichts — der Digest kennt sie bewusst nicht.
  final defaults = ref.watch(groupDefaultsProvider).valueOrNull;
  // Die Abweichungen einzelner Tage (#183). Anders als die Vorgabe stehen sie
  // sehr wohl im Digest: Eine verschobene Abfahrt ist eine Tatsache über
  // diesen Tag, keine Parameter-Änderung — wer sie verschiebt, muss die
  // Mitfahrenden wecken.
  final dayDefaults = ref.watch(weekPlanDefaultsProvider).valueOrNull;
  // Und je Auto (Stufe B): Zwei Autos desselben Tages können verschieden
  // früh losfahren.
  final carDefaults = ref.watch(weekCarDefaultsProvider).valueOrNull;
  // Ein halb geladener Stand schriebe einen halben Text. Lieber gar nichts —
  // der stündliche Job holt es nach.
  if (week == null ||
      persons == null ||
      notes == null ||
      defaults == null ||
      dayDefaults == null ||
      carDefaults == null) {
    return;
  }

  final active = {
    for (final person in persons)
      if (person.active) person.id: person,
  };
  if (active.isEmpty) return;

  final now = ref.read(nowProvider)();
  final entries = outboxEntries(
    week: week,
    persons: active,
    now: now,
    notes: [for (final day in notes.values) ...day],
    defaults: defaults,
    dayDefaults: dayDefaults,
    carDefaults: carDefaults,
    // Wer an diesem Gerät sitzt, hat gerade selbst getippt und braucht
    // keine Meldung darüber (#163). Best effort: ohne Geräte-Zuordnung
    // wird nichts unterdrückt, und der stündliche Job hebt es wieder auf.
    suppressPersonId: ref.watch(myPersonProvider)?.id,
  );
  unawaited(
    ref
        .read(pushOutboxRepositoryProvider)
        .publish(entries, keepFrom: outboxKeepFrom(now))
        // Scheitert das Schreiben, ist das kein Fall für die Nutzerin: Sie
        // hat nichts falsch gemacht und kann nichts tun. **Ohne Fehlertext**
        // — der könnte die Nutzlast mitführen, und darin stehen Namen.
        // Dieselbe Regel wie beim Einladungstext.
        .catchError((Object error) {
          log.w('Ausgangskorb nicht geschrieben (${error.runtimeType})');
        }),
  );
});

/// Meldet geänderte und gelöschte Fahrten (#163).
///
/// **Ein zweiter Zuhörer neben [pushOutboxSyncProvider], und bewusst kein
/// Aufruf im Fahrten-Editor.** Eine Fahrt entsteht und ändert sich an
/// mehreren Stellen — Editor, Planer („Eintragen"), CSV-Import, zweites
/// Gerät. Ein Haken an jeder davon wäre einer, den man beim nächsten Weg
/// vergisst; hier hört einer auf das fertige Ergebnis.
///
/// Der vorige Stand wird selbst gemerkt und nicht aus dem `previous` des
/// Listeners genommen: Ein `invalidate` schickt den Provider über
/// `AsyncLoading` (mit altem Wert) nach `AsyncData`, der Listener feuert also
/// mehrfach für dieselbe Änderung. Gegen die eigene Merkzelle verglichen
/// entsteht der Diff genau einmal.
///
/// **Die Erstladung meldet nichts.** Ohne diesen Riegel bekäme jede Person
/// beim App-Start eine Meldung über jede Fahrt, die es gibt.
final tripPushSyncProvider = Provider<void>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return;

  List<Trip>? seen;
  ref.listen(tripsProvider, (_, next) {
    final trips = next.valueOrNull;
    if (trips == null) return;
    final previous = seen;
    seen = trips;
    if (previous == null) return;

    final persons = ref.read(personsProvider).valueOrNull;
    if (persons == null) return;
    final active = {
      for (final person in persons)
        if (person.active) person.id: person,
    };

    final entries = tripChangeEntries(
      previous: previous,
      next: trips,
      persons: active,
      now: ref.read(nowProvider)(),
      defaults:
          ref.read(groupDefaultsProvider).valueOrNull ?? const GroupDefaults(),
      dayDefaults: ref.read(weekPlanDefaultsProvider).valueOrNull ?? const {},
      suppressPersonId: ref.read(myPersonProvider)?.id,
    );
    if (entries.isEmpty) return;

    unawaited(
      ref
          .read(pushOutboxRepositoryProvider)
          .publish(entries, keepFrom: outboxKeepFrom(ref.read(nowProvider)()))
          // **Ohne Fehlertext** — er könnte die Nutzlast mitführen, und darin
          // stehen Namen. Dieselbe Regel wie beim Einladungstext.
          .catchError((Object error) {
            log.w('Fahrt-Meldung nicht geschrieben (${error.runtimeType})');
          }),
    );
  });
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
