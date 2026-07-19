/// auth_repository.dart – Gruppenlogin (ein gemeinsamer Account).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AuthRepository {
  bool get loggedIn;
  Stream<dynamic> get onAuthStateChange;
  Future<void> signIn(String email, String password);
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
  Future<void> signIn(String email, String password) =>
      _client.auth.signInWithPassword(email: email, password: password);

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
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}
}
