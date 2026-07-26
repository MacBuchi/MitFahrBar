/// fake_auth_repository.dart – Auth-Fake mit steuerbarem Zustand.
///
/// Bildet das Verhalten von Supabase-Auth nach, inklusive Login/Logout als
/// Stream-Ereignis, damit der Router-Redirect im Test genauso reagiert wie
/// in Produktion.
library;

import 'dart:async';

import 'package:mitfahrbar/core/group_login.dart';
import 'package:mitfahrbar/data/auth_repository.dart';

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
    if (backend.signupThrottled) {
      throw const TooManyRequestsException();
    }
    final email = handleToEmail(handle);
    if (backend.accounts.containsKey(email)) {
      throw const HandleTakenException();
    }
    // Wie die Edge Function in Produktion: legt nur an, meldet nicht an.
    backend.createPendingAccount(
      email: email,
      password: password,
      groupName: groupName,
      handle: normalizeHandle(handle),
    );
  }

  @override
  Future<void> changePassword(String newPassword) async {
    final email = backend.currentEmail;
    if (email == null) throw Exception('not signed in');
    // Gilt für beide Kontoarten — wie updateUser in Supabase.
    final admin = backend.adminAccounts[email];
    if (admin != null) {
      admin.password = newPassword;
    } else {
      backend.accounts[email]!.password = newPassword;
    }
  }

  @override
  bool get isAdminSession =>
      backend.adminAccounts.containsKey(backend.currentEmail);

  @override
  Future<void> signUpAdmin(String email, String password) async {
    if (backend.adminAccounts.containsKey(email)) {
      throw Exception('already registered');
    }
    // Wie in Produktion: Registrieren meldet nicht an, und bis der Code aus
    // der Mail eingegeben ist, bleibt das Konto gesperrt.
    backend.adminAccounts[email] = FakeAdminAccount(
      password: password,
      confirmed: false,
    );
  }

  @override
  Future<void> signInAdmin(String email, String password) async {
    final account = backend.adminAccounts[email];
    if (account == null || account.password != password) {
      throw Exception('invalid credentials');
    }
    if (!account.confirmed) {
      throw const EmailNotConfirmedException();
    }
    backend.setCurrentEmail(email);
  }

  @override
  Future<void> confirmAdminEmailWithCode({
    required String email,
    required String code,
  }) async {
    final account = backend.adminAccounts[email];
    if (account == null || code != FakeBackend.confirmCode) {
      throw const InvalidCodeException();
    }
    account.confirmed = true;
    // Wie verifyOTP: Die Sitzung kommt gleich mit.
    backend.setCurrentEmail(email);
  }

  @override
  Future<void> resendAdminConfirmation(String email) async {
    backend.confirmationResends.add(email);
  }

  @override
  Future<void> changeAdminEmail(String newEmail) async {
    if (backend.adminAccounts.containsKey(newEmail)) {
      throw const EmailTakenException();
    }
    backend.emailChangeRequests.add(newEmail);
  }

  /// Nimmt jede Adresse an — auch unbekannte. Genau so verhält sich Supabase,
  /// damit die Antwort kein Konto-Orakel wird.
  @override
  Future<void> sendAdminPasswordResetCode(String email) async {
    backend.passwordResets.add(email);
  }

  /// Spiegelt die echte Reihenfolge: `verifyOTP` meldet die Sitzung mit
  /// 'passwordRecovery' an, erst `updateUser` setzt das Passwort und meldet
  /// die fertige Anmeldung. Der Router hängt an genau diesem Unterschied —
  /// beides hier zu verschmelzen führte den Test am Kernpunkt vorbei.
  @override
  Future<void> resetAdminPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final account = backend.adminAccounts[email];
    if (account == null || code != FakeBackend.resetCode) {
      // Wie GoTrue: derselbe Fehler für falschen Code und unbekannte
      // Adresse — sonst wäre auch das ein Konto-Orakel.
      throw const InvalidCodeException();
    }
    backend.beginRecovery(email);
    account.password = newPassword;
    backend.setCurrentEmail(email);
  }

  @override
  Future<void> signOut() async => backend.setCurrentEmail(null);
}
