/// auth_repository.dart – Gruppen-Login (ein Account je Gruppe).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/group_login.dart';

/// Der gewünschte Anmeldename ist schon vergeben.
class HandleTakenException implements Exception {
  const HandleTakenException();
}

/// Das Verwalter-Konto existiert, hat den Bestätigungs-Link aber noch nicht
/// angetippt — die Anmeldung ist bis dahin gesperrt.
class EmailNotConfirmedException implements Exception {
  const EmailNotConfirmedException();
}

/// Die gewünschte neue E-Mail-Adresse gehört schon einem Konto.
class EmailTakenException implements Exception {
  const EmailTakenException();
}

/// Der Server drosselt gerade neue Gruppen-Anfragen (Missbrauchsschutz).
class TooManyRequestsException implements Exception {
  const TooManyRequestsException();
}

abstract class AuthRepository {
  bool get loggedIn;

  /// Stabile Kennung des angemeldeten Zugangs (null = abgemeldet).
  ///
  /// Daten-Provider hängen an diesem Wert statt am Auth-Event-Stream: Er
  /// ändert sich nur bei echtem An-/Abmelden, nicht bei jedem Ereignis
  /// (z. B. Token-Refresh). Sonst werden Provider mitten im Build-Vorgang
  /// invalidiert, was zu „setState during build" führt.
  String? get currentUserId;

  Stream<dynamic> get onAuthStateChange;
  Future<void> signIn(String handle, String password);

  /// Neue Gruppe anfragen: legt den Login an; die zugehörige Gruppe entsteht
  /// per DB-Trigger im Status 'pending' und muss freigegeben werden.
  /// Meldet NICHT an — die Anfrage bleibt eine Anfrage.
  /// Wirft [HandleTakenException], wenn der Anmeldename vergeben ist.
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  });

  /// Passwort des aktuell eingeloggten Gruppen-Accounts ändern.
  Future<void> changePassword(String newPassword);

  /// Ist die aktuelle Sitzung ein Verwalter-Konto (Konsole) statt eines
  /// Gruppen-Logins? Entscheidet den Router-Redirect.
  bool get isAdminSession;

  /// Verwalter-Konto registrieren (echte E-Mail). Die `account_type`-Metadata
  /// hält den Signup-Trigger davon ab, eine Geister-Gruppe anzulegen.
  Future<void> signUpAdmin(String email, String password);

  /// Wirft [EmailNotConfirmedException], solange der Bestätigungs-Link aus
  /// der Registrierungs-Mail nicht eingelöst ist.
  Future<void> signInAdmin(String email, String password);

  /// Bestätigungs-Mail der Registrierung erneut anstoßen (z. B. Mail weg
  /// oder im Spam) — GoTrue drosselt Wiederholungen selbst.
  Future<void> resendAdminConfirmation(String email);

  /// E-Mail-Adresse des Verwalter-Kontos ändern — Supabase-Standard
  /// „secure email change": Bestätigungs-Links an die alte UND die neue
  /// Adresse, erst danach gilt die neue. Wirft [EmailTakenException],
  /// wenn die Adresse schon ein Konto hat.
  Future<void> changeAdminEmail(String newEmail);

  /// Passwort-vergessen-Mail für ein Verwalter-Konto — Supabase-Standard,
  /// der Betreiber ist nicht beteiligt.
  Future<void> sendAdminPasswordReset(String email);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  bool get loggedIn => _client.auth.currentSession != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<dynamic> get onAuthStateChange => _client.auth.onAuthStateChange;

  @override
  Future<void> signIn(String handle, String password) => _client.auth
      .signInWithPassword(email: resolveLoginEmail(handle), password: password);

  @override
  Future<void> requestGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {
    // Serverseitig statt auth.signUp: Seit Verwalter-Konten ihre E-Mail
    // bestätigen müssen (mailer_autoconfirm aus), würde ein Client-Signup
    // eine Bestätigungsmail an die unzustellbare Gruppen-Fake-Adresse
    // schicken — und das Konto bliebe für immer gesperrt. Die Edge Function
    // legt es per Admin-API als bestätigt an, ganz ohne Mail.
    try {
      await _client.functions.invoke(
        'request-group',
        body: {
          'handle': normalizeHandle(handle),
          'password': password,
          'groupName': groupName,
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 409) throw const HandleTakenException();
      if (e.status == 429) throw const TooManyRequestsException();
      rethrow;
    }
  }

  @override
  Future<void> changePassword(String newPassword) =>
      _client.auth.updateUser(UserAttributes(password: newPassword));

  @override
  bool get isAdminSession =>
      _client.auth.currentUser?.userMetadata?['account_type'] == 'admin';

  @override
  Future<void> signUpAdmin(String email, String password) =>
      _client.auth.signUp(
        email: email,
        password: password,
        data: {'account_type': 'admin'},
      );

  @override
  Future<void> signInAdmin(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthApiException catch (e) {
      if (e.code == 'email_not_confirmed') {
        throw const EmailNotConfirmedException();
      }
      rethrow;
    }
  }

  @override
  Future<void> resendAdminConfirmation(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email);

  @override
  Future<void> changeAdminEmail(String newEmail) async {
    try {
      await _client.auth.updateUser(
        UserAttributes(email: newEmail),
        emailRedirectTo: 'https://macbuchi.github.io/Fahrgemeinschaft/',
      );
    } on AuthApiException catch (e) {
      if (e.code == 'email_exists') throw const EmailTakenException();
      rethrow;
    }
  }

  @override
  Future<void> sendAdminPasswordReset(String email) =>
      // Der Link führt auf die Web-App (Groß-F!); dort fängt der
      // passwordRecovery-Auth-Event den Nutzer mit dem Neu-Setzen-Dialog ab.
      _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://macbuchi.github.io/Fahrgemeinschaft/',
      );

  @override
  Future<void> signOut() => _client.auth.signOut();
}

/// Demo-Modus ohne Supabase: immer eingeloggt.
class AlwaysLoggedInAuthRepository implements AuthRepository {
  @override
  bool get loggedIn => true;

  @override
  String? get currentUserId => 'demo';

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
  bool get isAdminSession => false;

  @override
  Future<void> signUpAdmin(String email, String password) async {}

  @override
  Future<void> signInAdmin(String email, String password) async {}

  @override
  Future<void> resendAdminConfirmation(String email) async {}

  @override
  Future<void> changeAdminEmail(String newEmail) async {}

  @override
  Future<void> sendAdminPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {}
}
