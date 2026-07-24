/// fake_backend.dart – In-Memory-Backend für Tests.
///
/// Bildet die Mandantentrennung der echten Datenbank nach: Daten hängen an
/// einer Gruppe, und man sieht ausschließlich die Daten der Gruppe, mit der
/// man angemeldet ist. So laufen Flow-Tests durch die echte App, ohne dass
/// eine Lücke im Fake echte RLS-Fehler verstecken kann.
library;

import 'dart:async';

import 'package:fahrgemeinschaft/core/update_check.dart';
import 'package:fahrgemeinschaft/data/app_config_repository.dart';
import 'package:fahrgemeinschaft/data/carpool_repository.dart';
import 'package:fahrgemeinschaft/data/fake_repository.dart';
import 'package:fahrgemeinschaft/data/feedback_repository.dart';
import 'package:fahrgemeinschaft/data/group_repository.dart';
import 'package:fahrgemeinschaft/models/app_settings.dart';
import 'package:fahrgemeinschaft/models/group.dart';
import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/plan_ride.dart';
import 'package:fahrgemeinschaft/models/trip.dart';

class FakeAccount {
  FakeAccount({required this.password, required this.groupId});

  String password;
  final String groupId;
}

/// Verwalter-Konto (Konsole): echte E-Mail, eigenes Passwort, optional mit
/// einer Gruppe verknüpft. `confirmed` bildet die Bestätigungspflicht ab:
/// Frisch registrierte Konten sind unbestätigt und können sich nicht
/// anmelden, bis der Mail-Link (im Fake: das Flag) eingelöst ist.
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
  /// Entsprechung der Mail, die in Produktion rausgeht.
  final List<String> passwordResets = [];

  /// Adressen, für die die Bestätigungs-Mail erneut angefordert wurde.
  final List<String> confirmationResends = [];

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

  /// Schiebt ein rohes Auth-Ereignis in den Stream — z. B.
  /// 'passwordRecovery', wie es Supabase nach einem Reset-Link meldet.
  /// Die Konsole erkennt das Ereignis über seine String-Form.
  void emitAuthEvent(Object? event) => _authController.add(event);

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
  Future<void> setPlanDriver(DateTime date, String? driverId) =>
      _target.setPlanDriver(date, driverId);
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
