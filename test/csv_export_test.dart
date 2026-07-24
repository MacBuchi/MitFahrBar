/// Prüft das CSV-Format. Die Fallen stehen alle in der Datei selbst:
/// Trennzeichen, BOM, Zeilenende und Quoting entscheiden darüber, ob die
/// Datei per Doppelklick in deutschem Excel lesbar aufgeht — das merkt man
/// sonst erst auf dem Rechner der Nutzerin.
library;

import 'package:mitfahrbar/core/csv_export.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

Person _person(String id, String name, {bool active = true}) =>
    Person(id: id, name: name, active: active);

Trip _trip(
  String id,
  DateTime date,
  Map<String, ParticipationStatus> participations, {
  String? note,
}) => Trip(id: id, date: date, participations: participations, note: note);

void main() {
  final anna = _person('p1', 'Anna');
  final bernd = _person('p2', 'Bernd');

  List<String> linesOf(String csv) =>
      csv.split('\r\n').where((l) => l.isNotEmpty).toList();

  test('Kopfzeile: Datum, Personen alphabetisch, Notiz zuletzt', () {
    final csv = buildTripCsv(persons: [bernd, anna], trips: const []);
    expect(linesOf(csv).first, '﻿Datum;Anna;Bernd;Notiz');
  });

  test('beginnt mit BOM — sonst zeigt Excel „Ã¤" statt „ä"', () {
    final csv = buildTripCsv(
      persons: [_person('p1', 'Käthe')],
      trips: const [],
    );
    expect(csv.codeUnitAt(0), 0xFEFF);
  });

  test('trennt mit Semikolon und beendet Zeilen mit CRLF', () {
    final csv = buildTripCsv(
      persons: [anna],
      trips: [
        _trip('t1', DateTime(2026, 3, 9), {'p1': ParticipationStatus.driver}),
      ],
    );
    expect(csv, contains('\r\n'));
    expect(csv, isNot(contains(',')));
    expect(linesOf(csv).last, '09.03.2026;Fahrer;');
  });

  test('Status stehen ausgeschrieben, Abwesende bleiben leer', () {
    final carla = _person('p3', 'Carla');
    final csv = buildTripCsv(
      persons: [anna, bernd, carla],
      trips: [
        _trip('t1', DateTime(2026, 3, 9), {
          'p1': ParticipationStatus.driver,
          'p2': ParticipationStatus.passenger,
          'p3': ParticipationStatus.oneWay,
        }),
        _trip('t2', DateTime(2026, 3, 10), {'p1': ParticipationStatus.driver}),
      ],
    );
    final lines = linesOf(csv);
    expect(lines[1], '09.03.2026;Fahrer;Mit;Einfach;');
    // Bernd und Carla waren am 10.03. nicht dabei — leere Zellen, keine
    // Nullen: In der Tabelle soll ein freier Tag auch frei aussehen.
    expect(lines[2], '10.03.2026;Fahrer;;;');
  });

  test('Datum als dd.MM.yyyy, damit Excel es als Datum erkennt', () {
    expect(formatCsvDate(DateTime(2026, 1, 5)), '05.01.2026');
    expect(formatCsvDate(DateTime(2026, 12, 31)), '31.12.2026');
  });

  test('Fahrten stehen aufsteigend, obwohl loadTrips absteigend liefert', () {
    final csv = buildTripCsv(
      persons: [anna],
      trips: [
        _trip('t2', DateTime(2026, 3, 10), const {}),
        _trip('t1', DateTime(2026, 3, 9), const {}),
      ],
    );
    final lines = linesOf(csv);
    expect(lines[1], startsWith('09.03.2026'));
    expect(lines[2], startsWith('10.03.2026'));
  });

  test('Semikolon im Namen zerlegt keine Spalte', () {
    final csv = buildTripCsv(
      persons: [_person('p1', 'Meier; Anna')],
      trips: const [],
    );
    expect(linesOf(csv).first, '﻿Datum;"Meier; Anna";Notiz');
  });

  test('Anführungszeichen in der Notiz werden verdoppelt', () {
    final csv = buildTripCsv(
      persons: const [],
      trips: [
        _trip(
          't1',
          DateTime(2026, 3, 9),
          const {},
          note: 'Umweg über "die Baustelle"',
        ),
      ],
    );
    expect(linesOf(csv).last, '09.03.2026;"Umweg über ""die Baustelle"""');
  });

  test('Zeilenumbruch in der Notiz sprengt die Zeile nicht', () {
    final csv = buildTripCsv(
      persons: const [],
      trips: [
        _trip('t1', DateTime(2026, 3, 9), const {}, note: 'erste\nzweite'),
      ],
    );
    // Zwei echte Zeilen (Kopf + Fahrt), der Umbruch steckt in Anführungs-
    // zeichen und zählt nicht als Datensatz-Ende.
    expect(csv.split('\r\n').where((l) => l.isNotEmpty).length, 2);
    expect(csv, contains('"erste\nzweite"'));
  });

  test('inaktive Personen bleiben Spalten — sonst fehlt die Historie', () {
    final csv = buildTripCsv(
      persons: [anna, _person('p9', 'Zoe', active: false)],
      trips: const [],
    );
    expect(linesOf(csv).first, contains('Zoe'));
  });

  test('ohne Fahrten bleibt genau die Vorlage übrig', () {
    final csv = buildTripCsv(persons: [anna, bernd], trips: const []);
    expect(linesOf(csv), hasLength(1));
  });

  test('Dateiname trägt das Datum, damit Sicherungen nebeneinander liegen', () {
    expect(
      csvFileName(DateTime(2026, 7, 5)),
      'ridebuddy-fahrten-2026-07-05.csv',
    );
  });
}
