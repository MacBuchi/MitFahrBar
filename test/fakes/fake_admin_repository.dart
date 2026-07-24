/// fake_admin_repository.dart – Verwalter-Konsole gegen das In-Memory-Backend.
///
/// Bildet die SECURITY-DEFINER-Funktionen nach, inklusive der getypten
/// Fehler — die Flow-Tests sollen dieselben Wege gehen wie die echte App.
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
    final taken = backend.adminAccounts.values.any((a) => a.groupId == groupId);
    if (taken || admin.groupId != null) throw GroupAlreadyClaimed();
    admin.groupId = groupId;
  }

  @override
  Future<AdminGroup?> myAdminGroup() async {
    final admin = backend.adminAccounts[backend.currentEmail];
    final group = admin?.groupId == null
        ? null
        : backend.groups[admin!.groupId];
    return group == null
        ? null
        : AdminGroup(handle: group.handle, name: group.name);
  }

  @override
  Future<void> resetGroupPassword(String newPassword) async {
    final admin = _currentAdmin();
    final groupId = admin.groupId;
    if (groupId == null) throw Exception('not linked');
    if (newPassword.length < 8) throw Exception('password too short');
    backend.accounts.values
            .firstWhere((account) => account.groupId == groupId)
            .password =
        newPassword;
  }

  @override
  Future<void> releaseGroup(String adminPassword) async {
    final admin = _currentAdmin();
    if (admin.groupId == null) throw Exception('not linked');
    if (admin.password != adminPassword) throw WrongAdminPassword();
    admin.groupId = null;
  }

  @override
  Future<void> deleteGroup({
    required String adminPassword,
    required String handleConfirmation,
  }) async {
    final admin = _currentAdmin();
    final groupId = admin.groupId;
    final group = groupId == null ? null : backend.groups[groupId];
    if (group == null) throw Exception('not linked');
    if (admin.password != adminPassword) throw WrongAdminPassword();
    if (handleConfirmation != group.handle) throw HandleMismatch();
    backend.deleteGroupCompletely(groupId!);
  }
}
