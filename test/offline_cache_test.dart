/// offline_cache_test.dart – Der letzte bekannte Stand (#169).
///
/// Der Kern steht in der Gruppe „Was NICHT zwischengespeichert wird": Ein
/// Zwischenspeicher, der auch Schreibzugriffe abfängt oder berechnete Zahlen
/// hält, wäre kein Komfort mehr, sondern eine zweite Wahrheit.
library;

import 'dart:async';

import 'package:mitfahrbar/core/widgets/offline_bar.dart';
import 'package:mitfahrbar/data/caching_repository.dart';
import 'package:mitfahrbar/data/carpool_repository.dart';
import 'package:mitfahrbar/data/group_repository.dart';
import 'package:mitfahrbar/data/fake_repository.dart';
import 'package:mitfahrbar/data/offline_cache.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_backend.dart';

/// Ein Repository, das auf Kommando kein Netz hat — oder eines, das hängt.
///
/// Beides ist nicht dasselbe, und der Unterschied ist der Grund für #232: Im
/// Flugmodus scheitert eine Anfrage sofort, im Funkloch läuft sie in den
/// Timeout der Plattform. [hold] ist der zweite Fall.
class _Switchable implements GroupRepository {
  _Switchable(this.group);

  Group? group;
  bool offline = false;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<Group?> myGroup() async {
    calls++;
    await hold?.future;
    if (offline) throw Exception('SocketException: kein Netz');
    return group;
  }
}

/// Wie [FakeCarpoolRepository], nur dass das Laden der Fahrten hängen kann.
class _SlowTrips extends FakeCarpoolRepository {
  Completer<void>? hold;

  @override
  Future<List<Trip>> loadTrips() async {
    await hold?.future;
    return super.loadTrips();
  }
}

const _group = Group(
  id: 'g1',
  name: 'Dacia Racing',
  handle: 'daciaracing',
  status: GroupStatus.active,
);

void main() {
  group('Der Stand überlebt den Netzausfall', () {
    test('erst vom Server, dann aus dem Speicher — mit Zeitpunkt', () async {
      final cache = InMemoryOfflineCache(
        clock: () => DateTime(2026, 8, 5, 7, 12),
      );
      final status = OfflineStatus();
      final inner = _Switchable(_group);
      final repo = CachingGroupRepository(inner, cache, status, () => 'g1');

      expect((await repo.myGroup())!.name, 'Dacia Racing');
      expect(status.notifier.value, isNull, reason: 'frisch vom Server');

      inner.offline = true;
      final offline = await repo.myGroup();

      expect(offline!.name, 'Dacia Racing');
      expect(status.notifier.value, DateTime(2026, 8, 5, 7, 12));
    });

    test('ohne vorherigen Besuch bleibt der Fehler ein Fehler', () async {
      final inner = _Switchable(_group)..offline = true;
      final repo = CachingGroupRepository(
        inner,
        InMemoryOfflineCache(),
        OfflineStatus(),
        () => 'g1',
      );
      // Nichts zu zeigen heißt: der Schirm aus v0.60.0, nicht eine Lüge.
      await expectLater(repo.myGroup(), throwsA(isA<Exception>()));
    });

    test('ein Treffer aus dem Speicher altert nicht nach', () async {
      var now = DateTime(2026, 8, 5, 7, 12);
      final cache = InMemoryOfflineCache(clock: () => now);
      final status = OfflineStatus();
      final inner = _Switchable(_group);
      final repo = CachingGroupRepository(inner, cache, status, () => 'g1');

      await repo.myGroup();
      inner.offline = true;
      now = DateTime(2026, 8, 5, 19, 0);
      await repo.myGroup();
      await repo.myGroup();

      // Der Zeitstempel bleibt der des letzten ECHTEN Abrufs. Frischte ein
      // Treffer ihn auf, stünde in der Leiste ewig „gerade eben" über einem
      // Stand von heute früh.
      expect(status.notifier.value, DateTime(2026, 8, 5, 7, 12));
    });

    test('ohne Gruppenkennung wird nichts abgelegt', () async {
      final cache = InMemoryOfflineCache();
      final inner = _Switchable(_group);
      final repo = CachingGroupRepository(
        inner,
        cache,
        OfflineStatus(),
        () => null,
      );

      await repo.myGroup();
      expect(cache.entries, isEmpty);
    });

    test('eine andere Gruppe sieht die Zeilen der ersten nie', () async {
      final cache = InMemoryOfflineCache();
      var groupId = 'g1';
      final inner = _Switchable(_group);
      final repo = CachingGroupRepository(
        inner,
        cache,
        OfflineStatus(),
        () => groupId,
      );

      await repo.myGroup();
      groupId = 'g2';
      inner.offline = true;

      // Die Mandantentrennung der RLS, auf dem Gerät nachgezogen: Ein
      // geteiltes Handy darf nicht die Fahrten der vorigen Gruppe zeigen.
      await expectLater(repo.myGroup(), throwsA(isA<Exception>()));

      // Und die alten Zeilen sind nicht bloß unsichtbar, sondern weg —
      // aufgeräumt hat das der Lesezugriff selbst, nicht ein Abmelde-Haken.
      expect(cache.entries, isEmpty);
    });
  });

  group('Zuerst der Speicher, dann das Netz (#232)', () {
    late RefreshSignal signal;

    setUp(() => signal = RefreshSignal());
    tearDown(() => signal.dispose());

    test('der erste Lesezugriff wartet nicht auf die Antwort', () async {
      final cache = InMemoryOfflineCache(
        clock: () => DateTime(2026, 8, 5, 7, 12),
      );
      final inner = _Switchable(_group);
      // Einmal mit Empfang öffnen — das füllt den Speicher.
      await CachingGroupRepository(
        inner,
        cache,
        OfflineStatus(),
        () => 'g1',
        refresh: signal,
      ).myGroup();

      // Und jetzt der gemeldete Fall: Das Netz ist da, antwortet aber nicht.
      // Bis v0.79.0 hing der Start genau so lange, wie die Anfrage brauchte,
      // um aufzugeben.
      inner.hold = Completer<void>();
      final status = OfflineStatus();
      final cold = CachingGroupRepository(
        inner,
        cache,
        status,
        () => 'g1',
        refresh: signal,
      );

      final group = await cold.myGroup().timeout(const Duration(seconds: 1));

      expect(group!.name, 'Dacia Racing');
      expect(status.notifier.value, DateTime(2026, 8, 5, 7, 12));
      inner.hold!.complete();
    });

    test('genau eine Abholung, danach wieder das Netz', () async {
      final cache = InMemoryOfflineCache();
      final inner = _Switchable(_group);
      await CachingGroupRepository(
        inner,
        cache,
        OfflineStatus(),
        () => 'g1',
        refresh: signal,
      ).myGroup();

      final repo = CachingGroupRepository(
        inner,
        cache,
        OfflineStatus(),
        () => 'g1',
        refresh: signal,
      );
      expect((await repo.myGroup())!.name, 'Dacia Racing');

      // Die Auffrischung im Hintergrund läuft durch, und erst danach
      // benennt sich die Gruppe um.
      await pumpEventQueue();
      inner.group = const Group(
        id: 'g1',
        name: 'Rallye Team',
        handle: 'daciaracing',
        status: GroupStatus.active,
      );

      expect(
        (await repo.myGroup())!.name,
        'Dacia Racing',
        reason:
            'die Abholung dessen, was eben eingetroffen ist — sonst fragte '
            'der vom Signal ausgelöste Lesezugriff dieselbe Zeile ein '
            'zweites Mal beim Server ab',
      );
      expect(
        (await repo.myGroup())!.name,
        'Rallye Team',
        reason:
            'ab hier fragt jeder Lesezugriff wieder das Netz zuerst — sonst '
            'lieferte „Erneut versuchen" den Stand zurück, den zu ersetzen '
            'sein Zweck ist',
      );
    });

    test(
      'nach einem Schreibzugriff kommt nichts mehr aus dem Speicher',
      () async {
        final cache = InMemoryOfflineCache();
        final inner = _SlowTrips();
        CachingCarpoolRepository layer() => CachingCarpoolRepository(
          inner,
          cache,
          OfflineStatus(),
          () => 'g1',
          refresh: signal,
        );
        await layer().loadTrips();

        // Ohne Schreibzugriff steht der Stand sofort da, auch wenn das Netz
        // hängt — die Gegenprobe zum eigentlichen Fall.
        inner.hold = Completer<void>();
        await expectLater(
          layer().loadTrips().timeout(const Duration(milliseconds: 200)),
          completion(isEmpty),
        );
        inner.hold!.complete();
        inner.hold = null;

        final wrote = layer();
        await wrote.createPerson(
          const Person(id: '', name: 'Anna', active: true),
        );
        inner.hold = Completer<void>();

        // Ab dem ersten erfolgreichen Schreibzugriff ist der abgelegte Stand
        // möglicherweise überholt. Ein Schirm, der danach zum ersten Mal
        // aufgeht, zeigt lieber einen Ladekreis als die eigene Eingabe von
        // vorhin — sonst sähe die Nutzerin sie zurückspringen.
        await expectLater(
          wrote.loadTrips().timeout(const Duration(milliseconds: 200)),
          throwsA(isA<TimeoutException>()),
        );
        inner.hold!.complete();
      },
    );

    test('ein Schwall meldet sich einmal, nicht achtmal', () async {
      var beeps = 0;
      final signal = RefreshSignal(window: const Duration(milliseconds: 10));
      addTearDown(signal.dispose);
      signal.addListener(() => beeps++);

      for (var i = 0; i < 8; i++) {
        signal.ping();
      }
      expect(beeps, 0, reason: 'gesammelt wird, bevor gemeldet wird');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beeps, 1);

      // Und der nächste Schwall meldet sich wieder.
      signal.ping();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beeps, 2);
    });
  });

  group('Was NICHT zwischengespeichert wird', () {
    late FakeBackend backend;
    late CachingCarpoolRepository repo;
    late InMemoryOfflineCache cache;

    setUp(() async {
      backend = FakeBackend();
      final groupId = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      cache = InMemoryOfflineCache();
      repo = CachingCarpoolRepository(
        backend.dataFor(groupId),
        cache,
        OfflineStatus(),
        () => groupId,
      );
    });

    tearDown(() => backend.dispose());

    test('Schreiben legt nichts ab und fällt auf nichts zurück', () async {
      await repo.createPerson(const Person(id: '', name: 'Anna', active: true));
      await repo.saveSettings(const AppSettings());

      // Kein Eintrag aus einem Schreibzugriff: Der Speicher ist ein
      // Gedächtnis für Gelesenes, keine Warteschlange für Ungesendetes.
      // Ein „später hochschieben" wäre ein eigenes Vorhaben mit einer
      // eigenen Antwort auf gleichzeitige Änderungen.
      expect(cache.entries.keys, isNot(contains(contains('createPerson'))));
      expect(cache.entries.keys.every((k) => !k.contains('save')), isTrue);
    });

    test('gespeichert werden Zeilen, keine Kennzahlen', () async {
      await repo.createPerson(const Person(id: '', name: 'Anna', active: true));
      await repo.loadPersons();
      await repo.loadTrips();

      final keys = cache.entries.keys.toList();
      // Punkte, Quote, Ersparnis und der vorgeschlagene Fahrer entstehen
      // weiter in fairness.dart aus diesen Zeilen. Läge eine davon hier,
      // gäbe es zwei Wahrheiten über dieselbe Woche.
      for (final forbidden in ['stats', 'ranking', 'points', 'driver']) {
        expect(
          keys.any((k) => k.contains(forbidden)),
          isFalse,
          reason: '„$forbidden" gehört nicht in den Zwischenspeicher',
        );
      }
      expect(keys.any((k) => k.endsWith('.persons')), isTrue);
    });
  });

  group('Die Zeilen überstehen den Rundlauf', () {
    test('Gruppe', () {
      final back = Group.fromJson(_group.toJson());
      expect(back.id, _group.id);
      expect(back.handle, _group.handle);
      expect(back.status, GroupStatus.active);
    });

    test('Wochenplan mit 1-way und Übersteuerung', () {
      final plan = WeekPlan(
        availability: {
          DateTime(2026, 8, 5): {'a': PlanRide.full, 'b': PlanRide.oneWay},
        },
        overrides: {
          DateTime(2026, 8, 5): {'a'},
        },
      );

      final back = WeekPlan.fromJson(plan.toJson());
      expect(back.availability[DateTime(2026, 8, 5)]!['b'], PlanRide.oneWay);
      expect(back.overrides[DateTime(2026, 8, 5)], {'a'});
    });

    test('ein unbekannter Wert macht den Speicher nicht unbrauchbar', () {
      final back = WeekPlan.fromJson({
        'availability': {
          '2026-08-05': {'a': 'irgendwas-neues'},
        },
        'overrides': <String, dynamic>{},
      });
      // Tolerant lesen statt werfen — dieselbe Linie wie Group.statusFrom.
      expect(back.availability[DateTime(2026, 8, 5)]!['a'], PlanRide.full);
    });

    test('Fahrten behalten ihre Teilnahmen', () {
      final trip = Trip(
        id: 't1',
        date: DateTime(2026, 8, 4),
        participations: const {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.oneWay,
        },
      );
      final back = Trip.fromJson(trip.toJson());
      expect(back.participations['a'], ParticipationStatus.driver);
      expect(back.participations['b'], ParticipationStatus.oneWay);
    });
  });

  group('Der Zeitpunkt in der Leiste', () {
    final now = DateTime(2026, 8, 5, 19, 30);

    test('heute nennt nur die Uhrzeit', () {
      expect(describeStamp(DateTime(2026, 8, 5, 7, 12), now), 'heute 07:12');
    });

    test('gestern wird benannt', () {
      expect(describeStamp(DateTime(2026, 8, 4, 18, 40), now), 'gestern 18:40');
    });

    test('ab vorgestern steht das Datum dabei', () {
      // Ohne Datum läse sich ein zwei Tage alter Stand wie ein heutiger.
      expect(describeStamp(DateTime(2026, 8, 3, 18, 40), now), '03.08. 18:40');
    });
  });
}
