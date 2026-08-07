/// fake_backend.dart – In-Memory-Backend für Tests.
///
/// Bildet die Mandantentrennung der echten Datenbank nach: Daten hängen an
/// einer Gruppe, und man sieht ausschließlich die Daten der Gruppe, mit der
/// man angemeldet ist. So laufen Flow-Tests durch die echte App, ohne dass
/// eine Lücke im Fake echte RLS-Fehler verstecken kann.
library;

import 'dart:async';

import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/push_outbox.dart';
import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/data/admin_repository.dart';
import 'package:mitfahrbar/data/app_config_repository.dart';
import 'package:mitfahrbar/data/carpool_repository.dart';
import 'package:mitfahrbar/data/fake_repository.dart';
import 'package:mitfahrbar/data/feedback_repository.dart';
import 'package:mitfahrbar/data/group_repository.dart';
import 'package:mitfahrbar/data/price_repository.dart';
import 'package:mitfahrbar/models/price_area.dart';
import 'package:mitfahrbar/data/push_outbox_repository.dart';
import 'package:mitfahrbar/data/push_repository.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_note.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/seat_choice.dart';
import 'package:mitfahrbar/models/trip.dart';

class FakeAccount {
  FakeAccount({required this.password, required this.groupId});

  String password;
  final String groupId;
}

/// Verwalter-Konto (Konsole): echte E-Mail, eigenes Passwort, bis zu
/// [groupCap] verknüpfte Gruppen. `confirmed` bildet die
/// Bestätigungspflicht ab: Frisch registrierte Konten sind unbestätigt und
/// können sich nicht anmelden, bis der Code aus der Mail (im Fake: das Flag)
/// eingelöst ist.
class FakeAdminAccount {
  FakeAdminAccount({required this.password, this.confirmed = true});

  String password;
  bool confirmed;

  /// Reihenfolge zählt: Die Konsole zeigt die Gruppen nach Alter sortiert,
  /// und die Tests greifen Karten über ihren Namen.
  final List<String> groupIds = [];
}

class FakeBackend {
  final Map<String, FakeAccount> accounts = {};
  final Map<String, FakeAdminAccount> adminAccounts = {};

  /// Wohin eine Nachricht geht, die eintrifft, während die App vorne ist —
  /// gesetzt von `pumpApp`. [deliverPush] ist die Fake-Entsprechung von
  /// `FirebaseMessaging.onMessage`, das es im Test nicht gibt.
  void Function(String title, String body)? pushMessageSink;

  /// Stellt eine Nachricht zu, als käme sie gerade von FCM.
  void deliverPush(String title, String body) =>
      pushMessageSink?.call(title, body);

  /// Was der Client zuletzt in den Ausgangskorb geschrieben hat (#132), je
  /// Gruppe — die Fake-Entsprechung von `publish_push_outbox`. Damit kann
  /// ein Flow-Test prüfen, dass eine Änderung im Planer wirklich bis dorthin
  /// durchschlägt, statt nur zu glauben, dass der Zuhörer feuert.
  final Map<String, List<OutboxEntry>> outbox = {};

  /// Adressen, für die ein Passwort-Reset angefordert wurde — die Fake-
  /// Entsprechung der Mail, die in Produktion rausgeht. Enthält auch
  /// unbekannte Adressen: Die App darf beide Fälle nicht unterscheiden.
  final List<String> passwordResets = [];

  /// Adressen, für die die Bestätigungs-Mail erneut angefordert wurde.
  final List<String> confirmationResends = [];

  /// Die Codes, die der Fake in der „Mail" verschickt. Fest statt zufällig,
  /// damit Tests sie kennen; echt sind es sechs Ziffern von GoTrue.
  static const resetCode = '123456';
  static const confirmCode = '654321';

  /// Angeforderte E-Mail-Wechsel (neue Adresse) — wie in Produktion gilt
  /// der Wechsel erst nach beiden Bestätigungs-Links, der Fake wendet ihn
  /// deshalb bewusst nicht an.
  final List<String> emailChangeRequests = [];

  final Map<String, Group> groups = {};
  final Map<String, FakeCarpoolRepository> _data = {};
  final List<Map<String, Object?>> feedback = [];
  final _authController = StreamController<Object?>.broadcast();

  /// Optionales „verfügbares Update" für Banner-Tests.
  UpdateInfo? update;

  /// Kleinste unterstützte Version — `null` heißt „unbekannt" und sperrt
  /// niemanden aus, genau wie ein Netzwerkfehler in der echten App.
  String? minSupportedVersion;

  String? currentEmail;
  int _nextId = 1;

  Stream<Object?> get authEvents => _authController.stream;

  String? get currentGroupId =>
      currentEmail == null ? null : accounts[currentEmail]?.groupId;

  Group? get currentGroup =>
      currentGroupId == null ? null : groups[currentGroupId];

  void setCurrentEmail(String? email) {
    currentEmail = email;
    _authController.add(email);
  }

  /// Schiebt ein rohes Auth-Ereignis in den Stream. Die App erkennt
  /// Ereignisse über ihre String-Form (siehe `isPasswordRecovery`), deshalb
  /// genügt hier der Name statt einer echten `AuthState`.
  void emitAuthEvent(Object? event) => _authController.add(event);

  /// Der Zustand direkt nach `verifyOTP` beim Zurücksetzen: Die Sitzung ist
  /// gültig, das neue Passwort aber noch nicht gesetzt.
  ///
  /// Meldet bewusst NUR 'passwordRecovery' und geht nicht über
  /// [setCurrentEmail] — dessen Ereignis passiert den Router-Filter und
  /// öffnete die Konsole mitten im Zurücksetzen. Genau diesen Unterschied
  /// prüft `test/flows/console_reset_flow_test.dart`.
  void beginRecovery(String email) {
    currentEmail = email;
    _authController.add('passwordRecovery');
  }

  FakeCarpoolRepository dataFor(String groupId) =>
      _data.putIfAbsent(groupId, FakeCarpoolRepository.new);

  /// Legt eine Gruppe samt Zugang an und gibt die groupId zurück.
  String addGroup({
    required String handle,
    required String password,
    required String name,
    GroupStatus status = GroupStatus.active,
  }) {
    final id = 'group-${_nextId++}';
    groups[id] = Group(
      id: id,
      name: name,
      handle: handle,
      status: status,
      createdAt: DateTime(2026, 1, _nextId),
    );
    accounts['$handle@grp.fahrgemeinschaft.app'] = FakeAccount(
      password: password,
      groupId: id,
    );
    return id;
  }

  /// Die Anlage aus der Konsole (Edge Function `request-group`): Gruppe
  /// **sofort aktiv** und **sofort verknüpft** — in einem Zug, damit keine
  /// Gruppe ohne Zuordnung entstehen kann.
  ///
  /// Wirft wie der Server, wenn der Handle vergeben ist oder das Konto seinen
  /// Deckel erreicht hat. Den Deckel bildet der Fake bewusst nach: Sonst
  /// prüfte der Test nur, ob die Oberfläche das Formular versteckt — nicht,
  /// ob die Grenze wirklich hält.
  String createGroupForAdmin({
    required String adminEmail,
    required String handle,
    required String password,
    required String groupName,
  }) {
    final admin = adminAccounts[adminEmail];
    if (admin == null) throw Exception('not an admin account');
    if (admin.groupIds.length >= groupCap) {
      throw const GroupLimitReached();
    }
    final email = '$handle@grp.fahrgemeinschaft.app';
    if (accounts.containsKey(email)) throw const HandleTakenException();
    final id = addGroup(handle: handle, password: password, name: groupName);
    admin.groupIds.add(id);
    return id;
  }

  /// Löscht wie die Kaskade der echten Datenbank: Gruppe, Daten und Zugang.
  ///
  /// Das Verwalter-Konto überlebt und verliert nur die Verknüpfung — es trägt
  /// womöglich weitere Gruppen.
  void deleteGroupCompletely(String groupId) {
    groups.remove(groupId);
    _data.remove(groupId);
    accounts.removeWhere((_, account) => account.groupId == groupId);
    for (final admin in adminAccounts.values) {
      admin.groupIds.remove(groupId);
    }
  }

  void dispose() => _authController.close();
}

/// Leitet alle Datenzugriffe an die Gruppe des angemeldeten Zugangs weiter.
class FakeRoutingCarpoolRepository implements CarpoolRepository {
  FakeRoutingCarpoolRepository(this.backend);

  final FakeBackend backend;

  CarpoolRepository get _target {
    final groupId = backend.currentGroupId;
    if (groupId == null) throw StateError('nicht angemeldet');
    return backend.dataFor(groupId);
  }

  @override
  Future<List<Person>> loadPersons() => _target.loadPersons();

  @override
  Future<Person> createPerson(Person person) => _target.createPerson(person);

  @override
  Future<void> updatePerson(Person person) => _target.updatePerson(person);

  @override
  Future<List<Trip>> loadTrips() => _target.loadTrips();

  @override
  Future<Trip> createTrip(
    DateTime date,
    Map<String, ParticipationStatus> participations, {
    String? note,
  }) => _target.createTrip(date, participations, note: note);

  @override
  Future<void> updateTrip(Trip trip) => _target.updateTrip(trip);

  @override
  Future<void> deleteTrip(String tripId) => _target.deleteTrip(tripId);

  @override
  Future<AppSettings> loadSettings() => _target.loadSettings();

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _target.saveSettings(settings);

  @override
  Future<GroupDefaults> loadGroupDefaults() => _target.loadGroupDefaults();

  @override
  Future<void> saveGroupDefaults(GroupDefaults defaults) =>
      _target.saveGroupDefaults(defaults);

  @override
  Future<Map<DateTime, GroupDefaults>> loadPlanDefaults(
    DateTime from, {
    int days = 7,
  }) => _target.loadPlanDefaults(from, days: days);

  @override
  Future<void> savePlanDefaults(DateTime date, GroupDefaults defaults) =>
      _target.savePlanDefaults(date, defaults);

  @override
  Future<Map<DateTime, Map<String, GroupDefaults>>> loadCarDefaults(
    DateTime from, {
    int days = 7,
  }) => _target.loadCarDefaults(from, days: days);

  @override
  Future<void> saveCarDefaults(
    DateTime date,
    String driverId,
    GroupDefaults defaults,
  ) => _target.saveCarDefaults(date, driverId, defaults);

  @override
  Future<WeekPlan> loadPlan(DateTime from, {int days = 7}) =>
      _target.loadPlan(from, days: days);

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) => _target.setAvailability(date, personId, ride);

  @override
  Future<void> setPlanDrivers(DateTime date, Set<String> driverIds) =>
      _target.setPlanDrivers(date, driverIds);

  @override
  Future<Map<DateTime, List<SeatChoice>>> loadSeatChoices(
    DateTime from, {
    int days = 7,
  }) => _target.loadSeatChoices(from, days: days);

  @override
  Future<void> saveSeatChoice(SeatChoice choice) =>
      _target.saveSeatChoice(choice);

  @override
  Future<void> deleteSeatChoice(
    DateTime date,
    String personId,
    String driverId,
  ) => _target.deleteSeatChoice(date, personId, driverId);

  @override
  Future<List<PlanNote>> loadNotes(DateTime from, {int days = 7}) =>
      _target.loadNotes(from, days: days);

  @override
  Future<void> addNote(DateTime date, String personId, String body) =>
      _target.addNote(date, personId, body);

  @override
  Future<void> deleteNote(String noteId) => _target.deleteNote(noteId);
}

class FakeAppConfigRepository implements AppConfigRepository {
  FakeAppConfigRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<String?> minSupportedVersion() async => backend.minSupportedVersion;
}

class FakeFeedbackRepository implements FeedbackRepository {
  FakeFeedbackRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<void> submit(
    FeedbackType type,
    String message, {
    String? appVersion,
    String? platform,
  }) async {
    backend.feedback.add({
      'group_id': backend.currentGroupId,
      'type': type.name,
      'message': message.trim(),
      'app_version': appVersion,
      'platform': platform,
    });
  }
}

/// Push-Registrierung und -Einstellungen, mandantengetrennt wie die echte
/// Tabelle: Die Zuordnung hängt an der Gruppe, die gerade angemeldet ist.
class FakePushRepository implements PushRepository {
  FakePushRepository(this.backend);

  final FakeBackend backend;

  /// Token → (group_id, person_id), wie `push_devices`.
  final Map<String, (String?, String?)> devices = {};

  /// (group_id, person_id) → Einstellungen, wie `notification_prefs`.
  final Map<String, NotificationPrefs> prefs = {};

  /// Was `sendTest` verschickt hätte.
  final List<String> tests = [];

  String _key(String personId) => '${backend.currentGroupId}|$personId';

  @override
  Future<PushState> stateFor(String token) async {
    final device = devices[token];
    if (device == null || device.$1 != backend.currentGroupId) {
      return const PushState();
    }
    final personId = device.$2;
    if (personId == null) return const PushState();
    return PushState(personId: personId, prefs: prefs[_key(personId)]);
  }

  @override
  Future<void> register({
    required String token,
    required String? personId,
    required String platform,
  }) async {
    // Wie register_push_device: Die alte Zeile weicht, egal welcher Gruppe
    // sie gehörte.
    devices[token] = (backend.currentGroupId, personId);
  }

  @override
  Future<void> unregister(String token) async => devices.remove(token);

  @override
  Future<void> savePrefs(NotificationPrefs value) async {
    prefs[_key(value.personId)] = value;
  }

  @override
  Future<void> deletePrefs(String personId) async {
    prefs.remove(_key(personId));
  }

  /// Ob FCM die Testnachricht annimmt. Auf `false` gesetzt spielt der Test
  /// den Fall durch, den der Screen bis 0.39.0 als Erfolg meldete.
  bool testAccepted = true;

  @override
  Future<bool> sendTest(String token) async {
    tests.add(token);
    return testAccepted;
  }
}

/// Bildet `publish_push_outbox` nach: Was vor `keepFrom` liegt, fällt weg —
/// sonst prüfte ein Test eine Zusage („beschränkt auf Personen × Planwoche"),
/// die der Fake gar nicht einhält.
///
/// **Es wird geräumt und ergänzt, nicht ersetzt** (#177). Die echte Funktion
/// löscht `kind='plan'` vor `keepFrom` und schreibt die Einträge dann per
/// `on conflict do update` darüber; eine Zeile ab `keepFrom`, die in den neuen
/// Einträgen nicht vorkommt, **überlebt**. Genau davon lebt der Freitag: Ab
/// Freitagmittag rechnet der Client nur noch die kommende Woche, die Zeilen
/// dieses Freitags stammen vom Vormittag und müssen stehen bleiben, bis seine
/// Rückfahrt-Erinnerung gefallen ist.
///
/// Ein Fake, der stattdessen den Korb ersetzt, verliert sie in **jedem** Fall
/// — mit und ohne Fix. Er wäre grün und bewiese nichts; genau der nachgebaute
/// Pfad, den ein Flow-Test nicht prüfen darf.
class FakePushOutboxRepository implements PushOutboxRepository {
  FakePushOutboxRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<void> publish(
    List<OutboxEntry> entries, {
    required DateTime keepFrom,
  }) async {
    final group = backend.currentGroupId;
    if (group == null) return;
    // Der Purge trifft wie in der Datenbank nur `plan`: Ohne den Filter nähme
    // ein Plan-Schreib jede Fahrt-Meldung (#163) mit, bevor sie rausgeht.
    final kept = [
      for (final entry in backend.outbox[group] ?? const <OutboxEntry>[])
        if (entry.kind != 'plan' || !entry.date.isBefore(keepFrom)) entry,
    ];
    // `on conflict (group_id, person_id, plan_date, kind) do update` — und
    // ohne Filter auf `keepFrom`, genau wie in der Datenbank: Dort läuft der
    // Insert nach dem Delete und kennt die Grenze nicht.
    for (final entry in entries) {
      final at = kept.indexWhere(
        (existing) =>
            existing.personId == entry.personId &&
            existing.date == entry.date &&
            existing.kind == entry.kind,
      );
      if (at < 0) {
        kept.add(entry);
      } else {
        kept[at] = entry;
      }
    }
    backend.outbox[group] = kept;
  }
}

class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<Group?> myGroup() async => backend.currentGroup;
}

/// Preisarchiv, mandantengetrennt wie die echten Tabellen: Bereich und
/// Wochenwerte hängen an der Gruppe, die gerade angemeldet ist.
///
/// Die Rohschicht gibt es hier bewusst nicht — sie ist für den Client
/// unsichtbar, ein Fake dafür prüfte einen Weg, den es nicht gibt.
class FakePriceRepository implements PriceRepository {
  FakePriceRepository(this.backend);

  final FakeBackend backend;

  /// group_id → Bereich, wie `price_area`.
  final Map<String, PriceArea> areas = {};

  /// group_id → Wochenwerte, wie `price_week`. Tests füllen das direkt;
  /// geschrieben wird es in der echten App nur vom Verdichtungslauf.
  final Map<String, List<PricePoint>> weeks = {};

  /// Was die Ortssuche liefern soll.
  List<GeoPlace> places = const [];

  /// Was ein „Jetzt aktualisieren" ergeben soll.
  SampleResult next = const SampleResult(stored: 12, failed: false);

  /// Wie oft abgetastet wurde — damit ein Test den Knopf nachweisen kann.
  int samples = 0;

  @override
  Future<PriceArea?> loadArea() async => areas[backend.currentGroupId];

  @override
  Future<void> saveArea(PriceArea area) async {
    final group = backend.currentGroupId;
    if (group == null) return;
    areas[group] = area;
  }

  @override
  Future<List<PricePoint>> loadWeeks() async =>
      weeks[backend.currentGroupId] ?? const [];

  @override
  Future<List<GeoPlace>> searchPlace(String query) async => places;

  @override
  Future<SampleResult> sampleNow() async {
    samples++;
    return next;
  }
}
