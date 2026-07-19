/// auth_repository.dart – Gruppen-Login (ein Account je Gruppe).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/group_login.dart';

abstract class AuthRepository {
  bool get loggedIn;
  Stream<dynamic> get onAuthStateChange;
  Future<void> signIn(String handle, String password);

  /// Neue Gruppe anfragen: legt den Login an; die zugehörige Gruppe entsteht
  /// per DB-Trigger im Status 'pending' und muss freigegeben werden.
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  });

  /// Passwort des aktuell eingeloggten Gruppen-Accounts ändern.
  Future<void> changePassword(String newPassword);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get loggedIn => _client.auth.currentSession != null;

  @override
  Stream<dynamic> get onAuthStateChange => _client.auth.onAuthStateChange;

  @override
  Future<void> signIn(String handle, String password) =>
      _client.auth.signInWithPassword(
        email: resolveLoginEmail(handle),
        password: password,
      );

  @override
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  }) =>
      _client.auth.signUp(
        email: handleToEmail(handle),
        password: password,
        data: {'group_name': groupName},
      );

  @override
  Future<void> changePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  @override
  Future<void> signOut() => _client.auth.signOut();
}

/// Demo-Modus ohne Supabase: immer eingeloggt.
class AlwaysLoggedInAuthRepository implements AuthRepository {
  @override
  bool get loggedIn => true;

  @override
  Stream<dynamic> get onAuthStateChange => const Stream.empty();

  @override
  Future<void> signIn(String handle, String password) async {}

  @override
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {}

  @override
  Future<void> changePassword(String newPassword) async {}

  @override
  Future<void> signOut() async {}
}
