/// trip_push_test.dart – Meldungen über geänderte und gelöschte Fahrten
/// (#163).
///
/// Der eigentliche Inhalt ist die Frage, wann NICHTS passieren darf: Eine
/// neu angelegte Fahrt meldet niemandem etwas (das Anlegen ist die
/// Bestätigung), und wer selbst geändert hat, hört von seiner eigenen
/// Änderung nichts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/trip_push.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';

void main() {
  const anna = 'a';
  const bernd = 'b';
  const clara = 'c';

  final persons = <String, Person>{
    anna: const Person(id: anna, name: 'Anna', active: true),
    bernd: const Person(id: bernd, name: 'Bernd', active: true),
    clara: const Person(id: clara, name: 'Clara', active: true),
  };

  // Der Testtag ist ein Dienstag; „jetzt" ist der Donnerstag darauf, damit
  // die Fahrt eine ÄLTERE ist — genau der Fall, für den es #163 gibt.
  final tuesday = DateTime(2026, 7, 28);
  final now = DateTime(2026, 7, 30, 19, 0);

  Trip trip({
    String id = 't1',
    DateTime? date,
    Map<String, ParticipationStatus> participations = const {
      anna: ParticipationStatus.driver,
      bernd: ParticipationStatus.passenger,
    },
  }) => Trip(id: id, date: date ?? tuesday, participations: participations);

  List<OutboxLike> entriesFor({
    required List<Trip> previous,
    required List<Trip> next,
    String? suppress,
    GroupDefaults defaults = const GroupDefaults(),
  }) => [
    for (final entry in tripChangeEntries(
      previous: previous,
      next: next,
      persons: persons,
      now: now,
      defaults: defaults,
      suppressPersonId: suppress,
    ))
      (
        personId: entry.personId,
        title: entry.titleChange,
        body: entry.body,
        kind: entry.kind,
        digest: entry.digest,
      ),
  ];

  test('eine geänderte Fahrt meldet alten UND neuen Beteiligten', () {
    final result = entriesFor(
      previous: [trip()],
      next: [
        trip(
          participations: const {
            anna: ParticipationStatus.driver,
            clara: ParticipationStatus.passenger,
          },
        ),
      ],
    );
    expect(
      result.map((e) => e.personId).toSet(),
      {anna, bernd, clara},
      reason:
          'Bernd ist herausgeflogen — gerade er muss es erfahren. Clara ist '
          'neu dabei und ebenso.',
    );
    expect(
      result.every((e) => e.title == 'Fahrt geändert · Di, 28.07.'),
      isTrue,
    );
    expect(result.every((e) => e.kind == 'trip'), isTrue);
  });

  test('wer herausgeflogen ist, liest es im Text', () {
    final result = entriesFor(
      previous: [trip()],
      next: [
        trip(participations: const {anna: ParticipationStatus.driver}),
      ],
    );
    final berndsMessage = result.singleWhere((e) => e.personId == bernd);
    expect(
      berndsMessage.body,
      contains('nicht mehr eingetragen'),
      reason:
          'Der Text kommt aus composeBody über einen synthetischen '
          'bestätigten Tag — dadurch ergibt sich das von selbst, statt hier '
          'noch einmal formuliert zu werden.',
    );
    final annasMessage = result.singleWhere((e) => e.personId == anna);
    expect(annasMessage.body, contains('Du fährst'));
  });

  test('eine gelöschte Fahrt sagt, dass sie weg ist', () {
    final result = entriesFor(previous: [trip()], next: const []);
    expect(result.map((e) => e.personId).toSet(), {anna, bernd});
    expect(
      result.every((e) => e.title == 'Fahrt entfernt · Di, 28.07.'),
      isTrue,
    );
    expect(result.every((e) => e.body.contains('gelöscht')), isTrue);
  });

  test('eine NEUE Fahrt meldet niemandem etwas', () {
    expect(
      entriesFor(previous: const [], next: [trip()]),
      isEmpty,
      reason:
          'Das Anlegen einer Fahrt IST die Bestätigung des Tages, und wer '
          'beteiligt war, hat es gerade selbst besprochen. Eine Meldung '
          'darüber wäre Lärm — und im Planer stünde sie neben der Fahrt, die '
          'man gerade eingetragen hat.',
    );
  });

  test('unveränderte Fahrten melden nichts', () {
    expect(entriesFor(previous: [trip()], next: [trip()]), isEmpty);
    // Auch eine andere Reihenfolge derselben Teilnahmen ist keine Änderung.
    expect(
      entriesFor(
        previous: [
          trip(
            participations: const {
              anna: ParticipationStatus.driver,
              bernd: ParticipationStatus.passenger,
            },
          ),
        ],
        next: [
          trip(
            participations: const {
              bernd: ParticipationStatus.passenger,
              anna: ParticipationStatus.driver,
            },
          ),
        ],
      ),
      isEmpty,
      reason:
          'Sonst meldete jede Neuladung dieselbe Fahrt als geändert — die '
          'Reihenfolge einer Map sichert niemand zu.',
    );
  });

  test('die eigene Änderung bleibt still — best effort', () {
    final result = entriesFor(
      previous: [trip()],
      next: [
        trip(
          participations: const {
            anna: ParticipationStatus.driver,
            clara: ParticipationStatus.passenger,
          },
        ),
      ],
      suppress: anna,
    );
    expect(result.map((e) => e.personId).toSet(), {bernd, clara});
    expect(
      entriesFor(
        previous: [trip()],
        next: [
          trip(
            participations: const {
              anna: ParticipationStatus.driver,
              clara: ParticipationStatus.passenger,
            },
          ),
        ],
      ).map((e) => e.personId),
      contains(anna),
      reason:
          'Ohne Geräte-Zuordnung wird nichts unterdrückt — sie ist kein '
          'Login (#121), und der stündliche Job kennt sie ohnehin nicht.',
    );
  });

  test('ein verschobenes Datum meldet sich am NEUEN Tag', () {
    final result = entriesFor(
      previous: [trip()],
      next: [trip(date: DateTime(2026, 7, 29))],
    );
    expect(result, isNotEmpty);
    expect(
      result.every((e) => e.title == 'Fahrt geändert · Mi, 29.07.'),
      isTrue,
      reason:
          'Der Stempel nennt, wo die Fahrt jetzt steht. Für eine ältere '
          'Fahrt ist er der einzige Anhaltspunkt, worum es geht — „Heute" '
          'oder „Morgen" trifft hier nie zu.',
    );
  });

  test('die Vorgaben der Gruppe reisen mit', () {
    final result = entriesFor(
      previous: [trip()],
      next: [
        trip(
          participations: const {
            anna: ParticipationStatus.driver,
            bernd: ParticipationStatus.passenger,
            clara: ParticipationStatus.passenger,
          },
        ),
      ],
      defaults: const GroupDefaults(
        outboundTime: DayTime(7, 30),
        meetingPoint: 'Parkplatz Rathaus',
      ),
    );
    expect(
      result.first.body,
      contains('Treffpunkt Parkplatz Rathaus'),
      reason: 'Ein Wortschatz für Banner, Abend-Blick und Fahrt-Meldung.',
    );
  });

  test('eine Fahrt ohne Fahrer behauptet nichts Falsches', () {
    // Fahrten ohne Fahrer gibt es nur aus dem Excel-Import; sie stellen kein
    // Auto. composeBody läse daraus für JEDEN ein „nicht mehr eingetragen".
    final result = entriesFor(
      previous: [
        trip(
          participations: const {
            anna: ParticipationStatus.passenger,
            bernd: ParticipationStatus.passenger,
          },
        ),
      ],
      next: [
        trip(participations: const {anna: ParticipationStatus.passenger}),
      ],
    );
    final annasMessage = result.singleWhere((e) => e.personId == anna);
    expect(annasMessage.body, 'Die Fahrt an diesem Tag wurde geändert.');
  });

  test('unbekannte Personen bekommen keine Zeile', () {
    final result = entriesFor(
      previous: [
        trip(
          participations: const {
            anna: ParticipationStatus.driver,
            'weg': ParticipationStatus.passenger,
          },
        ),
      ],
      next: const [],
    );
    expect(
      result.map((e) => e.personId).toSet(),
      {anna},
      reason:
          'Inaktive und gelöschte Personen stehen nicht in der Personen-Map '
          '— eine Zeile für sie liefe im Schreibweg ohnehin ins Leere.',
    );
  });

  test('derselbe Zustand ergibt denselben Digest', () {
    final once = entriesFor(
      previous: [trip()],
      next: [
        trip(participations: const {anna: ParticipationStatus.driver}),
      ],
    );
    final twice = entriesFor(
      previous: [trip()],
      next: [
        trip(participations: const {anna: ParticipationStatus.driver}),
      ],
    );
    expect(
      once.first.digest,
      twice.first.digest,
      reason:
          'Zwei Geräte sehen dieselbe Änderung und schreiben dieselbe Zeile. '
          'Bei gleichem Digest lässt der Entprell-Trigger die Fälligkeit in '
          'Ruhe — es geht EINE Meldung raus statt zwei.',
    );
  });
}

/// Nur die Felder, um die es hier geht — spart in jedem Test drei Zeilen
/// Zugriffspfad.
typedef OutboxLike = ({
  String personId,
  String title,
  String body,
  String kind,
  String digest,
});
