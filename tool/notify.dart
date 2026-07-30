/// notify.dart – Hält den Push-Ausgangskorb in Ordnung (Issues #101, #132).
///
/// Läuft stündlich auf GitHub Actions (`.github/workflows/notify.yml`),
/// Muster und Selbstabschaltung wie beim Feedback-Bot.
///
/// **Dieser Job verschickt seit #132 nichts mehr.** Das tut die Datenbank:
/// Der Client legt beim Ändern in `push_outbox` ab, was zu sagen wäre, ein
/// Trigger macht die Zeile 60 Sekunden später fällig, pg_cron ruft
/// `flush-push`. Damit kommt eine Änderung binnen einer Minute an statt
/// erst beim nächsten Actions-Lauf — der real oft erst nach einer Stunde
/// kam (#115).
///
/// **Wozu es ihn trotzdem gibt: Er ist der Boden.** Rechnen beim Schreiben
/// ist schnell, aber nicht selbstheilend — ein Gerät ohne Netz, ein
/// geschlossener Tab, ein künftig vergessener Schreibpfad, und der Korb
/// stünde falsch da. Dieser Lauf rechnet ihn neu. Der Ereignis-Weg ist
/// damit ein Beschleuniger und keine Zusage: Schlägt er fehl, kommt die
/// Meldung eine Stunde später — also genau so spät wie vor der Umstellung.
///
/// **Warum Dart und nicht eine Edge Function:** Der Text nennt, wer morgen
/// fährt — und das ist eine berechnete Kennzahl aus `planWeek`. In
/// TypeScript nachgebaut wäre es die zweite Wahrheit über die Fairness-Regel,
/// und niemand merkte es, solange beide zufällig gleich rechnen. `fairness.dart`
/// und die Modelle sind reines Dart ohne Flutter-Import, also importiert
/// dieser Job den **echten** Code — genau wie die App.
///
/// Aufruf:
///   dart run tool/notify.dart [--dry-run] [--now 2026-07-27T21:05]
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/push_outbox.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_note.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final now = _argValue(args, '--now') != null
      ? DateTime.parse(_argValue(args, '--now')!)
      : DateTime.now();

  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || url.isEmpty || key == null || key.isEmpty) {
    // Wie der Feedback-Bot: ohne Zugang ruhen statt rot werden.
    stdout.writeln('SUPABASE_* fehlt – nichts zu tun.');
    return;
  }

  final api = _Api(url, key);

  // Anmerkungen vergangener Tage entfernen (#131): Am Folgetag sind sie
  // nicht mehr relevant, und sie tragen Namen — je kürzer sie liegen
  // bleiben, desto besser. Gruppenübergreifend (service_role) und VOR der
  // Gruppen-Schleife, damit auch stille Gruppen aufgeräumt werden — hinter
  // deren Early-Exits käme der Schritt nie an. Push-sicher: Für vergangene
  // Tage sendet `push_due()` nie (das Fenster schließt mit der Abfahrt),
  // und Tage vor dem Wochen-Montag haben gar keine Korb-Zeile mehr.
  if (!dryRun) {
    try {
      final purged = await api.deleteCounted('plan_notes', {
        'plan_date': 'lt.${_isoDay(now)}',
      });
      stdout.writeln('$purged Anmerkung(en) vergangener Tage entfernt.');
    } catch (error) {
      // Aufräumen darf den Versand nie verhindern; Details bleiben draußen,
      // das Actions-Protokoll ist öffentlich.
      stderr.writeln('Anmerkungs-Aufräumen übersprungen: ${error.runtimeType}');
    }
  }

  final groups = await api.rows('groups', {
    'status': 'eq.active',
    'select': 'id',
  });
  var rowsTotal = 0;

  for (final group in groups) {
    final groupId = group['id'] as String;
    try {
      rowsTotal += await _handleGroup(
        api: api,
        groupId: groupId,
        now: now,
        dryRun: dryRun,
      );
    } catch (error) {
      // Eine Gruppe darf den Lauf nicht abbrechen. Bewusst ohne Details:
      // Was hier ins Log kommt, steht im öffentlichen Actions-Protokoll.
      stderr.writeln('Gruppe übersprungen: ${error.runtimeType}');
    }
  }
  stdout.writeln('$rowsTotal Korb-Zeile(n)${dryRun ? ' (Probelauf)' : ''}.');
}

Future<int> _handleGroup({
  required _Api api,
  required String groupId,
  required DateTime now,
  required bool dryRun,
}) async {
  final scope = {'group_id': 'eq.$groupId'};

  final personRows = await api.rows('persons', {...scope, 'select': '*'});
  final persons = [for (final row in personRows) Person.fromJson(row)];
  final active = {
    for (final p in persons)
      if (p.active) p.id: p,
  };
  if (active.isEmpty) return 0;

  // Keine Einstellungen heißt: Diese Gruppe will nichts. Dann sparen wir uns
  // das Laden von Fahrten und Plan. Die Zeilen selbst braucht dieser Job
  // nicht mehr — welche Nachricht fällig ist, entscheidet `push_due()` beim
  // Senden aus denselben Einstellungen.
  final prefRows = await api.rows('notification_prefs', {
    ...scope,
    'select': 'person_id',
  });
  if (!prefRows.any((row) => active.containsKey(row['person_id']))) return 0;

  final week = planningWeek(now);
  final planned = await _plan(api, scope, week, active);

  // Anmerkungen (#127). `order=created_at` ist Pflicht: Der Digest mischt die
  // Notiz-IDs ein, und ohne zugesicherte Reihenfolge unterschiede er sich
  // zwischen zwei Läufen ohne jede Datenänderung — es gäbe endlos
  // „Änderung"-Meldungen. `push_digest.dart` sortiert zusätzlich selbst;
  // dieser Parameter ist die zweite Hälfte desselben Riegels und zugleich
  // das, was die Anzeige-Reihenfolge festlegt.
  final noteRows = await api.rows('plan_notes', {
    ...scope,
    'plan_date': 'gte.${_isoDay(week.first)}',
    'order': 'created_at',
    'select': '*',
  });
  final notes = [
    for (final row in noteRows)
      if (active.containsKey(row['person_id']))
        PlanNote.fromJson(row.cast<String, dynamic>()),
  ];

  // Ab #132 rechnet dieser Job nicht mehr aus, WAS verschickt wird — das
  // steht schon im Ausgangskorb, den die App beim Ändern schreibt. Er
  // rechnet ihn nur neu und repariert damit, was ein verpasster Schreibpfad
  // oder eine abgestürzte App hinterlassen hat. Verschickt wird aus der
  // Datenbank heraus (pg_cron → `flush-push`).
  //
  // **Das ist der Boden, auf dem der schnelle Weg steht.** Ohne diesen Lauf
  // wäre „der Client schreibt beim Ändern" eine Zusage, die niemand
  // einhalten kann: Ein Gerät ohne Netz, ein geschlossener Tab, ein
  // vergessener Aufruf — und die Meldung käme nie. So kommt sie eine Stunde
  // später, also genau so spät wie vor dieser Umstellung.
  final entries = outboxEntries(
    week: planned,
    persons: active,
    now: now,
    notes: notes,
  );
  if (dryRun) {
    // Im Probelauf keine Namen ins Protokoll: Der Actions-Log ist
    // öffentlich. Nur, wie viele Zeilen entstünden.
    stdout.writeln('  ${entries.length} Korb-Zeile(n)');
    return entries.length;
  }
  if (entries.isEmpty) return 0;

  // Vergangene Tage wegräumen, sonst wächst der Korb mit jedem Tag — dieselbe
  // Aufgabe, die `publish_push_outbox` für den Client erledigt. Der Job
  // schreibt mit dem service_role-Key und damit an der Funktion vorbei: Die
  // leitet die Gruppe aus `auth.uid()` ab, und die hat er nicht.
  await api.delete('push_outbox', {
    ...scope,
    'plan_date': 'lt.${_isoDay(week.first)}',
  });
  await api.upsert('push_outbox', [
    for (final entry in entries) {'group_id': groupId, ...entry.toJson()},
  ], onConflict: 'group_id,person_id,plan_date');
  return entries.length;
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
    Object row, {
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

  /// Löscht und liefert die Zeilenzahl — fürs Protokoll, das nur Zahlen
  /// nennen darf.
  Future<int> deleteCounted(String table, Map<String, String> query) async {
    final uri = Uri.parse('$base/$table').replace(queryParameters: query);
    final response = await http.delete(
      uri,
      headers: {..._headers, 'Prefer': 'count=exact'},
    );
    if (response.statusCode >= 400) {
      throw HttpException('$table ${response.statusCode}');
    }
    // PostgREST meldet die Zahl im Content-Range-Header als `*/N`.
    final range = response.headers['content-range'];
    return int.tryParse(range?.split('/').last ?? '') ?? 0;
  }
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _isoDay(DateTime date) => date.toIso8601String().substring(0, 10);
