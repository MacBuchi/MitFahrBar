/// usage_report.dart – Wöchentlicher anonymisierter Nutzungsbericht (#134).
///
/// Läuft montags früh auf GitHub Actions (`.github/workflows/usage-report.yml`)
/// und schreibt EIN dauerhaftes ops-Issue „Usage report": Der Issue-Text
/// trägt die frisch abgeschlossene Woche plus eine Verlaufstabelle der
/// letzten 26 ISO-Wochen; zusätzlich postet der Job einen Kommentar mit dem
/// Wochenblock — GitHub verschickt Kommentare als Mail (voller Text + Link),
/// das Umschreiben eines Issue-Texts dagegen nicht.
///
/// **Warum Dart und nicht ein Shell-/TS-Skript:** Die Ersparnis ist eine
/// berechnete Kennzahl aus `savedCosts`/`computeStats`/`kilometers`. Hier
/// nachgebaut wäre sie die zweite Wahrheit über dieselbe Formel — deshalb
/// importiert der Job den echten Code, wie `tool/notify.dart`.
///
/// **Warum jede Woche komplett neu gerechnet wird:** Fahrten werden in
/// dieser App notorisch nachgetragen (der Schnellwahl-Chip heißt „Gestern",
/// Zukunft ist gesperrt). Ein einmal eingefrorener Wochenwert wäre
/// systematisch zu niedrig; die zustandslose Neurechnung korrigiert
/// vergangene Zeilen bei jedem Lauf still.
///
/// **Warum auch eine Null-Woche berichtet wird** — bewusste Abweichung vom
/// Error-Digest des Feedback-Bots („keine Zeilen = kein Issue"): Bei einem
/// Nutzungsbericht ist „nichts passiert" genau das Signal, auf das der
/// Betreiber wartet.
///
/// **Anonymisierung ist strukturell:** Die Selects laden `persons` ohne
/// `name` und `trips` ohne `note` (Freitext kann Namen tragen) — Namen
/// erreichen den Speicher dieses Jobs nie, und es gibt nur Summen über alle
/// Gruppen, nie Zahlen je Gruppe. `test/report_workflow_test.dart` nagelt
/// beides fest.
///
/// Aufruf:
///   dart run tool/usage_report.dart [--dry-run] [--now 2026-08-03T05:43]
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';

/// Wie viele abgeschlossene ISO-Wochen die Verlaufstabelle zeigt.
const historyWeeks = 26;

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final now = _argValue(args, '--now') != null
      ? DateTime.parse(_argValue(args, '--now')!)
      : DateTime.now();

  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || url.isEmpty || key == null || key.isEmpty) {
    // Wie Feedback-Bot und notify: ohne Zugang ruhen statt rot werden.
    stdout.writeln('SUPABASE_* fehlt – nichts zu tun.');
    return;
  }

  final api = _Api(url, key);

  // Montag der laufenden ISO-Woche; alles davor ist abgeschlossen. Gerechnet
  // in UTC — `Duration`-Addition auf lokalen DateTimes verrutscht über die
  // Sommerzeit (dieselbe Begründung wie bei `isoWeekNumber`), und der
  // Workflow setzt TZ=Europe/Berlin.
  final today = DateTime.utc(now.year, now.month, now.day);
  final currentMonday = today.subtract(Duration(days: today.weekday - 1));
  final cutoff = currentMonday.subtract(const Duration(days: 7 * historyWeeks));

  final groupRows = await api.rows('groups', {'select': 'id, status'});

  // Personen OHNE `name`: `savedCosts` liest nur Energieart und Verbrauch.
  // Auch Inaktive bleiben drin — wer im Juni deaktiviert wurde, fuhr im Mai,
  // und die Historie soll rückwirkend stimmen.
  final personRows = await api.rows('persons', {
    'select': 'id, group_id, active, energy_type, consumption_per_100km',
  });
  final personsByGroup = <String, Map<String, Person>>{};
  for (final row in personRows) {
    final person = Person(
      id: row['id'] as String,
      name: '',
      active: row['active'] as bool,
      energyType: row['energy_type'] == null
          ? null
          : EnergyType.values.byName(row['energy_type'] as String),
      consumptionPer100km: (row['consumption_per_100km'] as num?)?.toDouble(),
    );
    personsByGroup.putIfAbsent(row['group_id'] as String, () => {})[person.id] =
        person;
  }

  final settingRows = await api.rows('settings', {
    'select': 'group_id, key, value',
  });
  final settingsMapByGroup = <String, Map<String, double>>{};
  for (final row in settingRows) {
    settingsMapByGroup.putIfAbsent(
      row['group_id'] as String,
      () => {},
    )[row['key'] as String] = (row['value'] as num)
        .toDouble();
  }
  // Gruppen ohne Zeilen bekommen dieselben Defaults wie die App selbst.
  AppSettings settingsOf(String groupId) =>
      AppSettings.fromMap(settingsMapByGroup[groupId] ?? const {});

  // Fahrten OHNE `note` — die Notiz ist Freitext und kann Namen tragen.
  // `rows()` nimmt je Spalte nur EIN Filter (Map), deshalb `gte` im Query
  // und die laufende Woche im Speicher ausgefiltert.
  final tripRows = await api.rows('trips', {
    'select': 'id, group_id, trip_date, trip_participations(person_id, status)',
    'trip_date': 'gte.${_isoDay(cutoff)}',
    'order': 'trip_date',
  });
  final tripsByGroupAndMonday = <String, Map<DateTime, List<Trip>>>{};
  for (final row in tripRows) {
    final date = DateTime.parse(row['trip_date'] as String);
    final day = DateTime.utc(date.year, date.month, date.day);
    if (!day.isBefore(currentMonday)) continue;
    final monday = day.subtract(Duration(days: day.weekday - 1));
    final participations = <String, ParticipationStatus>{
      for (final p
          in (row['trip_participations'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        p['person_id'] as String: switch (p['status']) {
          'driver' => ParticipationStatus.driver,
          'passenger' => ParticipationStatus.passenger,
          _ => ParticipationStatus.oneWay,
        },
    };
    final trip = Trip(
      id: row['id'] as String,
      date: day,
      participations: participations,
    );
    tripsByGroupAndMonday
        .putIfAbsent(row['group_id'] as String, () => {})
        .putIfAbsent(monday, () => [])
        .add(trip);
  }

  // Je abgeschlossener Woche: Fahrten, aktiv genutzte Gruppen, Ersparnis und
  // Kilometer — Summen über alle Gruppen, nie je Gruppe (Anonymisierung).
  final weeks = <_WeekStats>[];
  for (var k = 1; k <= historyWeeks; k++) {
    final monday = currentMonday.subtract(Duration(days: 7 * k));
    var trips = 0;
    var groups = 0;
    var saved = 0.0;
    var km = 0.0;
    var personDays = 0;
    for (final entry in tripsByGroupAndMonday.entries) {
      final weekTrips = entry.value[monday];
      if (weekTrips == null || weekTrips.isEmpty) continue;
      groups += 1;
      trips += weekTrips.length;
      final settings = settingsOf(entry.key);
      final persons = personsByGroup[entry.key] ?? const {};
      final stats = computeStats(weekTrips, settings);
      for (final s in stats.values) {
        final person = persons[s.personId];
        if (person == null) continue;
        saved += s.savedCosts(settings, person);
        km += s.kilometers(settings);
        personDays += s.participationDays;
      }
    }
    weeks.add(
      _WeekStats(
        monday: monday,
        trips: trips,
        groups: groups,
        saved: saved,
        km: km,
        personDays: personDays,
      ),
    );
  }

  final statusCounts = <String, int>{};
  for (final row in groupRows) {
    final status = row['status'] as String? ?? 'unknown';
    statusCounts[status] = (statusCounts[status] ?? 0) + 1;
  }

  final latest = weeks.first;
  final weekBlock = _weekBlock(latest, statusCounts);
  final body = _issueBody(weeks, weekBlock);

  if (dryRun) {
    // Der Bericht ist konstruktionsbedingt namensfrei — er darf ins
    // öffentliche Actions-Protokoll.
    stdout.writeln(body);
    stdout.writeln('(Probelauf — kein Issue, kein Kommentar.)');
    return;
  }

  await _deliver(weekBlock: weekBlock, body: body);
  stdout.writeln(
    '${latest.trips} Fahrt(en), ${latest.groups} aktive Gruppe(n) in '
    '${_weekLabel(latest.monday)} — Issue aktualisiert.',
  );
}

class _WeekStats {
  const _WeekStats({
    required this.monday,
    required this.trips,
    required this.groups,
    required this.saved,
    required this.km,
    required this.personDays,
  });

  final DateTime monday;
  final int trips;
  final int groups;
  final double saved;
  final double km;

  /// Summe der Anwesenheitstage über alle Personen — `driven + ridden +
  /// oneWay`, dieselbe Größe, aus der `kilometers` die Strecke macht.
  final int personDays;

  /// Wie voll die Autos waren: Personen je Fahrt.
  ///
  /// Steht neben den Kilometern, weil die Strecke diese Frage NICHT
  /// beantworten kann: `km` ist `Anwesenheitstage × Arbeitsweg × 2`, und
  /// damit fällt sie gleichermaßen, wenn die Autos leerer fahren ODER wenn
  /// die Woche überwiegend aus Fahrten der Gruppe mit dem kürzeren Arbeitsweg
  /// besteht. Aus einer Summe sind die beiden Fälle nicht zu trennen; diese
  /// Zahl ist gegen die Weglänge unempfindlich und trennt sie.
  ///
  /// Anlass war 2026-W35: 7 Fahrten wie üblich, aber 77 km je Fahrt — 45 %
  /// unter dem Minimum der 25 Wochen davor. Fahrten und Ersparnis sahen
  /// unauffällig aus; sichtbar wurde es erst, als jemand das Verhältnis von
  /// Hand ausrechnete. Genau das soll niemand mehr müssen.
  double? get personsPerTrip => trips == 0 ? null : personDays / trips;
}

/// Personen je Fahrt als Text, `–` für eine Woche ganz ohne Fahrt.
///
/// Eine Woche ohne Fahrten (2026-W22 etwa) hat keine Besetzung — `0,0` wäre
/// dort eine Aussage über leere Autos, die es nicht gab, und im Verlauf ein
/// Einbruch, den niemand erklären kann.
String _perTrip(_WeekStats w) => w.personsPerTrip?.toStringAsFixed(1) ?? '–';

/// ISO-8601-Wochenjahr: das Jahr des Donnerstags derselben Woche — Gegenstück
/// zum importierten [isoWeekNumber] (2021-01-01 gehört zu 2020-W53).
int _isoWeekYear(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  return day.add(Duration(days: DateTime.thursday - day.weekday)).year;
}

String _weekLabel(DateTime date) =>
    '${_isoWeekYear(date)}-W${isoWeekNumber(date).toString().padLeft(2, '0')}';

String _weekBlock(_WeekStats week, Map<String, int> statusCounts) {
  final status = [
    for (final key in ['active', 'pending', 'archived', 'rejected'])
      if ((statusCounts[key] ?? 0) > 0) '${statusCounts[key]} $key',
  ].join(' · ');
  return '''
## Week ${_weekLabel(week.monday)}

- Groups with trips: **${week.groups}**
- Trips: **${week.trips}**
- Savings: **${week.saved.toStringAsFixed(2)} EUR**
- Distance: **${week.km.round()} km**
- Persons per trip: **${_perTrip(week)}**

Groups total: $status.''';
}

/// Wie viele Wochen die Trend-Charts zeigen. Weniger als die Tabelle:
/// 26 Achsen-Labels quetschen sich in Mermaid unlesbar zusammen — die
/// Tabelle bleibt die exakte Zahlenbasis für die volle Historie.
const chartWeeks = 12;

/// Ein Trend-Chart als Mermaid `xychart-beta` — GitHub rendert das nativ
/// im Issue, null zusätzliche Infrastruktur.
///
/// EINE Serie und EINE Achse je Chart: Fahrten und Ersparnis sind
/// verschieden skalierte Größen — die gehören in zwei Charts, nie an eine
/// Doppelachse. Balken beginnen bei 0 (abgeschnittene Balken lügen).
/// Die Farbe ist das Banner-Teal, minimal chroma-angehoben (#0787A6),
/// damit die Marke auf GitHubs heller UND dunkler Fläche weder grau
/// liest noch den Kontrast reißt — mit dem Palette-Validator gerechnet,
/// nicht geschätzt.
String _chart({
  required String title,
  required String yLabel,
  required List<_WeekStats> oldestFirst,
  required int Function(_WeekStats) value,
  required String mark,
}) {
  final values = [for (final w in oldestFirst) value(w)];
  var top = 1;
  for (final v in values) {
    if (v >= top) top = v + 1;
  }
  final labels = [
    for (final w in oldestFirst)
      'W${isoWeekNumber(w.monday).toString().padLeft(2, '0')}',
  ];
  return '''
```mermaid
%%{init: {"theme": "base", "themeVariables": {"xyChart": {"plotColorPalette": "#0787A6"}}}}%%
xychart-beta
    title "$title"
    x-axis [${labels.join(', ')}]
    y-axis "$yLabel" 0 --> $top
    $mark [${values.join(', ')}]
```''';
}

String _issueBody(List<_WeekStats> weeks, String weekBlock) {
  // `weeks` kommt neueste zuerst; die Charts lesen sich links → rechts.
  final trend = weeks.take(chartWeeks).toList().reversed.toList();
  final rows = [
    for (final w in weeks)
      '| ${_weekLabel(w.monday)} | ${w.groups} | ${w.trips} | '
          '${w.saved.toStringAsFixed(2)} | ${w.km.round()} | ${_perTrip(w)} |',
  ].join('\n');
  return '''
$weekBlock

## Trend (last ${trend.length} weeks)

${_chart(title: 'Trips per week', yLabel: 'Trips', oldestFirst: trend, value: (w) => w.trips, mark: 'bar')}

${_chart(title: 'Savings per week (EUR)', yLabel: 'EUR', oldestFirst: trend, value: (w) => w.saved.round(), mark: 'line')}

## History (last $historyWeeks completed weeks)

| Week | Groups | Trips | Savings (EUR) | km | Persons/trip |
|------|--------|-------|---------------|----|--------------|
$rows

Savings and km exclude solo trips (issue #61) and persons without vehicle
data — same rules as in the app. History is recomputed on every run; late
entries update past rows. Exact values live in the table; the charts show
the shape.

Persons per trip is presence days divided by trips. It answers a question km
cannot: km is presence days × commute × 2, so it drops both when cars run
emptier and when a week is dominated by the group with the shorter commute.
This column is blind to commute length, so it separates the two.

_Automatically maintained by the usage report job (issue #134)._''';
}

/// Schreibt den Issue-Text neu und postet den Wochenblock als Kommentar —
/// der Kommentar ist der Mail-Auslöser (@-Mention inklusive).
Future<void> _deliver({required String weekBlock, required String body}) async {
  // Label idempotent anlegen — `gh issue create` scheitert an unbekannten
  // Labels (Muster Feedback-Bot). Fehler hier sind egal (existiert schon).
  await Process.run('gh', [
    'label',
    'create',
    'ops',
    '--color',
    '5319E7',
    '--description',
    'Betrieb, Monitoring, Backups',
  ]);

  // Präfix-Suche statt exaktem Titel: Unter demselben Label liegen auch die
  // „Error reports"-Wochen-Issues des Feedback-Bots. Ein von Hand
  // geschlossenes Issue bleibt geschlossen — der nächste Lauf legt ein
  // frisches an.
  final list = await _gh([
    'issue',
    'list',
    '--state',
    'open',
    '--label',
    'ops',
    '--limit',
    '50',
    '--json',
    'number,title',
  ]);
  final issues = (jsonDecode(list) as List).cast<Map<String, Object?>>();
  final existing = issues
      .where((i) => (i['title'] as String).startsWith('Usage report'))
      .firstOrNull;

  final String number;
  if (existing != null) {
    number = '${existing['number']}';
    await _gh(['issue', 'edit', number, '--body', body]);
  } else {
    final url = await _gh([
      'issue',
      'create',
      '--title',
      'Usage report',
      '--body',
      body,
      '--label',
      'ops',
    ]);
    number = url.trim().split('/').last;
  }

  // Der Kommentar trägt die Mail: GitHub verschickt neue Kommentare mit
  // vollem Text und Link, das Umschreiben des Issue-Texts nicht.
  //
  // Über die REST-API, nicht `gh issue comment`: Dessen GraphQL-Mutation
  // scheiterte mit dem Actions-GITHUB_TOKEN an „Resource not accessible by
  // integration" (beobachtet 30.07.2026, Lauf 30560898790) — obwohl list,
  // create und edit mit demselben Token laufen. Der REST-Endpunkt nimmt
  // `issues: write` anstandslos.
  final repo = Platform.environment['GITHUB_REPOSITORY'] ?? _fallbackRepo;
  await _gh([
    'api',
    'repos/$repo/issues/$number/comments',
    '-f',
    'body=$weekBlock\n\ncc @MacBuchi',
  ]);
}

/// Außerhalb von Actions fehlt GITHUB_REPOSITORY — dann gilt das Prod-Repo,
/// dieselbe Linie wie die fest verdrahtete SUPABASE_URL im Workflow.
const _fallbackRepo = 'MacBuchi/MitFahrBar';

/// `gh` mit Argumentliste (kein Shell, kein Quoting-Risiko). Ein Fehler
/// macht den Lauf rot — anders als fehlende Secrets: Wer den Bericht
/// bestellt hat, soll einen stillen Ausfall im Actions-Tab sehen.
/// gh's stderr darf mit ins Log: Der Bericht ist namensfrei gebaut, und
/// ohne die Meldung ist ein Montag-früh-Ausfall nicht diagnostizierbar.
Future<String> _gh(List<String> args) async {
  final result = await Process.run('gh', args);
  if (result.exitCode != 0) {
    stderr.writeln(
      '::error::gh ${args.take(2).join(' ')} failed '
      '(exit ${result.exitCode}): ${result.stderr}',
    );
    throw ProcessException('gh', args, '', result.exitCode);
  }
  return result.stdout as String;
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

  /// Liest ALLE Zeilen — mit Paging: Hosted-PostgREST deckelt still bei
  /// 1000 Zeilen je Antwort, und eine still zu niedrige Zahl im Bericht
  /// wäre der schlimmste Fehlermodus. Wer pagt, braucht `order` im Query,
  /// sonst sichert PostgREST keine Reihenfolge zu.
  Future<List<Map<String, Object?>>> rows(
    String table,
    Map<String, String> query,
  ) async {
    const page = 1000;
    final all = <Map<String, Object?>>[];
    for (var from = 0; ; from += page) {
      final uri = Uri.parse('$base/$table').replace(queryParameters: query);
      final response = await http.get(
        uri,
        headers: {..._headers, 'Range': '$from-${from + page - 1}'},
      );
      if (response.statusCode == 404) return const [];
      if (response.statusCode >= 400) {
        throw HttpException('$table ${response.statusCode}');
      }
      final rows = (jsonDecode(response.body) as List)
          .cast<Map<String, Object?>>();
      all.addAll(rows);
      if (rows.length < page) return all;
    }
  }
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _isoDay(DateTime date) => date.toIso8601String().substring(0, 10);
