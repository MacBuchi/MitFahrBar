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

import '../models/app_settings.dart';
import '../models/group_defaults.dart';
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
///
/// Der Import liest ausschließlich den Inhalt, nie den Namen — ältere
/// `ridebuddy-fahrten-*.csv` (bis v0.41.0, #117) bleiben also lesbar.
String csvFileName(DateTime today) =>
    'mitfahrbar-fahrten-${today.year}-'
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

/// Spaltenüberschriften der Parameter-Datei. Der Schlüssel ist die **Kennung
/// aus der Datenbank**, nicht die deutsche Beschriftung: Die Beschriftung darf
/// sich ändern, ohne dass eine alte Sicherung unlesbar wird.
const settingsKeyHeader = 'Parameter';
const settingsValueHeader = 'Wert';
const settingsLabelHeader = 'Bedeutung';

/// Was die Parameter-Datei trägt — genau die Werte des Parameter-Screens.
///
/// **`one_way_factor` und `points_weight` stehen bewusst NICHT darin**, obwohl
/// sie in derselben Tabelle liegen. Es ist dasselbe Kriterium, an dem auch der
/// Screen sie auslässt: Sie verschieben rückwirkend die Punkte *aller*. Eine
/// CSV wäre sonst genau die Hintertür, die der Screen nicht sein will — und
/// zwar eine, die niemand sieht, weil eine Datei zwischen zwei Geräten wandert.
/// Verloren geht dabei nichts: Beide werden per Migration gesetzt, nicht von
/// Hand, und eine frische Gruppe bekommt sie aus den Vorgaben.
const settingsLabels = <String, String>{
  'commute_km': 'Arbeitsweg einfach (km)',
  'diesel_price_per_liter': 'Diesel (EUR/l)',
  'petrol_price_per_liter': 'Super E5 (EUR/l)',
  'e10_price_per_liter': 'Super E10 (EUR/l)',
  'electricity_price_per_kwh': 'Hausstrom (EUR/kWh)',
  'charging_price_per_kwh': 'Ladestrom (EUR/kWh)',
  'car_assignment_enabled': 'Auto-Zuordnung (1 = an, 0 = aus)',
  'outbound_time': 'Abfahrt hin (hh:mm)',
  'return_time': 'Abfahrt zurück (hh:mm)',
  'meeting_point': 'Treffpunkt',
};

/// Die Parameter als CSV — zugleich die Vorlage für den Import.
///
/// Nicht gepflegte Vorgaben (keine Zeile in `group_defaults`) stehen mit
/// leerem Wert da statt zu fehlen: Eine Vorlage, die nur die gesetzten Felder
/// zeigt, verrät nicht, welche es überhaupt gibt.
String buildSettingsCsv({
  required AppSettings settings,
  required GroupDefaults defaults,
}) {
  final values = <String, String>{
    'commute_km': _number(settings.commuteKm),
    'diesel_price_per_liter': _number(settings.dieselPricePerLiter),
    'petrol_price_per_liter': _number(settings.petrolPricePerLiter),
    'e10_price_per_liter': _number(settings.e10PricePerLiter),
    'electricity_price_per_kwh': _number(settings.electricityPricePerKwh),
    'charging_price_per_kwh': _number(settings.chargingPricePerKwh),
    'car_assignment_enabled': settings.carAssignmentEnabled ? '1' : '0',
    'outbound_time': defaults.outboundTime?.format() ?? '',
    'return_time': defaults.returnTime?.format() ?? '',
    'meeting_point': defaults.meetingPoint ?? '',
  };

  final buffer = StringBuffer(_bom);
  buffer.write(
    [
      settingsKeyHeader,
      settingsValueHeader,
      settingsLabelHeader,
    ].join(_separator),
  );
  buffer.write(_lineEnd);
  for (final entry in settingsLabels.entries) {
    buffer.write(
      [
        entry.key,
        _escape(values[entry.key] ?? ''),
        _escape(entry.value),
      ].join(_separator),
    );
    buffer.write(_lineEnd);
  }
  return buffer.toString();
}

/// Zahl mit **Dezimalkomma**: Deutsches Excel liest `1.70` als Text und
/// zeigt in der Spalte plötzlich linksbündige Zeichenketten. Der Import liest
/// beide Schreibweisen — eine von Hand getippte Datei trägt oft den Punkt.
String _number(double value) {
  final text = value == value.roundToDouble() && value.abs() < 1e15
      ? value.toStringAsFixed(value.abs() < 10 ? 2 : 0)
      : value.toString();
  return text.replaceAll('.', ',');
}

/// **Es gibt bewusst keine Datei mit den Wochenwerten des Archivs.** Sie
/// stehen unter CC BY-NC-SA; die ShareAlike-Klausel greift bei Weitergabe,
/// und eine Datei, die man weiterreichen kann, ist genau das. Die Zusage des
/// Projekts ist, dass die Werte die Gruppendatenbank nicht verlassen —
/// `test/price_archive_license_test.dart` erzwingt sie, Begründung in
/// `doc/entscheidung-preisarchiv-lizenz.md`. Verloren ist dadurch nichts: Der
/// nächtliche Nachfüll-Lauf sucht sich „Woche mit Fahrt ohne vollständige
/// Preiszeilen" und holt sie aus dem Archiv zurück.
///
/// Die Kraftstoff-Konstanten der Parameter-Datei sind davon unberührt — das
/// sind die Zahlen, die die Gruppe selbst eingetippt hat, keine Archivwerte.
///
/// Dateiname der Beilage — dasselbe Muster wie [csvFileName], damit die
/// beiden Dateien einer Sicherung nebeneinander stehen.
String settingsCsvFileName(DateTime today) => _dated('parameter', today);

String _dated(String kind, DateTime today) =>
    'mitfahrbar-$kind-${today.year}-'
    '${today.month.toString().padLeft(2, '0')}-'
    '${today.day.toString().padLeft(2, '0')}.csv';
