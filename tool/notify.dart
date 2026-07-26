/// notify.dart – Verschickt die Wochenplan-Benachrichtigungen (Issue #101).
///
/// Läuft alle zehn Minuten auf GitHub Actions (`.github/workflows/notify.yml`),
/// Muster und Selbstabschaltung wie beim Feedback-Bot.
///
/// **Warum Dart und nicht eine Edge Function:** Der Text nennt, wer morgen
/// fährt — und das ist eine berechnete Kennzahl aus `planWeek`. In
/// TypeScript nachgebaut wäre es die zweite Wahrheit über die Fairness-Regel,
/// und niemand merkte es, solange beide zufällig gleich rechnen. `fairness.dart`
/// und die Modelle sind reines Dart ohne Flutter-Import, also importiert
/// dieser Job den **echten** Code. Verschickt wird über die Edge Function
/// `send-push`, damit das FCM-Dienstkonto bei den übrigen Server-Geheimnissen
/// bleibt.
///
/// Aufruf:
///   dart run tool/notify.dart [--dry-run] [--now 2026-07-27T21:05]
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/push_digest.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final now = _argValue(args, '--now') != null
      ? DateTime.parse(_argValue(args, '--now')!)
      : DateTime.now();

  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  final jobSecret = Platform.environment['PUSH_JOB_SECRET'];
  if (url == null || url.isEmpty || key == null || key.isEmpty) {
    // Wie der Feedback-Bot: ohne Zugang ruhen statt rot werden.
    stdout.writeln('SUPABASE_* fehlt – nichts zu tun.');
    return;
  }
  if (!dryRun && (jobSecret == null || jobSecret.isEmpty)) {
    stdout.writeln('PUSH_JOB_SECRET fehlt – nichts zu tun.');
    return;
  }

  final api = _Api(url, key);
  final groups = await api.rows('groups', {
    'status': 'eq.active',
    'select': 'id',
  });
  var sentTotal = 0;

  for (final group in groups) {
    final groupId = group['id'] as String;
    try {
      sentTotal += await _handleGroup(
        api: api,
        groupId: groupId,
        now: now,
        dryRun: dryRun,
        jobSecret: jobSecret ?? '',
        functionsUrl: '$url/functions/v1/send-push',
        anonOrServiceKey: key,
      );
    } catch (error) {
      // Eine Gruppe darf den Lauf nicht abbrechen. Bewusst ohne Details:
      // Was hier ins Log kommt, steht im öffentlichen Actions-Protokoll.
      stderr.writeln('Gruppe übersprungen: ${error.runtimeType}');
    }
  }
  stdout.writeln(
    '$sentTotal Benachrichtigung(en)${dryRun ? ' (Probelauf)' : ''}.',
  );
}

Future<int> _handleGroup({
  required _Api api,
  required String groupId,
  required DateTime now,
  required bool dryRun,
  required String jobSecret,
  required String functionsUrl,
  required String anonOrServiceKey,
}) async {
  final scope = {'group_id': 'eq.$groupId'};

  final personRows = await api.rows('persons', {...scope, 'select': '*'});
  final persons = [for (final row in personRows) Person.fromJson(row)];
  final active = {
    for (final p in persons)
      if (p.active) p.id: p,
  };
  if (active.isEmpty) return 0;

  final prefRows = await api.rows('notification_prefs', {
    ...scope,
    'select': '*',
  });
  final prefs = <String, NotificationPrefs>{
    for (final row in prefRows)
      if (active.containsKey(row['person_id']))
        row['person_id'] as String: NotificationPrefs.fromJson(row),
  };
  // Keine Einstellungen heißt: Diese Gruppe will nichts. Dann sparen wir uns
  // das Laden von Fahrten und Plan.
  if (prefs.isEmpty) return 0;

  final deviceRows = await api.rows('push_devices', {
    ...scope,
    'select': 'token, person_id',
  });
  final devices = <String, List<String>>{};
  for (final row in deviceRows) {
    final personId = row['person_id'] as String?;
    if (personId == null) continue;
    devices.putIfAbsent(personId, () => []).add(row['token'] as String);
  }
  if (devices.isEmpty) return 0;

  final week = planningWeek(now);
  final planned = await _plan(api, scope, week, active);

  final logRows = await api.rows('push_log', {
    ...scope,
    'plan_date': 'gte.${_isoDay(week.first)}',
    'select': '*',
  });
  final sent = [
    for (final row in logRows)
      SentPush(
        personId: row['person_id'] as String,
        planDate: DateTime.parse(row['plan_date'] as String),
        kind: row['kind'] == 'evening' ? PushKind.evening : PushKind.change,
        digest: row['digest'] as String,
        sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
      ),
  ];

  final due = dueMessages(
    week: planned,
    prefs: prefs,
    sent: sent,
    persons: active,
    now: now,
  );
  if (due.isEmpty) return 0;

  var count = 0;
  for (final message in due) {
    final tokens = devices[message.personId] ?? const [];
    if (tokens.isEmpty) continue;
    if (dryRun) {
      // Im Probelauf keine Namen ins Protokoll: Der Actions-Log ist
      // öffentlich. Nur, was verschickt würde.
      stdout.writeln(
        '  ${message.kind.name} → ${tokens.length} Gerät(e), '
        '${_isoDay(message.planDate)}',
      );
      count += 1;
      continue;
    }

    final results = await _send(
      functionsUrl: functionsUrl,
      apiKey: anonOrServiceKey,
      jobSecret: jobSecret,
      messages: [
        for (final token in tokens)
          {'token': token, 'title': message.title, 'body': message.body},
      ],
    );
    final delivered = results.where((r) => r['status'] == 'ok').length;
    // Abgelaufene Registrierungen wegräumen, sonst wächst die Tabelle mit
    // deinstallierten Apps zu.
    for (final result in results.where((r) => r['status'] == 'unregistered')) {
      await api.delete('push_devices', {'token': 'eq.${result['token']}'});
    }
    if (delivered == 0) continue;

    await api.upsert('push_log', {
      'group_id': groupId,
      'person_id': message.personId,
      'plan_date': _isoDay(message.planDate),
      'kind': message.kind.name,
      'digest': message.digest,
      'sent_at': now.toUtc().toIso8601String(),
    }, onConflict: 'group_id,person_id,plan_date,kind');
    count += 1;
  }
  return count;
}

/// Der Wochenplan dieser Gruppe — mit der echten Fairness-Rechnung.
Future<List<PlannedDay>> _plan(
  _Api api,
  Map<String, String> scope,
  List<DateTime> week,
  Map<String, Person> active,
) async {
  final tripRows = await api.rows('trips', {
    ...scope,
    'select': 'id, trip_date, note, trip_participations(person_id, status)',
  });
  final trips = [
    for (final row in tripRows)
      Trip(
        id: row['id'] as String,
        date: DateTime.parse(row['trip_date'] as String),
        note: row['note'] as String?,
        participations: {
          for (final p in (row['trip_participations'] as List))
            (p as Map<String, dynamic>)['person_id']
                as String: switch (p['status']) {
              'driver' => ParticipationStatus.driver,
              'passenger' => ParticipationStatus.passenger,
              _ => ParticipationStatus.oneWay,
            },
        },
      ),
  ];

  final settingRows = await api.rows('settings', {
    ...scope,
    'select': 'key, value',
  });
  final settings = AppSettings.fromMap({
    for (final row in settingRows)
      row['key'] as String: (row['value'] as num).toDouble(),
  });

  final from = _isoDay(week.first);
  final to = _isoDay(week.last);
  final availabilityRows = await api.rows('plan_availability', {
    ...scope,
    'plan_date': 'gte.$from',
    'select': '*',
  });
  final overrideRows = await api.rows('plan_overrides', {
    ...scope,
    'plan_date': 'gte.$from',
    'select': '*',
  });

  final availability = <DateTime, Map<String, PlanRide>>{};
  for (final row in availabilityRows) {
    final date = DateTime.parse(row['plan_date'] as String);
    if (_isoDay(date).compareTo(to) > 0) continue;
    final personId = row['person_id'] as String;
    // Inaktive Personen fallen raus — genau wie im Planer der App.
    if (!active.containsKey(personId)) continue;
    availability.putIfAbsent(date, () => {})[personId] =
        (row['one_way'] as bool? ?? false) ? PlanRide.oneWay : PlanRide.full;
  }
  final overrides = <DateTime, Set<String>>{};
  for (final row in overrideRows) {
    final date = DateTime.parse(row['plan_date'] as String);
    if (_isoDay(date).compareTo(to) > 0) continue;
    final driverId = row['driver_id'] as String;
    if (!active.containsKey(driverId)) continue;
    overrides.putIfAbsent(date, () => {}).add(driverId);
  }

  return planWeek(
    dates: week,
    availability: availability,
    overrides: overrides,
    trips: trips,
    settings: settings,
    seats: {for (final entry in active.entries) entry.key: entry.value.seats},
  );
}

Future<List<Map<String, Object?>>> _send({
  required String functionsUrl,
  required String apiKey,
  required String jobSecret,
  required List<Map<String, String>> messages,
}) async {
  final response = await http.post(
    Uri.parse(functionsUrl),
    headers: {
      'Content-Type': 'application/json',
      'apikey': apiKey,
      'x-push-secret': jobSecret,
    },
    body: jsonEncode({'messages': messages}),
  );
  if (response.statusCode != 200) {
    throw HttpException('send-push ${response.statusCode}');
  }
  final payload = jsonDecode(response.body) as Map<String, Object?>;
  return (payload['results'] as List).cast<Map<String, Object?>>();
}

/// Der schmale PostgREST-Zugang. Bewusst ohne SDK — wie `feedback_bot.py`.
class _Api {
  _Api(String url, this.key)
    : base = '${url.replaceAll(RegExp(r'/$'), '')}/rest/v1';

  final String base;
  final String key;

  /// Alte service_role-Keys sind JWTs und brauchen zusätzlich Authorization;
  /// neue `sb_secret_*`-Keys nur den apikey-Header.
  Map<String, String> get _headers => {
    'apikey': key,
    'Content-Type': 'application/json',
    if (key.startsWith('eyJ')) 'Authorization': 'Bearer $key',
  };

  Future<List<Map<String, Object?>>> rows(
    String table,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$base/$table').replace(queryParameters: query);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 404) return const [];
    if (response.statusCode >= 400) {
      throw HttpException('$table ${response.statusCode}');
    }
    return (jsonDecode(response.body) as List).cast<Map<String, Object?>>();
  }

  Future<void> upsert(
    String table,
    Map<String, Object?> row, {
    required String onConflict,
  }) async {
    final uri = Uri.parse(
      '$base/$table',
    ).replace(queryParameters: {'on_conflict': onConflict});
    final response = await http.post(
      uri,
      headers: {..._headers, 'Prefer': 'resolution=merge-duplicates'},
      body: jsonEncode(row),
    );
    if (response.statusCode >= 400) {
      throw HttpException('$table ${response.statusCode}');
    }
  }

  Future<void> delete(String table, Map<String, String> query) async {
    final uri = Uri.parse('$base/$table').replace(queryParameters: query);
    await http.delete(uri, headers: _headers);
  }
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _isoDay(DateTime date) => date.toIso8601String().substring(0, 10);
