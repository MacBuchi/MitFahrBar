/// marked_date_picker.dart – Datumswähler, der einzelne Tage markieren kann.
///
/// Flutters [showDatePicker] kennt keinen Per-Tag-Builder — deshalb selbst
/// gezeichnet, dieselbe Linie wie Charts und Stimmungs-Gesichter: keine
/// Zusatz-Dependency für ein Raster aus 42 Zellen (Issue #83, der
/// Fahrten-Editor markiert Tage mit bereits eingetragener Fahrt).
///
/// Tagesmathe hier NIE über `Duration`-Addition auf lokalen [DateTime]s:
/// Über die Sommerzeit-Umstellung landet Mitternacht + 24 h um 23 Uhr am
/// selben Tag. Zellen entstehen per `DateTime(jahr, monat, tag)`, die
/// Monatslänge über Tag 0 des Folgemonats — Dart normalisiert den Überlauf.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../tokens.dart';

/// Kantenlänge einer Tageszelle — 7 davon ergeben die Dialogbreite,
/// zusammen mit dem Rand die 328 dp des Material-Datumswählers.
const _cellSize = 40.0;

/// Ersatz für [showDatePicker] mit demselben Vertrag: liefert das gewählte
/// Datum (auf Mitternacht normiert) oder `null` bei Abbruch.
///
/// [markedDates] bekommen einen Punkt unter der Tageszahl; [markedLabel]
/// beschriftet ihn (Legende und Screenreader) — ohne Label keine Legende.
Future<DateTime?> showMarkedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  Set<DateTime> markedDates = const {},
  String? markedLabel,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: SizedBox(
        width: 7 * _cellSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MarkedCalendar(
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              markedDates: markedDates,
              markedLabel: markedLabel,
              onSelected: (date) => Navigator.pop(context, date),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Der Kalender selbst — als eigenes Widget direkt testbar.
class MarkedCalendar extends StatefulWidget {
  const MarkedCalendar({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.onSelected,
    this.markedDates = const {},
    this.markedLabel,
  });

  /// Vorauswahl; bestimmt auch den zuerst gezeigten Monat.
  final DateTime initialDate;

  /// Frühester wählbarer Tag.
  final DateTime firstDate;

  /// Spätester wählbarer Tag — im Fahrten-Editor „heute", denn in der
  /// Zukunft wird nichts eingetragen.
  final DateTime lastDate;

  /// Tage mit Punkt-Markierung; Uhrzeiten werden ignoriert.
  final Set<DateTime> markedDates;

  /// Bedeutung der Markierung — Legende und Screenreader-Zusatz.
  final String? markedLabel;

  /// Ein Tipp auf einen wählbaren Tag; das Datum ist auf Mitternacht
  /// normiert.
  final ValueChanged<DateTime> onSelected;

  @override
  State<MarkedCalendar> createState() => _MarkedCalendarState();
}

class _MarkedCalendarState extends State<MarkedCalendar> {
  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  late DateTime _month = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );

  /// Monate als fortlaufende Zahl — so wird „gleicher Monat" ein Vergleich
  /// statt zweier.
  static int _monthIndex(DateTime d) => d.year * 12 + d.month;

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final marked = {for (final d in widget.markedDates) _dayOf(d)};
    final selected = _dayOf(widget.initialDate);
    final now = DateTime.now();
    final today = _dayOf(now);
    final first = _dayOf(widget.firstDate);
    final last = _dayOf(widget.lastDate);

    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = DateTime(_month.year, _month.month).weekday - 1;
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++)
        const SizedBox(width: _cellSize, height: _cellSize),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(
          scheme,
          DateTime(_month.year, _month.month, d),
          marked: marked,
          selected: selected,
          today: today,
          first: first,
          last: last,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Datum wählen',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            IconButton(
              tooltip: 'Voriger Monat',
              icon: const Icon(Icons.chevron_left),
              onPressed: _monthIndex(_month) <= _monthIndex(first)
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month - 1),
                    ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('MMMM yyyy', 'de').format(_month),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Nächster Monat',
              icon: const Icon(Icons.chevron_right),
              onPressed: _monthIndex(_month) >= _monthIndex(last)
                  ? null
                  : () => setState(
                      () => _month = DateTime(_month.year, _month.month + 1),
                    ),
            ),
          ],
        ),
        Row(
          children: [
            for (final label in _weekdays)
              SizedBox(
                width: _cellSize,
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < cells.length; row += 7)
          Row(
            children: cells.sublist(
              row,
              row + 7 > cells.length ? cells.length : row + 7,
            ),
          ),
        if (widget.markedLabel case final legend?) ...[
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.driver,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  legend,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dayCell(
    ColorScheme scheme,
    DateTime date, {
    required Set<DateTime> marked,
    required DateTime selected,
    required DateTime today,
    required DateTime first,
    required DateTime last,
  }) {
    final enabled = !date.isBefore(first) && !date.isAfter(last);
    final isSelected = date == selected;
    final isMarked = marked.contains(date);
    final numberColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : isSelected
        ? scheme.onPrimary
        : date == today
        ? scheme.primary
        : scheme.onSurface;

    return SizedBox(
      width: _cellSize,
      height: _cellSize,
      child: InkWell(
        onTap: enabled ? () => widget.onSelected(date) : null,
        customBorder: const CircleBorder(),
        child: Semantics(
          button: enabled,
          enabled: enabled,
          excludeSemantics: true,
          label: [
            DateFormat('d. MMMM yyyy', 'de').format(date),
            if (isMarked && widget.markedLabel != null) widget.markedLabel,
            if (isSelected) 'ausgewählt',
          ].join(', '),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: isSelected
                ? BoxDecoration(shape: BoxShape.circle, color: scheme.primary)
                : date == today
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary),
                  )
                : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: numberColor),
                ),
                if (isMarked)
                  Positioned(
                    bottom: 4,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Dieselbe „eingetragen"-Farbsprache wie das Häkchen
                        // im Planer; auf der gefüllten Auswahl invertiert.
                        color: isSelected ? scheme.onPrimary : AppColors.driver,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
