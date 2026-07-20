/// csv_export.dart – Fahrten als CSV, wie sie deutsches Excel erwartet.
///
/// Reine Aufbereitung, kein Datei-Zugriff: Das Schreiben liegt in
/// `export_file.dart`, damit das Format hier ohne Plattform testbar bleibt
/// (dieselbe Trennung wie `chart_data.dart` ↔ `widgets/charts.dart`).
///
/// Der Export ist zugleich die Import-Vorlage: echte Spaltennamen, echte
/// Struktur, echte Beispielzeilen. Deshalb gibt es keinen zweiten Generator
/// für ein Template.
library;

import '../models/person.dart';
import '../models/trip.dart';

/// Trennzeichen. Deutsches Excel erwartet `;` — mit `,` landet die ganze
/// Zeile in einer einzigen Spalte.
const _separator = ';';

/// Excel bricht Zeilen nur an CRLF sauber um.
const _lineEnd = '\r\n';

/// Ohne BOM liest Excel die Datei als Latin-1 und macht aus „ä" ein „Ã¤".
const _bom = '﻿';

/// Wie ein Teilnahme-Status in der Tabelle steht. Bewusst ausgeschriebene
/// Wörter statt Kürzel: Die Datei soll ohne Legende verständlich sein.
const statusLabels = {
  ParticipationStatus.driver: 'Fahrer',
  ParticipationStatus.passenger: 'Mit',
  ParticipationStatus.oneWay: 'Einfach',
};

/// Spaltenüberschriften der festen Spalten.
const dateHeader = 'Datum';
const noteHeader = 'Notiz';

/// Baut die CSV: eine Zeile je Fahrt, eine Spalte je Person.
///
/// Das Raster spiegelt die Excel-Tabelle, aus der die Gruppe kommt, und ist
/// von Hand befüllbar — anders als eine Zeile je Teilnahme.
///
/// [persons] kommt vollständig in die Kopfzeile, auch inaktive Personen und
/// solche ohne Fahrt: Sonst verlöre ein Export als Sicherung genau die
/// Personen, die zuletzt nicht mitgefahren sind.
///
/// Fahrten stehen aufsteigend nach Datum — in der Tabelle liest sich die
/// Historie von oben nach unten, während `loadTrips` für die Liste in der
/// App absteigend liefert.
String buildTripCsv({
  required List<Person> persons,
  required List<Trip> trips,
}) {
  final columns = [...persons]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final rows = [...trips]..sort((a, b) => a.date.compareTo(b.date));

  final buffer = StringBuffer(_bom);
  buffer.write(
    [
      dateHeader,
      for (final p in columns) _escape(p.name),
      noteHeader,
    ].join(_separator),
  );
  buffer.write(_lineEnd);

  for (final trip in rows) {
    buffer.write(
      [
        formatCsvDate(trip.date),
        for (final p in columns)
          _escape(statusLabels[trip.participations[p.id]] ?? ''),
        _escape(trip.note ?? ''),
      ].join(_separator),
    );
    buffer.write(_lineEnd);
  }

  return buffer.toString();
}

/// `dd.MM.yyyy` — das Format, das deutsches Excel als Datum erkennt statt
/// als Text. Bewusst ohne `intl`: Die Datei hat ein festes Format, kein
/// gebietsschema-abhängiges.
String formatCsvDate(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d.$m.${date.year}';
}

/// Dateiname mit Datum, damit mehrere Sicherungen nebeneinander liegen.
String csvFileName(DateTime today) =>
    'ridebuddy-fahrten-${today.year}-'
    '${today.month.toString().padLeft(2, '0')}-'
    '${today.day.toString().padLeft(2, '0')}.csv';

/// CSV-Quoting: Nur wenn nötig, dann nach RFC 4180 (Anführungszeichen
/// verdoppeln). Namen dürfen Semikola enthalten — ungeschützt zerlegt das
/// eine einzelne Person in zwei Spalten.
String _escape(String value) {
  if (!value.contains(_separator) &&
      !value.contains('"') &&
      !value.contains('\n') &&
      !value.contains('\r')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
