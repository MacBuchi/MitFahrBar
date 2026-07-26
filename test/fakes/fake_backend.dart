/// fake_backend.dart – In-Memory-Backend für Tests.
///
/// Bildet die Mandantentrennung der echten Datenbank nach: Daten hängen an
/// einer Gruppe, und man sieht ausschließlich die Daten der Gruppe, mit der
/// man angemeldet ist. So laufen Flow-Tests durch die echte App, ohne dass
/// eine Lücke im Fake echte RLS-Fehler verstecken kann.
library;

import 'dart:async';

import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/data/app_config_repository.dart';
import 'package:mitfahrbar/data/carpool_repository.dart';
import 'package:mitfahrbar/data/fake_repository.dart';
import 'package:mitfahrbar/data/feedback_repository.dart';
import 'package:mitfahrbar/data/group_repository.dart';
import 'package:mitfahrbar/data/push_repository.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';

class FakeAccount {
  FakeAccount({required this.password, required this.groupId});

  String password;
  final String groupId;
}

/// Verwalter-Konto (Konsole): echte E-Mail, eigenes Passwort, optional mit
/// einer Gruppe verknüpft. `confirmed` bildet die Bestätigungspflicht ab:
/// Frisch registrierte Konten sind unbestätigt und können sich nicht
/// anmelden, bis der Code aus der Mail (im Fake: das Flag) eingelöst ist.
class FakeAdminAccount {
  FakeAdminAccount({required this.password, this.confirmed = true});

  String password;
  bool confirmed;
  String? groupId;
}

class FakeBackend {
  final Map<String, FakeAccount> accounts = {};
  final Map<String, FakeAdminAccount> adminAccounts = {};

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

  /// Simuliert die gedrosselte Gruppen-Anlage (Missbrauchsschutz, #69):
  /// Die Edge Function antwortet dann mit 429.
  bool signupThrottled = false;
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
    bool isAdmin = false,
  }) {
    final id = 'group-${_nextId++}';
    groups[id] = Group(
      id: id,
      name: name,
      handle: handle,
      status: status,
      isAdmin: isAdmin,
      createdAt: DateTime(2026, 1, _nextId),
    );
    accounts['$handle@grp.fahrgemeinschaft.app'] = FakeAccount(
      password: password,
      groupId: id,
    );
    return id;
  }

  void createPendingAccount({
    required String email,
    required String password,
    required String groupName,
    required String handle,
  }) {
    final id = 'group-${_nextId++}';
    groups[id] = Group(
      id: id,
      name: groupName,
      handle: handle,
      status: GroupStatus.pending,
      isAdmin: false,
      createdAt: DateTime(2026, 1, _nextId),
    );
    accounts[email] = FakeAccount(password: password, groupId: id);
  }

  /// Löscht wie die Kaskade der echten Datenbank: Gruppe, Daten, Zugang
  /// und die Verwalter-Verknüpfung in einem Schlag.
  void deleteGroupCompletely(String groupId) {
    groups.remove(groupId);
    _data.remove(groupId);
    accounts.removeWhere((_, account) => account.groupId == groupId);
    adminAccounts.removeWhere((_, admin) => admin.groupId == groupId);
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

  @override
  Future<void> sendTest(String token) async => tests.add(token);
}

class FakeGroupRepository implements GroupRepository {
  FakeGroupRepository(this.backend);

  final FakeBackend backend;

  @override
  Future<Group?> myGroup() async => backend.currentGroup;

  @override
  Future<List<Group>> pendingGroups() async {
    // Nur Admins bekommen die Liste – wie die RLS-Policy in der Datenbank.
    if (!(backend.currentGroup?.isAdmin ?? false)) return const [];
    return backend.groups.values
        .where((g) => g.status == GroupStatus.pending)
        .toList();
  }

  @override
  Future<void> setStatus(String groupId, GroupStatus status) async {
    final g = backend.groups[groupId];
    if (g == null) return;
    backend.groups[groupId] = Group(
      id: g.id,
      name: g.name,
      handle: g.handle,
      status: status,
      isAdmin: g.isAdmin,
      createdAt: g.createdAt,
    );
  }
}
