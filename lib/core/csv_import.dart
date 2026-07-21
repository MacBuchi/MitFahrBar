/// csv_import.dart – Fahrten aus der CSV lesen, die der Export schreibt.
///
/// Reine Auswertung ohne Datei-Zugriff und ohne Repository: Das Einlesen
/// liegt in `import_file.dart`, das Schreiben im Screen. Dadurch ist das
/// Format ohne Plattform testbar — dieselbe Trennung wie bei `csv_export`.
///
/// Bewusst **minimal**: Datum, wer gefahren ist, wer mitgefahren ist. Fahrzeug,
/// Verbrauch und Sitzplätze pflegt man in der App; sie hier mitzuschleppen
/// hieße, ein zweites Format zu pflegen, das nur beim Import existiert.
///
/// Der Import legt **nie** von sich aus Personen an. `persons.name` hat keine
/// Eindeutigkeit in der Datenbank — aus „Marcus" und „Marcus " würden zwei
/// Personen, und das verschiebt rückwirkend die Punkte *aller anderen*.
/// Deshalb liefert [parseTripCsv] neue Namen nur als Vorschlag; entschieden
/// wird in der Oberfläche.
library;

import '../models/trip.dart';
import 'csv_export.dart';

/// Eine eingelesene Zeile: ein Tag mit Teilnahmen **nach Personennamen**.
/// Die Zuordnung zu Ids passiert erst, wenn feststeht, wer angelegt wird.
class ImportedTrip {
  const ImportedTrip({
    required this.line,
    required this.date,
    required this.participations,
    this.note,
  });

  /// Zeilennummer in der Datei (1-basiert, inklusive Kopfzeile) — damit eine
  /// Meldung auf die Stelle zeigen kann, die die Nutzerin vor sich hat.
  final int line;
  final DateTime date;
  final Map<String, ParticipationStatus> participations;
  final String? note;
}

/// Was beim Einlesen herauskam.
class ImportResult {
  const ImportResult({
    required this.trips,
    required this.names,
    required this.problems,
  });

  /// Nichts gelesen, mit genau einem Grund — der Kopf der Datei stimmt nicht.
  ImportResult.failed(String problem)
    : trips = const [],
      names = const [],
      problems = [problem];

  /// Gelesene Fahrten, aufsteigend nach Datum.
  final List<ImportedTrip> trips;

  /// Alle Personen-Spalten der Kopfzeile, in ihrer Reihenfolge.
  final List<String> names;

  /// Übersprungene Zeilen und was an ihnen nicht stimmte. Bewusst gesammelt
  /// statt beim ersten Fehler abzubrechen: Eine krumme Zeile in der Mitte
  /// soll nicht die anderen 200 verhindern.
  final List<String> problems;

  bool get isEmpty => trips.isEmpty;
}

/// Umkehrung von [statusLabels]. Kleinschreibung, damit „fahrer" genauso
/// gelesen wird wie „Fahrer" — die Datei geht durch fremde Tabellenprogramme.
final _statusByLabel = {
  for (final e in statusLabels.entries) e.value.toLowerCase(): e.key,
};

/// Liest den Inhalt einer Export-CSV.
///
/// Verträgt CRLF und LF, ein führendes BOM und Anführungszeichen nach
/// RFC 4180 — also genau das, was `buildTripCsv` schreibt, plus das, was ein
/// Tabellenprogramm daraus macht, wenn jemand die Datei zwischendurch
/// speichert.
ImportResult parseTripCsv(String content) {
  final rows = _splitRows(content.replaceFirst('﻿', ''));
  if (rows.isEmpty) return ImportResult.failed('Die Datei ist leer.');

  final header = rows.first.cells;
  if (header.isEmpty || header.first.trim() != dateHeader) {
    return ImportResult.failed(
      'Die erste Spalte muss „$dateHeader" heißen — '
      'am einfachsten mit einer Datei aus dem Export.',
    );
  }

  // Die Notiz-Spalte ist optional; ohne sie sind alle übrigen Spalten
  // Personen.
  final hasNote = header.length > 1 && header.last.trim() == noteHeader;
  final names = [
    for (final cell in header.sublist(1, header.length - (hasNote ? 1 : 0)))
      cell.trim(),
  ];
  if (names.isEmpty) {
    return ImportResult.failed('In der Kopfzeile steht keine einzige Person.');
  }
  if (names.any((n) => n.isEmpty)) {
    return ImportResult.failed('Eine Personen-Spalte hat keine Überschrift.');
  }
  final duplicate = _firstDuplicate(names);
  if (duplicate != null) {
    return ImportResult.failed(
      '„$duplicate" steht zweimal in der Kopfzeile. '
      'Sonst wäre nicht entscheidbar, welche Spalte gilt.',
    );
  }

  final trips = <ImportedTrip>[];
  final problems = <String>[];
  final seenDates = <int, int>{};

  for (final row in rows.skip(1)) {
    final cells = row.cells;
    if (cells.every((c) => c.trim().isEmpty)) continue;

    final date = parseCsvDate(cells.first.trim());
    if (date == null) {
      problems.add(
        'Zeile ${row.line}: „${cells.first.trim()}" ist kein Datum '
        '(erwartet: 31.12.2026).',
      );
      continue;
    }

    final participations = <String, ParticipationStatus>{};
    var broken = false;
    for (var i = 0; i < names.length; i++) {
      final raw = (i + 1 < cells.length ? cells[i + 1] : '').trim();
      if (raw.isEmpty) continue;
      final status = _statusByLabel[raw.toLowerCase()];
      if (status == null) {
        problems.add(
          'Zeile ${row.line}: „$raw" bei ${names[i]} ist unbekannt — '
          'erlaubt sind ${statusLabels.values.join(', ')}.',
        );
        broken = true;
        break;
      }
      participations[names[i]] = status;
    }
    if (broken) continue;

    if (participations.isEmpty) {
      problems.add('Zeile ${row.line}: niemand eingetragen.');
      continue;
    }
    final drivers = participations.values
        .where((s) => s == ParticipationStatus.driver)
        .length;
    if (drivers > 1) {
      problems.add('Zeile ${row.line}: mehr als ein Fahrer.');
      continue;
    }

    // Zwei Zeilen für denselben Tag sind erlaubt (zweites Auto), doppelte
    // Zeilen aber fast immer ein Versehen beim Zusammenkopieren.
    final key = date.year * 10000 + date.month * 100 + date.day;
    final before = seenDates[key];
    if (before != null) {
      problems.add(
        'Zeile ${row.line}: derselbe Tag steht schon in Zeile $before. '
        'Beide werden angelegt — bei einem zweiten Auto ist das richtig.',
      );
    }
    seenDates[key] = row.line;

    final note = hasNote && cells.length > names.length + 1
        ? cells[names.length + 1].trim()
        : '';
    trips.add(
      ImportedTrip(
        line: row.line,
        date: date,
        participations: participations,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  trips.sort((a, b) => a.date.compareTo(b.date));
  return ImportResult(trips: trips, names: names, problems: problems);
}

/// `31.12.2026` wie im Export, zusätzlich `2026-12-31`.
///
/// Beide, weil deutsches Excel beim Speichern gern auf ISO umstellt — die
/// Datei kommt dann anders zurück, als sie herausgegangen ist.
DateTime? parseCsvDate(String value) {
  final german = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(value);
  if (german != null) {
    return _dateOrNull(
      int.parse(german.group(3)!),
      int.parse(german.group(2)!),
      int.parse(german.group(1)!),
    );
  }
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(value);
  if (iso != null) {
    return _dateOrNull(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
    );
  }
  return null;
}

/// `DateTime` rollt Unsinn stillschweigend weiter (32.01. wird 01.02.) —
/// hier soll er stattdessen als Fehler auffallen.
DateTime? _dateOrNull(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String? _firstDuplicate(List<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value.toLowerCase())) return value;
  }
  return null;
}

class _Row {
  const _Row(this.line, this.cells);
  final int line;
  final List<String> cells;
}

/// Zerlegt die Datei in Zeilen und Felder — in einem Durchgang, weil ein
/// Zeilenumbruch innerhalb von Anführungszeichen kein Zeilenende ist.
List<_Row> _splitRows(String content) {
  final rows = <_Row>[];
  final cells = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var line = 1;
  var startLine = 1;

  void endRow() {
    cells.add(field.toString());
    field.clear();
    rows.add(_Row(startLine, [...cells]));
    cells.clear();
    startLine = line;
  }

  for (var i = 0; i < content.length; i++) {
    final char = content[i];
    if (quoted) {
      if (char == '"') {
        // Verdoppeltes Anführungszeichen ist ein echtes Zeichen.
        if (i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        if (char == '\n') line++;
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        quoted = true;
      case ';':
        cells.add(field.toString());
        field.clear();
      case '\r':
        break; // gehört zum CRLF, das \n schließt die Zeile ab
      case '\n':
        line++;
        endRow();
        startLine = line;
      default:
        field.write(char);
    }
  }
  if (field.isNotEmpty || cells.isNotEmpty) endRow();
  return rows;
}
