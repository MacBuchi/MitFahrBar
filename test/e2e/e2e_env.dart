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
final String _runTag = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
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
  });

  final String handle;
  final String email;
  final String password;
  final String id;
  final SupabaseClient client;
}

/// Registriert eine neue Gruppe wie die App: Handle → interne Login-E-Mail.
/// Der Signup-Trigger legt dazu die pending-`groups`-Zeile an.
Future<GroupAccount> registerGroup(String label) async {
  final handle = uniqueName(label);
  final email = '$handle@$e2eGroupDomain';
  const password = 'gruppen-passwort-1';
  final client = newAnonClient();
  final res = await client.auth.signUp(email: email, password: password);
  return GroupAccount(
    handle: handle,
    email: email,
    password: password,
    id: res.user!.id,
    client: client,
  );
}

/// Freigabe, die in der App die Admin-Gruppe erteilt — hier per Service-Role.
Future<void> activateGroup(SupabaseClient service, String groupId) async {
  await service.from('groups').update({'status': 'active'}).eq('id', groupId);
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
/// `account_type: 'admin'` in den Metadata.
Future<AdminAccount> registerAdmin({
  String password = 'admin-passwort-1',
}) async {
  final email = '${uniqueName('admin')}@e2e-postfach.test';
  final client = newAnonClient();
  final res = await client.auth.signUp(
    email: email,
    password: password,
    data: {'account_type': 'admin'},
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
Future<String> waitForMail(
  String to, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final http = HttpClient();
  try {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final id = await _firstMessageId(http, to);
      if (id != null) return _messageBody(http, id);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    http.close(force: true);
  }
  throw StateError(
    'Keine Mail an $to innerhalb von ${timeout.inSeconds}s '
    '(Mailpit: $e2eMailpitUrl)',
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

/// Erste URL im Mail-Inhalt — bei Auth-Mails der Bestätigungs-/Reset-Link.
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

Future<String?> _firstMessageId(HttpClient http, String to) async {
  final query = Uri.encodeQueryComponent('to:"$to"');
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
