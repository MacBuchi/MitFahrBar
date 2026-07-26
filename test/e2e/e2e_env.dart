/// e2e_env.dart – Umgebung & Helfer für die E2E-Tests gegen einen ECHTEN
/// Supabase-Stack (echtes Postgres, echte RLS, echte Auth-Mails via Mailpit).
///
/// Gestartet wird über `tool/e2e.sh` (lokaler CLI-Stack, Docker) oder mit
/// gesetzten E2E_*-Variablen gegen einen entfernten Stack, z. B. die
/// Proxmox-VM (doc/testbackend.md). Fehlen die Variablen, überspringen sich
/// alle E2E-Tests selbst — `flutter test` bleibt ohne Docker/Stack grün,
/// dasselbe Muster wie der Excel-Backtest in fairness_test.dart.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

final String? e2eUrl = Platform.environment['E2E_SUPABASE_URL'];
final String e2eAnonKey = Platform.environment['E2E_SUPABASE_ANON_KEY'] ?? '';
final String e2eServiceKey =
    Platform.environment['E2E_SUPABASE_SERVICE_KEY'] ?? '';
final String e2eMailpitUrl = Platform.environment['E2E_MAILPIT_URL'] ?? '';

bool get e2eConfigured =>
    e2eUrl != null && e2eAnonKey.isNotEmpty && e2eServiceKey.isNotEmpty;

const String e2eSkipReason =
    'E2E-Umgebung nicht gesetzt — Start über '
    'tool/e2e.sh (siehe doc/testbackend.md)';

/// Muss zur festen Login-Domain in core/group_login.dart passen.
const String e2eGroupDomain = 'grp.fahrgemeinschaft.app';

/// Eindeutiger Lauf-Stempel: Testdateien laufen parallel und Läufe gegen
/// eine VM räumen nicht auf — Namen dürfen sich deshalb nie wiederholen.
///
/// Die Zufallshälfte ist Pflicht, nicht Zierde: Jede Testdatei läuft in
/// einem **eigenen Isolate** mit eigenem `_runTag` und eigenem `_seq` ab 0.
/// Starten zwei Dateien in derselben Millisekunde, erzeugen beide
/// `e2eadmin<stempel>x0` — und der zweite Signup prallt mit „User already
/// registered" ab. Genau so fiel am 24.07.2026 in CI der Recovery-Test um,
/// während dieselbe Datei einen Lauf vorher grün war. `Random()` ohne Seed
/// zieht je Isolate aus der Systementropie und trennt die beiden sicher.
final String _runTag =
    DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
    Random().nextInt(1 << 32).toRadixString(36);
int _seq = 0;

String uniqueName(String label) => 'e2e$label$_runTag${'x'}${_seq++}';

final List<SupabaseClient> _clients = [];

/// Implicit statt PKCE: Der PKCE-Flow verlangt einen persistenten Storage,
/// den es in einem Test-Prozess nicht gibt (asyncStorage-Assertion).
const _authOptions = AuthClientOptions(authFlowType: AuthFlowType.implicit);

SupabaseClient newAnonClient() {
  final client = SupabaseClient(e2eUrl!, e2eAnonKey, authOptions: _authOptions);
  _clients.add(client);
  return client;
}

/// Service-Role-Client: umgeht RLS. Nur für Arrange/Assert der Tests —
/// niemals, um App-Verhalten „nachzustellen".
SupabaseClient newServiceClient() {
  final client = SupabaseClient(
    e2eUrl!,
    e2eServiceKey,
    authOptions: _authOptions,
  );
  _clients.add(client);
  return client;
}

/// Schließt alle erzeugten Clients (stoppt insbesondere die
/// Token-Refresh-Timer, die den Test-Runner sonst am Leben halten).
Future<void> disposeClients() async {
  for (final client in _clients) {
    await client.dispose();
  }
  _clients.clear();
}

class GroupAccount {
  GroupAccount({
    required this.handle,
    required this.email,
    required this.password,
    required this.id,
    required this.client,
    required this.owner,
  });

  final String handle;
  final String email;
  final String password;
  final String id;
  final SupabaseClient client;

  /// Das Verwalter-Konto, das diese Gruppe angelegt hat und sie verwaltet.
  final AdminAccount owner;
}

/// Das Verwalter-Konto, über das die Tests ihre Gruppen anlegen.
///
/// Wird wiederverwendet, bis es seinen Deckel erreicht hat — danach entsteht
/// ein neues. Ohne die Rotation liefe jede Suite mit mehr als fünf Gruppen in
/// „group limit reached", und jedes neue Konto kostet einen Mail-Rundlauf.
AdminAccount? _creator;
int _creatorGroups = 0;

/// Muss zum Deckel im Trigger `group_admins_cap` passen.
const int e2eGroupCap = 5;

Future<AdminAccount> groupCreator() async {
  if (_creator == null || _creatorGroups >= e2eGroupCap) {
    _creator = await registerAdmin();
    _creatorGroups = 0;
  }
  return _creator!;
}

/// Registriert eine neue Gruppe wie die App: über die Edge Function
/// `request-group`, **authentifiziert als Verwalter-Konto** (seit #106). Die
/// Gruppe ist danach aktiv und mit diesem Konto verknüpft — es gibt keine
/// Freigabe mehr und keine Gruppe ohne Zuordnung.
Future<GroupAccount> registerGroup(String label) async {
  final creator = await groupCreator();
  final handle = uniqueName(label);
  final email = '$handle@$e2eGroupDomain';
  const password = 'gruppen-passwort-1';
  await creator.client.functions.invoke(
    'request-group',
    body: {'handle': handle, 'password': password, 'groupName': 'E2E $label'},
  );
  _creatorGroups++;
  final client = newAnonClient();
  final res = await client.auth.signInWithPassword(
    email: email,
    password: password,
  );
  return GroupAccount(
    handle: handle,
    email: email,
    password: password,
    id: res.user!.id,
    client: client,
    owner: creator,
  );
}

/// Nimmt der Gruppe ihren Verwalter, ohne sie anzufassen.
///
/// Der Zustand, den `admin_release_group` erzeugt — und der einzige Weg, für
/// einen Test eine übernehmbare Gruppe herzustellen: Seit #106 entsteht keine
/// Gruppe mehr unverknüpft.
Future<void> unlinkGroup(SupabaseClient service, String groupId) async {
  await service.from('group_admins').delete().eq('group_id', groupId);
}

/// Setzt eine Gruppe zurück auf 'pending'.
///
/// Seit #106 entsteht keine pending-Gruppe mehr über die App; den Zustand gibt
/// es nur noch für Fremd-Signups gegen die Gruppen-Domain. Die Tests, die
/// beweisen, dass eine pending-Gruppe **nichts** darf (RLS, Push,
/// Verknüpfung), brauchen ihn trotzdem.
Future<void> makePending(SupabaseClient service, String groupId) async {
  await service.from('groups').update({'status': 'pending'}).eq('id', groupId);
}

class AdminAccount {
  AdminAccount({
    required this.email,
    required this.password,
    required this.id,
    required this.client,
  });

  final String email;
  final String password;
  final String id;
  final SupabaseClient client;
}

/// Registriert ein Verwalter-Konto wie die Konsole: echte E-Mail plus
/// `account_type: 'admin'` in den Metadata — und löst wie in Production den
/// **Code** aus der Bestätigungs-Mail ein, bevor es sich anmeldet.
///
/// Der Code statt des Links ist die Prod-Wahrheit seit Issue #102: Der Link
/// wäre an das anfordernde Gerät gebunden (PKCE-Verifier). Die Vorlagen unter
/// supabase/templates/ führen deshalb nur `{{ .Token }}` — [firstCode] wacht
/// darüber, dass das auch so bleibt.
Future<AdminAccount> registerAdmin({
  String password = 'admin-passwort-1',
}) async {
  final email = '${uniqueName('admin')}@e2e-postfach.test';
  final client = newAnonClient();
  await client.auth.signUp(
    email: email,
    password: password,
    data: {'account_type': 'admin'},
  );
  await client.auth.verifyOTP(
    email: email,
    token: firstCode(await waitForMail(email, subject: 'Adresse')),
    type: OtpType.signup,
  );
  final res = await client.auth.signInWithPassword(
    email: email,
    password: password,
  );
  return AdminAccount(
    email: email,
    password: password,
    id: res.user!.id,
    client: client,
  );
}

// ------------------------------------------------------------------ Mailpit

/// Wartet, bis Mailpit eine Mail an [to] hat, und liefert Text+HTML zurück.
/// [subject] grenzt per Mailpit-Suche ein — wichtig, sobald ein Postfach
/// mehrere Auth-Mails trägt (Bestätigung UND Reset), damit nicht die
/// falsche zurückkommt.
Future<String> waitForMail(
  String to, {
  String? subject,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final http = HttpClient();
  try {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final id = await _firstMessageId(http, to, subject: subject);
      if (id != null) return _messageBody(http, id);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    http.close(force: true);
  }
  throw StateError(
    'Keine Mail an $to (subject: $subject) innerhalb von '
    '${timeout.inSeconds}s (Mailpit: $e2eMailpitUrl)',
  );
}

/// Prüft, dass NACH [wait] keine Mail an [to] vorliegt (Negativ-Beweis).
Future<bool> noMailFor(
  String to, {
  Duration wait = const Duration(seconds: 3),
}) async {
  await Future<void>.delayed(wait);
  final http = HttpClient();
  try {
    return await _firstMessageId(http, to) == null;
  } finally {
    http.close(force: true);
  }
}

/// Der sechsstellige Code aus einer Auth-Mail — und zugleich der Wächter über
/// die Mail-Vorlage.
///
/// Beides ist Absicht: Fehlt die Zahl, zeigt die Vorlage kein `{{ .Token }}`;
/// steht ein GoTrue-Link darin, ist `{{ .ConfirmationURL }}` noch drin und der
/// gerätegebundene (kaputte) Weg wieder erreichbar. Genau davor schützt die
/// Umstellung aus Issue #102, deshalb schlägt der Test hier fehl statt später
/// beim Nutzer.
String firstCode(String body) {
  if (body.contains('auth/v1/verify')) {
    throw StateError(
      'Die Mail enthält einen Link — die Vorlage darf nur den Code zeigen '
      '(supabase/templates/, Issue #102):\n$body',
    );
  }
  final match = RegExp(r'\b\d{6}\b').firstMatch(body);
  if (match == null) {
    throw StateError(
      'Kein sechsstelliger Code in der Mail — zeigt die Vorlage '
      '{{ .Token }}?\n$body',
    );
  }
  return match.group(0)!;
}

/// Erste URL im Mail-Inhalt. Nach Issue #102 nur noch für den E-Mail-Wechsel
/// gedacht: Der läuft weiter über den Link, weil `updateUser` keinen
/// PKCE-Verifier erzeugt und die Bestätigung serverseitig passiert.
String firstLink(String body) {
  final match = RegExp('https?://[^\\s"<]+').firstMatch(body);
  if (match == null) {
    throw StateError('Kein Link im Mail-Inhalt gefunden:\n$body');
  }
  return match.group(0)!;
}

/// GoTrue schreibt in Mail-Links seine stack-INTERNE Adresse (127.0.0.1).
/// Läuft der Stack auf einer VM, muss der Link auf den Host aus
/// E2E_SUPABASE_URL umgebogen werden, sonst zeigt er ins Leere.
String rebaseAuthLink(String link) {
  final base = Uri.parse(e2eUrl!);
  final uri = Uri.parse(link);
  return uri
      .replace(scheme: base.scheme, host: base.host, port: base.port)
      .toString();
}

/// Löst einen GoTrue-Mail-Link ein (Bestätigung oder Recovery): folgt ihm
/// einmal und verlangt eine fehlerfreie Weiterleitung — genau das passiert,
/// wenn eine Nutzerin den Link in der Mail antippt.
Future<void> openAuthLink(String link) async {
  final http = HttpClient();
  try {
    final request = await http.getUrl(Uri.parse(rebaseAuthLink(link)));
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();
    final location = response.headers.value('location') ?? '';
    if (response.statusCode < 300 ||
        response.statusCode >= 400 ||
        location.contains('error')) {
      throw StateError(
        'Auth-Link nicht einlösbar (${response.statusCode}): $location',
      );
    }
  } finally {
    http.close(force: true);
  }
}

Future<String?> _firstMessageId(
  HttpClient http,
  String to, {
  String? subject,
}) async {
  final search = 'to:"$to"${subject == null ? '' : ' subject:"$subject"'}';
  final query = Uri.encodeQueryComponent(search);
  final json = await _getJson(
    http,
    '$e2eMailpitUrl/api/v1/search?query=$query',
  );
  final messages = json['messages'] as List<dynamic>? ?? <dynamic>[];
  if (messages.isEmpty) return null;
  return (messages.first as Map<String, dynamic>)['ID'] as String;
}

Future<String> _messageBody(HttpClient http, String id) async {
  final json = await _getJson(http, '$e2eMailpitUrl/api/v1/message/$id');
  final text = json['Text'] as String? ?? '';
  final html = json['HTML'] as String? ?? '';
  return '$text\n$html';
}

Future<Map<String, dynamic>> _getJson(HttpClient http, String url) async {
  final request = await http.getUrl(Uri.parse(url));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode != 200) {
    throw HttpException('GET $url -> ${response.statusCode}: $body');
  }
  return jsonDecode(body) as Map<String, dynamic>;
}
