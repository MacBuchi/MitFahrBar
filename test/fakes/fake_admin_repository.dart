/// fake_admin_repository.dart – Verwalter-Konsole gegen das In-Memory-Backend.
///
/// Bildet die SECURITY-DEFINER-Funktionen nach, inklusive der getypten
/// Fehler — die Flow-Tests sollen dieselben Wege gehen wie die echte App.
/// Dazu gehört die Eigentumsprüfung: Eine fremde `groupId` wird abgewiesen,
/// genau wie der Server es tut.
library;

import 'package:mitfahrbar/core/group_login.dart';
import 'package:mitfahrbar/data/admin_repository.dart';
import 'package:mitfahrbar/models/group.dart';

import 'fake_backend.dart';

class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository(this.backend);

  final FakeBackend backend;

  FakeAdminAccount _currentAdmin() {
    final admin = backend.adminAccounts[backend.currentEmail];
    if (admin == null) throw Exception('not an admin account');
    return admin;
  }

  /// Die eigene Gruppe oder ein Fehler — das Gegenstück zur Prüfung
  /// `user_id = auth.uid() and group_id = target_group` im Server.
  Group _ownGroup(String groupId) {
    final admin = _currentAdmin();
    final group = backend.groups[groupId];
    if (!admin.groupIds.contains(groupId) || group == null) {
      throw Exception('not linked');
    }
    return group;
  }

  @override
  Future<void> createGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {
    _currentAdmin();
    backend.createGroupForAdmin(
      adminEmail: backend.currentEmail!,
      handle: normalizeHandle(handle),
      password: password,
      groupName: groupName,
    );
  }

  @override
  Future<void> claimGroup(String handle, String groupPassword) async {
    final admin = _currentAdmin();
    final account = backend.accounts[resolveLoginEmail(handle)];
    final groupId = account?.groupId;
    final group = groupId == null ? null : backend.groups[groupId];
    if (account == null ||
        account.password != groupPassword ||
        group == null ||
        group.status != GroupStatus.active) {
      throw WrongGroupCredentials();
    }
    final taken = backend.adminAccounts.values.any(
      (a) => a.groupIds.contains(groupId),
    );
    if (taken) throw GroupAlreadyClaimed();
    // Der Deckel gilt für jeden Weg — auch für das Übernehmen.
    if (admin.groupIds.length >= groupCap) throw const GroupLimitReached();
    admin.groupIds.add(groupId!);
  }

  @override
  Future<List<AdminGroup>> myAdminGroups() async {
    final admin = backend.adminAccounts[backend.currentEmail];
    if (admin == null) return const [];
    return [
      for (final id in admin.groupIds)
        if (backend.groups[id] case final group?)
          AdminGroup(id: id, handle: group.handle, name: group.name),
    ];
  }

  @override
  Future<void> resetGroupPassword({
    required String groupId,
    required String newPassword,
  }) async {
    _ownGroup(groupId);
    if (newPassword.length < 8) throw Exception('password too short');
    backend.accounts.values
            .firstWhere((account) => account.groupId == groupId)
            .password =
        newPassword;
  }

  @override
  Future<void> releaseGroup({
    required String groupId,
    required String adminPassword,
  }) async {
    final admin = _currentAdmin();
    _ownGroup(groupId);
    if (admin.password != adminPassword) throw WrongAdminPassword();
    admin.groupIds.remove(groupId);
  }

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String adminPassword,
    required String handleConfirmation,
  }) async {
    final admin = _currentAdmin();
    final group = _ownGroup(groupId);
    if (admin.password != adminPassword) throw WrongAdminPassword();
    if (handleConfirmation != group.handle) throw HandleMismatch();
    backend.deleteGroupCompletely(groupId);
  }
}
