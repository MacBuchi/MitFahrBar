import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/models/app_settings.dart';

PriceSample sample(
  String station, {
  double? e5,
  double? e10,
  double? diesel,
  int day = 1,
}) => PriceSample(
  capturedAt: DateTime.utc(2026, 6, day, 7),
  stationId: station,
  e5: e5,
  e10: e10,
  diesel: diesel,
);

void main() {
  group('IsoWeek', () {
    test('ordnet Jahreswechsel nach ISO zu, nicht nach Kalenderjahr', () {
      // Sonntag: gehört noch in die letzte Woche des Vorjahres.
      expect(IsoWeek.of(DateTime.utc(2023, 1, 1)), const IsoWeek(2022, 52));
      // Freitag: 2020 hatte 53 Wochen.
      expect(IsoWeek.of(DateTime.utc(2021, 1, 1)), const IsoWeek(2020, 53));
      // Donnerstag: erster Donnerstag im Jahr, also Woche 1.
      expect(IsoWeek.of(DateTime.utc(2026, 1, 1)), const IsoWeek(2026, 1));
    });

    test('monday liefert den Wochenanfang, auch über den Jahreswechsel', () {
      expect(const IsoWeek(2026, 1).monday, DateTime.utc(2025, 12, 29));
      expect(const IsoWeek(2020, 53).monday, DateTime.utc(2020, 12, 28));
    });

    test('of und monday sind zueinander invers', () {
      for (final week in weeksBetween(
        const IsoWeek(2025, 50),
        const IsoWeek(2026, 10),
      )) {
        expect(IsoWeek.of(week.monday), week);
      }
    });

    test('eine Zeitumstellung verschiebt keine Woche', () {
      // Lokale Zeit am Tag der Sommerzeit-Umstellung (letzter Sonntag im
      // März): Ohne UTC-Rechnung landet der Tag in der Nachbarwoche.
      expect(
        IsoWeek.of(DateTime(2026, 3, 29, 2, 30)),
        IsoWeek.of(DateTime.utc(2026, 3, 29)),
      );
    });
  });

  group('weeksBetween', () {
    test('schließt beide Enden ein und lässt keine Lücke', () {
      final weeks = weeksBetween(
        const IsoWeek(2026, 1),
        const IsoWeek(2026, 4),
      );
      expect(weeks, const [
        IsoWeek(2026, 1),
        IsoWeek(2026, 2),
        IsoWeek(2026, 3),
        IsoWeek(2026, 4),
      ]);
    });

    test('läuft über ein 53-Wochen-Jahr hinweg', () {
      final weeks = weeksBetween(
        const IsoWeek(2020, 52),
        const IsoWeek(2021, 2),
      );
      expect(weeks, const [
        IsoWeek(2020, 52),
        IsoWeek(2020, 53),
        IsoWeek(2021, 1),
        IsoWeek(2021, 2),
      ]);
    });

    test('verkehrte Reihenfolge liefert leer statt Endlosschleife', () {
      expect(
        weeksBetween(const IsoWeek(2026, 5), const IsoWeek(2026, 1)),
        isEmpty,
      );
    });
  });

  group('percentile', () {
    test('interpoliert zwischen den Rangwerten', () {
      expect(percentile([1, 2, 3, 4, 5], 0.1), closeTo(1.4, 1e-9));
      expect(percentile([1, 2, 3, 4, 5], 0.5), closeTo(3.0, 1e-9));
      expect(percentile([1, 2, 3, 4, 5], 0.0), closeTo(1.0, 1e-9));
      expect(percentile([1, 2, 3, 4, 5], 1.0), closeTo(5.0, 1e-9));
    });

    test(
      'ist von der Eingabereihenfolge unabhängig und verändert sie nicht',
      () {
        final values = [3.0, 1.0, 2.0];
        expect(percentile(values, 0.5), closeTo(2.0, 1e-9));
        expect(values, [3.0, 1.0, 2.0]);
      },
    );

    test('einzelner Wert ist sein eigenes Perzentil', () {
      expect(percentile([1.799], 0.1), closeTo(1.799, 1e-9));
    });

    test('leere Eingabe und unsinniger Anteil werfen', () {
      expect(() => percentile([], 0.1), throwsArgumentError);
      expect(() => percentile([1, 2], 1.5), throwsArgumentError);
    });
  });

  group('aggregateWeek', () {
    test('verdichtet je Reihe und zählt Stichproben und Stationen', () {
      final result = aggregateWeek([
        sample('a', e5: 1.80, diesel: 1.70),
        sample('a', e5: 1.78, diesel: 1.68, day: 2),
        sample('b', e5: 1.75, diesel: 1.65),
      ]);

      expect(result[PriceSeries.e5]!.sampleCount, 3);
      expect(result[PriceSeries.e5]!.stationCount, 2);
      // Perzentil 0.1 über [1.75, 1.78, 1.80]: 1.75 + 0.03*0.2
      expect(result[PriceSeries.e5]!.value, closeTo(1.756, 1e-9));
      expect(result[PriceSeries.diesel]!.stationCount, 2);
    });

    test('fehlende Werte zählen nicht mit — eine Null zöge das Perzentil '
        'gegen den Boden', () {
      final result = aggregateWeek([
        sample('a', e5: 1.80),
        sample('b', e5: null, diesel: 1.60),
        sample('c', e5: 1.90),
      ]);

      expect(result[PriceSeries.e5]!.sampleCount, 2);
      expect(result[PriceSeries.e5]!.stationCount, 2);
      expect(result[PriceSeries.e5]!.value, greaterThan(1.79));
    });

    test(
      'Reihe ohne Stichprobe fehlt im Ergebnis, statt erfunden zu werden',
      () {
        final result = aggregateWeek([sample('a', e5: 1.80)]);
        expect(result.containsKey(PriceSeries.e10), isFalse);
        expect(result.containsKey(PriceSeries.diesel), isFalse);
      },
    );

    test('Strom wird nie aus Stichproben verdichtet', () {
      final result = aggregateWeek([sample('a', e5: 1.80, diesel: 1.70)]);
      expect(result.containsKey(PriceSeries.housePower), isFalse);
      expect(result.containsKey(PriceSeries.chargingPower), isFalse);
    });
  });

  group('weeklySeries', () {
    const settings = AppSettings();

    test('hält den gemessenen Wert an den Rändern, statt abzustürzen', () {
      final points = weeklySeries(
        series: PriceSeries.e5,
        from: const IsoWeek(2026, 1),
        to: const IsoWeek(2026, 3),
        stored: const [
          PricePoint(
            week: IsoWeek(2026, 2),
            series: PriceSeries.e5,
            value: 1.812,
            origin: PriceOrigin.measured,
            sampleCount: 40,
            stationCount: 6,
          ),
        ],
        settings: settings,
      );

      expect(points.length, 3);
      // Sobald EINE Woche gemessen ist, kommt die Konstante nicht mehr vor:
      // Sie liegt weit unter dem realen Niveau, und jede fahrfreie Woche
      // zeichnete damit einen Preissturz, den es nie gab.
      expect(points[0].origin, PriceOrigin.interpolated);
      expect(points[0].value, closeTo(1.812, 1e-9));
      expect(points[0].isEstimate, isTrue);
      expect(points[1].origin, PriceOrigin.measured);
      expect(points[1].value, closeTo(1.812, 1e-9));
      expect(points[1].isEstimate, isFalse);
      expect(points[2].origin, PriceOrigin.interpolated);
      expect(points[2].value, closeTo(1.812, 1e-9));
    });

    test('überbrückt eine Lücke linear zwischen zwei Messungen', () {
      final points = weeklySeries(
        series: PriceSeries.diesel,
        from: const IsoWeek(2026, 1),
        to: const IsoWeek(2026, 5),
        stored: const [
          PricePoint(
            week: IsoWeek(2026, 1),
            series: PriceSeries.diesel,
            value: 1.700,
            origin: PriceOrigin.imported,
          ),
          PricePoint(
            week: IsoWeek(2026, 5),
            series: PriceSeries.diesel,
            value: 2.100,
            origin: PriceOrigin.measured,
          ),
        ],
        settings: settings,
      );

      expect(points.length, 5);
      expect(points.map((p) => p.origin), [
        PriceOrigin.imported,
        PriceOrigin.interpolated,
        PriceOrigin.interpolated,
        PriceOrigin.interpolated,
        PriceOrigin.measured,
      ]);
      // Gleichmäßig von 1,70 auf 2,10 — die überbrückten Werte bleiben
      // zwischen den Messungen und können deshalb keinen Sturz erfinden.
      expect(points[1].value, closeTo(1.800, 1e-9));
      expect(points[2].value, closeTo(1.900, 1e-9));
      expect(points[3].value, closeTo(2.000, 1e-9));
    });

    test('das Fenster wächst nach hinten bis zur ältesten Woche', () {
      // Der Fehler, den es verhindert: Nach dem Nachfüll-Lauf lagen 164
      // Wochen vor, gezeigt wurden 26. Der Import wäre gelaufen, und man
      // hätte nichts davon gesehen.
      final (from, to) = chartWindow(
        stored: const [
          PricePoint(
            week: IsoWeek(2023, 2),
            series: PriceSeries.diesel,
            value: 1.759,
            origin: PriceOrigin.imported,
          ),
          PricePoint(
            week: IsoWeek(2026, 30),
            series: PriceSeries.diesel,
            value: 2.099,
            origin: PriceOrigin.measured,
          ),
        ],
        now: DateTime(2026, 8, 2),
      );
      expect(from, const IsoWeek(2023, 2));
      // W30 und nicht W31: Die laufende Woche ist noch nicht verdichtet,
      // das rechte Ende folgt der letzten Messung.
      expect(to, const IsoWeek(2026, 30));
    });

    test('das Fenster endet bei der letzten Messung, nicht bei heute', () {
      // Sonst hielte die Linie den zuletzt bekannten Preis bis zum heutigen
      // Tag: Fährt eine Gruppe ein Jahr nicht, zöge das Diagramm eine
      // gerade Linie über das ganze Jahr und behauptete einen Preis, den
      // nie jemand gemessen hat.
      final (from, to) = chartWindow(
        stored: const [
          PricePoint(
            week: IsoWeek(2025, 15),
            series: PriceSeries.diesel,
            value: 1.529,
            origin: PriceOrigin.imported,
          ),
        ],
        now: DateTime(2026, 8, 2),
      );
      expect(to, const IsoWeek(2025, 15));
      // 26 Wochen Untergrenze, vom neuen rechten Ende aus gerechnet.
      expect(from, const IsoWeek(2024, 42));
      expect(weeksBetween(from, to).length, 26);
    });

    test('ohne Daten bleibt es beim Mindestfenster bis heute', () {
      final (from, to) = chartWindow(
        stored: const [],
        now: DateTime(2026, 8, 2),
      );
      expect(to, const IsoWeek(2026, 31));
      expect(weeksBetween(from, to).length, 26);
    });

    test('die Zeitachse nennt das Jahr, sobald sie eines überschreitet', () {
      // Der Fall, der den Fehler ausgelöst hat: Das Fenster reicht seit dem
      // Nachfüll-Lauf bis 2023 zurück, die Achse las sich aber wie sieben
      // Wochen. Geprüft wird hier und nicht im Flow-Test, weil auf Canvas
      // gezeichneter Text in keinem Widget-Finder auftaucht.
      final long = axisLabels(const IsoWeek(2023, 23), const IsoWeek(2026, 31));
      expect(long.$1, '06.2023');
      expect(long.$2, '07.2026');

      // Innerhalb eines Jahres bleibt der Tag stehen — über wenige Wochen
      // wäre „06.2026" bis „07.2026" keine Auskunft.
      final short = axisLabels(
        const IsoWeek(2026, 23),
        const IsoWeek(2026, 31),
      );
      expect(short.$1, '01.06.');
      expect(short.$2, '27.07.');
    });

    test('nimmt nur Punkte der eigenen Reihe', () {
      final points = weeklySeries(
        series: PriceSeries.diesel,
        from: const IsoWeek(2026, 1),
        to: const IsoWeek(2026, 1),
        stored: const [
          PricePoint(
            week: IsoWeek(2026, 1),
            series: PriceSeries.e5,
            value: 1.812,
            origin: PriceOrigin.measured,
          ),
        ],
        settings: settings,
      );

      expect(points.single.origin, PriceOrigin.constant);
      expect(points.single.value, settings.dieselPricePerLiter);
    });

    test('Strom besteht vorerst ganz aus den Konstanten der Gruppe', () {
      final haus = weeklySeries(
        series: PriceSeries.housePower,
        from: const IsoWeek(2026, 1),
        to: const IsoWeek(2026, 2),
        stored: const [],
        settings: settings,
      );
      final saeule = weeklySeries(
        series: PriceSeries.chargingPower,
        from: const IsoWeek(2026, 1),
        to: const IsoWeek(2026, 2),
        stored: const [],
        settings: settings,
      );

      expect(haus.every((p) => p.origin == PriceOrigin.constant), isTrue);
      expect(haus.every((p) => p.isEstimate), isTrue);
      expect(haus.first.value, settings.electricityPricePerKwh);
      expect(saeule.first.value, settings.chargingPricePerKwh);
      // Öffentliches Laden ist teurer als die eigene Steckdose — wären die
      // beiden vertauscht, fiele es sonst nirgends auf.
      expect(saeule.first.value, greaterThan(haus.first.value));
    });
  });

  group('AppSettings', () {
    test('E10 und Tankstellenstrom überleben den Rundlauf über die DB-Map', () {
      const settings = AppSettings(
        e10PricePerLiter: 1.659,
        chargingPricePerKwh: 0.62,
      );
      final wieder = AppSettings.fromMap(settings.toMap());

      expect(wieder.e10PricePerLiter, closeTo(1.659, 1e-9));
      expect(wieder.chargingPricePerKwh, closeTo(0.62, 1e-9));
    });

    test('copyWith reicht die neuen Werte unverändert durch', () {
      const settings = AppSettings(
        e10PricePerLiter: 1.659,
        chargingPricePerKwh: 0.62,
      );
      final geaendert = settings.copyWith(commuteKm: 42);

      expect(geaendert.e10PricePerLiter, closeTo(1.659, 1e-9));
      expect(geaendert.chargingPricePerKwh, closeTo(0.62, 1e-9));
    });
  });
}
