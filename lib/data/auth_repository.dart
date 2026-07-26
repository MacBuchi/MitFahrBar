/// auth_repository.dart – Gruppen-Login (ein Account je Gruppe).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/group_login.dart';

/// Das Verwalter-Konto existiert, hat den Code aus der Registrierungs-Mail
/// aber noch nicht eingegeben — die Anmeldung ist bis dahin gesperrt.
class EmailNotConfirmedException implements Exception {
  const EmailNotConfirmedException();
}

/// Die gewünschte neue E-Mail-Adresse gehört schon einem Konto.
class EmailTakenException implements Exception {
  const EmailTakenException();
}

/// Der Code aus der Mail ist falsch oder abgelaufen.
///
/// Deckt bewusst auch die unbekannte Adresse ab: GoTrue antwortet in beiden
/// Fällen gleich, damit daraus kein Konto-Orakel wird. Die Oberfläche darf
/// die Fälle deshalb ebenfalls nicht unterscheiden.
class InvalidCodeException implements Exception {
  const InvalidCodeException();
}

/// Supabase hat das neue Passwort als unsicher abgelehnt (zu kurz oder aus
/// einem bekannten Leak) — „zu kurz" wäre als Meldung also falsch.
class WeakPasswordException implements Exception {
  const WeakPasswordException();
}

/// Das neue Passwort ist das bisherige.
class SamePasswordException implements Exception {
  const SamePasswordException();
}

/// Meldet GoTrue mit diesem Ereignis eine Recovery-Sitzung?
///
/// Die Prüfung läuft über die String-Form, weil [AuthRepository.onAuthStateChange]
/// bewusst `dynamic` liefert: So kann der Test-Fake rohe Ereignisnamen schieben,
/// ohne eine echte `AuthState` samt Session bauen zu müssen. `AuthState.toString()`
/// trägt `event: passwordRecovery`, die echte Sitzung matcht damit genauso.
/// Diese eine Stelle kennt die Zeichenkette — sonst driften Router und Fake.
bool isPasswordRecovery(Object? event) => '$event'.contains('passwordRecovery');

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

  /// Passwort des aktuell eingeloggten Gruppen-Accounts ändern.
  Future<void> changePassword(String newPassword);

  /// Ist die aktuelle Sitzung ein Verwalter-Konto (Konsole) statt eines
  /// Gruppen-Logins? Entscheidet den Router-Redirect.
  bool get isAdminSession;

  /// Verwalter-Konto registrieren (echte E-Mail). Die `account_type`-Metadata
  /// hält den Signup-Trigger davon ab, eine Geister-Gruppe anzulegen.
  Future<void> signUpAdmin(String email, String password);

  /// Wirft [EmailNotConfirmedException], solange der Code aus der
  /// Registrierungs-Mail nicht eingegeben wurde.
  Future<void> signInAdmin(String email, String password);

  /// Adresse mit dem Code aus der Registrierungs-Mail bestätigen. Die Sitzung
  /// kommt gleich mit — danach führt der Router in die Konsole.
  /// Wirft [InvalidCodeException] bei falschem oder abgelaufenem Code.
  Future<void> confirmAdminEmailWithCode({
    required String email,
    required String code,
  });

  /// Bestätigungs-Mail der Registrierung erneut anstoßen (z. B. Mail weg
  /// oder im Spam) — GoTrue drosselt Wiederholungen selbst.
  Future<void> resendAdminConfirmation(String email);

  /// E-Mail-Adresse des Verwalter-Kontos ändern — Supabase-Standard
  /// „secure email change": Bestätigungs-Links an die alte UND die neue
  /// Adresse, erst danach gilt die neue. Wirft [EmailTakenException],
  /// wenn die Adresse schon ein Konto hat.
  Future<void> changeAdminEmail(String newEmail);

  /// Schickt einen Zahlencode zum Zurücksetzen des Passworts per Mail.
  ///
  /// Wirft nicht, wenn es zu der Adresse kein Konto gibt — Supabase antwortet
  /// absichtlich gleich, damit daraus kein Konto-Orakel wird. Die Oberfläche
  /// muss dieselbe Meldung zeigen.
  Future<void> sendAdminPasswordResetCode(String email);

  /// Löst den Code ein und setzt das neue Passwort — in einem Schritt.
  /// Wirft [InvalidCodeException], [WeakPasswordException] oder
  /// [SamePasswordException].
  Future<void> resetAdminPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  });

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
  Future<void> confirmAdminEmailWithCode({
    required String email,
    required String code,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.signup,
      );
    } on AuthException catch (e) {
      throw _mapCodeError(e);
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
        emailRedirectTo: 'https://macbuchi.github.io/MitFahrBar/',
      );
    } on AuthApiException catch (e) {
      if (e.code == 'email_exists') throw const EmailTakenException();
      rethrow;
    }
  }

  @override
  Future<void> sendAdminPasswordResetCode(String email) =>
      // Bewusst der Code aus der Mail und NICHT der enthaltene Link: Im
      // PKCE-Standardflow legt gotrue beim Anfordern einen „code verifier"
      // im Speicher des *anfragenden* Geräts ab (`gotrue_client.dart`:
      // `_generatePKCECodeChallenge`) und verlangt ihn beim Einlösen wieder.
      // Wer in der App anfordert und die Mail dann im Handy-Browser öffnet,
      // hat ihn dort nicht — der Link stirbt still mit „Code verifier could
      // not be found in local storage.". Der Code ist gerätefrei, braucht
      // weder redirectTo noch einen uri_allow_list-Eintrag und bleibt in
      // derselben Maske. Die Mail-Vorlage im Dashboard führt deshalb
      // `{{ .Token }}` und KEINEN Link (Kopie in supabase/templates/,
      // Begründung in CLAUDE.md) — sonst existiert der kaputte Weg weiter.
      _client.auth.resetPasswordForEmail(email);

  @override
  Future<void> resetAdminPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    // `verifyOTP` legt eine Recovery-Sitzung an, erst `updateUser` macht das
    // neue Passwort gültig. Beides gehört in EINEN Aufruf: bliebe es
    // dazwischen stehen, wäre jemand angemeldet, ohne sein Passwort zu
    // kennen. Deshalb lässt der Router eine Recovery-Sitzung allein nicht
    // durch (siehe `isPasswordRecovery` und `core/router.dart`) — erst das
    // geänderte Passwort öffnet die Konsole.
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw _mapCodeError(e);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  /// GoTrue-Fehler beim Einlösen eines Codes auf die typisierten Ausnahmen
  /// abbilden. Alles Unbekannte fliegt weiter — die Oberfläche meldet es dann
  /// als allgemeinen Fehlschlag, statt eine falsche Ursache zu behaupten.
  Object _mapCodeError(AuthException e) => switch (e.code) {
    'otp_expired' || 'otp_disabled' => const InvalidCodeException(),
    'weak_password' => const WeakPasswordException(),
    'same_password' => const SamePasswordException(),
    // Falscher Code und unbekannte Adresse landen beide hier: GoTrue
    // antwortet auf beides mit 403, damit die Antwort kein Konto-Orakel wird.
    _ when e.statusCode == '403' => const InvalidCodeException(),
    _ => e,
  };
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
  Future<void> changePassword(String newPassword) async {}

  @override
  bool get isAdminSession => false;

  @override
  Future<void> signUpAdmin(String email, String password) async {}

  @override
  Future<void> signInAdmin(String email, String password) async {}

  @override
  Future<void> confirmAdminEmailWithCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<void> resendAdminConfirmation(String email) async {}

  @override
  Future<void> changeAdminEmail(String newEmail) async {}

  @override
  Future<void> sendAdminPasswordResetCode(String email) async {}

  @override
  Future<void> resetAdminPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> signOut() async {}
}
