/// marked_date_picker_test.dart – Der selbst gezeichnete Datumswähler (#83):
/// Markierungen, Zukunftssperre, Monatsklemmen und die DST-Falle.
library;

import 'package:fahrgemeinschaft/core/widgets/marked_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    // Ohne pumpApp lädt niemand die deutschen Datumsformate.
    await initializeDateFormatting('de');
  });

  Future<void> pumpCalendar(WidgetTester tester, Widget child) =>
      tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  MarkedCalendar calendar({
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    Set<DateTime> markedDates = const {},
    String? markedLabel = 'Fahrt schon eingetragen',
    ValueChanged<DateTime>? onSelected,
  }) => MarkedCalendar(
    initialDate: initialDate ?? DateTime(2026, 7, 15),
    firstDate: firstDate ?? DateTime(2020),
    lastDate: lastDate ?? DateTime(2026, 7, 20),
    markedDates: markedDates,
    markedLabel: markedLabel,
    onSelected: onSelected ?? (_) {},
  );

  testWidgets('markiert genau die übergebenen Tage', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCalendar(
      tester,
      calendar(markedDates: {DateTime(2026, 7, 5), DateTime(2026, 7, 12)}),
    );

    expect(
      find.bySemanticsLabel('5. Juli 2026, Fahrt schon eingetragen'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('12. Juli 2026, Fahrt schon eingetragen'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('6. Juli 2026'),
      findsOneWidget,
      reason: 'Ein Tag ohne Fahrt trägt keinen Zusatz.',
    );
    handle.dispose();
  });

  testWidgets('Uhrzeiten in markedDates sind egal', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCalendar(
      tester,
      calendar(markedDates: {DateTime(2026, 7, 5, 14, 30)}),
    );

    expect(
      find.bySemanticsLabel('5. Juli 2026, Fahrt schon eingetragen'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('ein Tipp liefert das Datum als Mitternacht', (tester) async {
    DateTime? picked;
    await pumpCalendar(tester, calendar(onSelected: (d) => picked = d));

    await tester.tap(find.text('9'));
    expect(picked, DateTime(2026, 7, 9));
  });

  testWidgets('Tage nach lastDate sind gesperrt', (tester) async {
    DateTime? picked;
    await pumpCalendar(
      tester,
      calendar(lastDate: DateTime(2026, 7, 20), onSelected: (d) => picked = d),
    );

    await tester.tap(find.text('21'));
    expect(
      picked,
      isNull,
      reason:
          'In der Zukunft wird nichts eingetragen — dieselbe Regel wie beim '
          'alten showDatePicker mit lastDate.',
    );
  });

  testWidgets('die Monats-Chevrons klemmen an first- und lastDate', (
    tester,
  ) async {
    await pumpCalendar(
      tester,
      calendar(firstDate: DateTime(2026, 6, 10), lastDate: DateTime(2026, 7, 20)),
    );

    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    final prev = find.widgetWithIcon(IconButton, Icons.chevron_left);
    expect(
      tester.widget<IconButton>(next).onPressed,
      isNull,
      reason: 'Nach dem Monat von lastDate gibt es nichts zu wählen.',
    );

    await tester.tap(prev);
    await tester.pump();
    expect(find.text('Juni 2026'), findsOneWidget);
    expect(
      tester.widget<IconButton>(prev).onPressed,
      isNull,
      reason: 'Vor dem Monat von firstDate gibt es nichts zu wählen.',
    );
  });

  testWidgets('DST-Monate rendern jeden Tag genau einmal', (tester) async {
    // Oktober (Rückstellung) und März (Vorstellung): Wer Tage per
    // Duration-Addition erzeugt, bekommt hier doppelte oder fehlende Tage.
    for (final month in [DateTime(2026, 3, 15), DateTime(2026, 10, 15)]) {
      await pumpCalendar(
        tester,
        calendar(initialDate: month, lastDate: DateTime(2026, 12, 31)),
      );

      for (var d = 1; d <= 31; d++) {
        expect(
          find.text('$d'),
          findsOneWidget,
          reason: 'Tag $d muss im Monat ${month.month} genau einmal stehen.',
        );
      }
    }
  });

  testWidgets('der Monat beginnt unter dem richtigen Wochentag', (
    tester,
  ) async {
    // Der 1. Juli 2026 ist ein Mittwoch.
    await pumpCalendar(tester, calendar());

    expect(
      tester.getCenter(find.text('1')).dx,
      closeTo(tester.getCenter(find.text('Mi')).dx, 1.0),
    );
  });

  testWidgets('showMarkedDatePicker liefert die Wahl und schließt', (
    tester,
  ) async {
    DateTime? result;
    await pumpCalendar(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            result = await showMarkedDatePicker(
              context: context,
              initialDate: DateTime(2026, 7, 15),
              firstDate: DateTime(2020),
              lastDate: DateTime(2026, 7, 20),
            );
          },
          child: const Text('öffnen'),
        ),
      ),
    );

    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();

    expect(result, DateTime(2026, 7, 9));
    expect(find.text('Datum wählen'), findsNothing);
  });

  testWidgets('Abbrechen liefert null', (tester) async {
    var opened = false;
    DateTime? result = DateTime(2000);
    await pumpCalendar(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            opened = true;
            result = await showMarkedDatePicker(
              context: context,
              initialDate: DateTime(2026, 7, 15),
              firstDate: DateTime(2020),
              lastDate: DateTime(2026, 7, 20),
            );
          },
          child: const Text('öffnen'),
        ),
      ),
    );

    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(result, isNull);
    expect(find.text('Datum wählen'), findsNothing);
  });
}
