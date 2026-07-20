/// fake_auth_repository.dart – Auth-Fake mit steuerbarem Zustand.
///
/// Bildet das Verhalten von Supabase-Auth nach, inklusive Login/Logout als
/// Stream-Ereignis, damit der Router-Redirect im Test genauso reagiert wie
/// in Produktion.
library;

import 'dart:async';

import 'package:fahrgemeinschaft/core/group_login.dart';
import 'package:fahrgemeinschaft/data/auth_repository.dart';

import 'fake_backend.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.backend);

  final FakeBackend backend;

  @override
  bool get loggedIn => backend.currentEmail != null;

  @override
  String? get currentUserId => backend.currentEmail;

  @override
  Stream<dynamic> get onAuthStateChange => backend.authEvents;

  @override
  Future<void> signIn(String handle, String password) async {
    final email = resolveLoginEmail(handle);
    final account = backend.accounts[email];
    if (account == null || account.password != password) {
      throw Exception('invalid credentials');
    }
    backend.setCurrentEmail(email);
  }

  @override
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {
    final email = handleToEmail(handle);
    if (backend.accounts.containsKey(email)) {
      throw Exception('handle already taken');
    }
    backend.createPendingAccount(
      email: email,
      password: password,
      groupName: groupName,
      handle: normalizeHandle(handle),
    );
    backend.setCurrentEmail(email);
  }

  @override
  Future<void> changePassword(String newPassword) async {
    final email = backend.currentEmail;
    if (email == null) throw Exception('not signed in');
    backend.accounts[email]!.password = newPassword;
  }

  @override
  Future<void> signOut() async => backend.setCurrentEmail(null);
}
