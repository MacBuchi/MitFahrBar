/// csv_import_test.dart – Einlesen der Export-CSV.
///
/// Der wichtigste Test ist der Rundlauf: Was `buildTripCsv` schreibt, muss
/// `parseTripCsv` unverändert zurückgeben. Driften die beiden auseinander,
/// ist die Vorlage aus dem Export keine Vorlage mehr.
library;

import 'package:fahrgemeinschaft/core/csv_export.dart';
import 'package:fahrgemeinschaft/core/csv_import.dart';
import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

String csv(List<String> lines) => '${lines.join('\r\n')}\r\n';

void main() {
  group('Rundlauf mit dem Export', () {
    test('was exportiert wurde, kommt unverändert zurück', () {
      const persons = [
        Person(id: 'p1', name: 'Anna', active: true),
        Person(id: 'p2', name: 'Bernd', active: true),
        Person(id: 'p3', name: 'Carla', active: false),
      ];
      final trips = [
        Trip(
          id: 't1',
          date: DateTime(2026, 3, 9),
          participations: const {
            'p1': ParticipationStatus.driver,
            'p2': ParticipationStatus.passenger,
            'p3': ParticipationStatus.oneWay,
          },
          note: 'Umweg über "die Baustelle"; zäh',
        ),
        Trip(
          id: 't2',
          date: DateTime(2026, 3, 10),
          participations: const {'p2': ParticipationStatus.driver},
        ),
      ];

      final result = parseTripCsv(buildTripCsv(persons: persons, trips: trips));

      expect(result.problems, isEmpty);
      expect(result.names, ['Anna', 'Bernd', 'Carla']);
      expect(result.trips, hasLength(2));

      final first = result.trips.first;
      expect(first.date, DateTime(2026, 3, 9));
      expect(first.participations, {
        'Anna': ParticipationStatus.driver,
        'Bernd': ParticipationStatus.passenger,
        'Carla': ParticipationStatus.oneWay,
      });
      expect(
        first.note,
        'Umweg über "die Baustelle"; zäh',
        reason:
            'Anführungszeichen und Semikolon müssen den Rundlauf '
            'überstehen — sonst zerlegt die Notiz die Zeile.',
      );
      expect(result.trips.last.participations, {
        'Bernd': ParticipationStatus.driver,
      });
    });

    test('die leere Vorlage liefert die Namen, aber keine Fahrten', () {
      final template = buildTripCsv(
        persons: const [
          Person(id: 'p1', name: 'Anna', active: true),
          Person(id: 'p2', name: 'Bernd', active: true),
        ],
        trips: const [],
      );
      final result = parseTripCsv(template);

      expect(result.names, ['Anna', 'Bernd']);
      expect(result.trips, isEmpty);
      expect(result.problems, isEmpty);
    });
  });

  group('Formatvarianten, die von außen kommen', () {
    test('ohne BOM und mit reinen LF-Zeilenenden', () {
      final result = parseTripCsv('Datum;Anna;Notiz\n09.03.2026;Fahrer;\n');
      expect(result.problems, isEmpty);
      expect(result.trips.single.participations, {
        'Anna': ParticipationStatus.driver,
      });
    });

    test('ohne Notiz-Spalte', () {
      final result = parseTripCsv(csv(['Datum;Anna', '09.03.2026;Fahrer']));
      expect(result.names, ['Anna']);
      expect(result.trips.single.note, isNull);
    });

    test('ISO-Datum, weil Excel beim Speichern umstellt', () {
      final result = parseTripCsv(csv(['Datum;Anna', '2026-03-09;Fahrer']));
      expect(result.trips.single.date, DateTime(2026, 3, 9));
    });

    test('Groß- und Kleinschreibung der Status ist egal', () {
      final result = parseTripCsv(
        csv(['Datum;Anna;Bernd', '09.03.2026;FAHRER;mit']),
      );
      expect(result.problems, isEmpty);
      expect(result.trips.single.participations, {
        'Anna': ParticipationStatus.driver,
        'Bernd': ParticipationStatus.passenger,
      });
    });

    test('Leerzeilen werden übergangen, nicht bemängelt', () {
      final result = parseTripCsv(
        csv(['Datum;Anna', '', '09.03.2026;Fahrer', ';']),
      );
      expect(result.trips, hasLength(1));
      expect(result.problems, isEmpty);
    });

    test('fehlende Spalten am Zeilenende gelten als „nicht dabei"', () {
      // Manche Tabellenprogramme schneiden leere Felder am Ende ab.
      final result = parseTripCsv(
        csv(['Datum;Anna;Bernd', '09.03.2026;Fahrer']),
      );
      expect(result.trips.single.participations, {
        'Anna': ParticipationStatus.driver,
      });
    });
  });

  group('Kopfzeile', () {
    test('ohne „Datum" als erste Spalte geht gar nichts', () {
      final result = parseTripCsv(csv(['Tag;Anna', '09.03.2026;Fahrer']));
      expect(result.trips, isEmpty);
      expect(result.problems.single, contains('Datum'));
    });

    test('ohne eine einzige Person auch nicht', () {
      final result = parseTripCsv(csv(['Datum;Notiz', '09.03.2026;']));
      expect(result.problems.single, contains('keine einzige Person'));
    });

    test('zwei gleiche Namen sind nicht auflösbar', () {
      // Sonst müsste geraten werden, welche Spalte gilt — und die Punkte
      // hingen an einem Rateergebnis.
      final result = parseTripCsv(
        csv(['Datum;Anna;Anna;Notiz', '09.03.2026;Fahrer;Mit;']),
      );
      expect(result.trips, isEmpty);
      expect(result.problems.single, contains('zweimal'));
    });

    test('eine namenlose Spalte ebenfalls nicht', () {
      final result = parseTripCsv(csv(['Datum;Anna;;Notiz']));
      expect(result.problems.single, contains('keine Überschrift'));
    });

    test('eine leere Datei sagt das', () {
      expect(parseTripCsv('').problems.single, contains('leer'));
    });
  });

  group('krumme Zeilen', () {
    test('eine kaputte Zeile stoppt die anderen nicht', () {
      final result = parseTripCsv(
        csv([
          'Datum;Anna',
          '09.03.2026;Fahrer',
          'kein-datum;Fahrer',
          '11.03.2026;Fahrer',
        ]),
      );
      expect(
        result.trips,
        hasLength(2),
        reason: 'Eine krumme Zeile in der Mitte darf nicht 200 gute kosten.',
      );
      expect(result.problems.single, contains('Zeile 3'));
    });

    test('ein unbekannter Status wird benannt, nicht verschluckt', () {
      final result = parseTripCsv(csv(['Datum;Anna', '09.03.2026;Beifahrer']));
      expect(result.trips, isEmpty);
      expect(result.problems.single, contains('Beifahrer'));
      expect(result.problems.single, contains('Fahrer'));
    });

    test('zwei Fahrer an einem Tag können nicht stimmen', () {
      final result = parseTripCsv(
        csv(['Datum;Anna;Bernd', '09.03.2026;Fahrer;Fahrer']),
      );
      expect(result.trips, isEmpty);
      expect(result.problems.single, contains('mehr als ein Fahrer'));
    });

    test('eine Zeile ohne jede Teilnahme ist keine Fahrt', () {
      final result = parseTripCsv(csv(['Datum;Anna;Notiz', '09.03.2026;;nix']));
      expect(result.trips, isEmpty);
      expect(result.problems.single, contains('niemand'));
    });

    test('derselbe Tag zweimal wird angemerkt, aber übernommen', () {
      // Zwei Autos an einem Tag sind erlaubt; ein Doppel beim Kopieren
      // ist häufiger — deshalb Hinweis statt Ablehnung.
      final result = parseTripCsv(
        csv(['Datum;Anna', '09.03.2026;Fahrer', '09.03.2026;Fahrer']),
      );
      expect(result.trips, hasLength(2));
      expect(result.problems.single, contains('schon in Zeile 2'));
    });

    test('Fahrten kommen aufsteigend zurück, egal wie sie dastanden', () {
      final result = parseTripCsv(
        csv(['Datum;Anna', '11.03.2026;Fahrer', '09.03.2026;Fahrer']),
      );
      expect([for (final t in result.trips) t.date.day], [9, 11]);
    });
  });

  group('parseCsvDate', () {
    test('deutsches und ISO-Format', () {
      expect(parseCsvDate('09.03.2026'), DateTime(2026, 3, 9));
      expect(parseCsvDate('9.3.2026'), DateTime(2026, 3, 9));
      expect(parseCsvDate('2026-03-09'), DateTime(2026, 3, 9));
    });

    test('Unsinn rollt nicht weiter, sondern fällt auf', () {
      // DateTime(2026, 1, 32) wäre stillschweigend der 1. Februar.
      expect(parseCsvDate('32.01.2026'), isNull);
      expect(parseCsvDate('29.02.2026'), isNull, reason: 'kein Schaltjahr');
      expect(parseCsvDate('09.13.2026'), isNull);
      expect(parseCsvDate(''), isNull);
      expect(parseCsvDate('09/03/2026'), isNull);
    });
  });
}
