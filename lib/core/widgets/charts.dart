/// charts.dart – Die Diagramme der Startseite, von Hand gezeichnet.
///
/// Bewusst ohne Diagramm-Bibliothek: zwei Formen reichen, und so bleiben
/// Marken, Abstände und Farben in denselben Tokens wie der Rest der App.
///
/// Gestaltungsregeln, die hier durchgehalten werden:
/// * Getrennt wird durch Fläche (2 px Lücke), nie durch einen Rahmen.
/// * Nur das Datenende ist gerundet, die Grundlinie bleibt eckig.
/// * Beschriftungen tragen Text-, niemals Datenfarben – die Zuordnung
///   übernimmt die farbige Marke daneben.
/// * Achsen und Hilfslinien sind durchgezogene Haarlinien, eine Stufe vom
///   Untergrund entfernt – nie gestrichelt, das läse sich als Schwellwert.
/// * **Werte trägt entweder die Direktbeschriftung oder die Achse, nie
///   beides.** Bis v0.42.0 beschriftete das Monats-Diagramm die Spitze und
///   den laufenden Monat und kam ohne Wertachse aus – das trägt, solange ein
///   Dutzend breite Säulen dastehen. Seit es die ganze Historie zeigt (#119,
///   bei dieser Gruppe 44 Monate), sind es zu viele und zu schmale Säulen
///   dafür: Dort steht jetzt eine Y-Achse mit Hilfslinien, und die Zahlen
///   über den Balken sind weg. Der gestapelte Balken darunter hat wenige
///   Zeilen und bleibt deshalb bei der Direktbeschriftung.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
// Nur DateFormat: intl exportiert ebenfalls ein `TextDirection` und würde
// sonst das der Zeichen-API verdecken.
import 'package:intl/intl.dart' show DateFormat;

import '../chart_data.dart';
import '../tokens.dart';

/// Wo ein Achsenwert auf der Zeichenfläche liegt.
///
/// Die eine Rechnung für Hilfslinie **und** Achsenzahl: Zwei getrennte
/// Formeln driften auseinander, und dann liegt die Linie neben ihrer Zahl.
double _tickY(int tick, int maxTick, double plotTop, double axisY) =>
    maxTick == 0 ? axisY : axisY - (axisY - plotTop) * tick / maxTick;

/// Fahrten je Monat als Säulen – eine Reihe, daher eine Farbe und keine
/// Legende: die Überschrift sagt bereits, was gezeigt wird.
///
/// Reicht die Breite nicht für alle Monate, wird waagerecht gescrollt statt
/// die Säulen zu Strichen zu quetschen (#119). Die Wertachse steht dabei
/// **außerhalb** des Scrollbereichs – mitgescrollt wäre sie keine Achse mehr.
class MonthlyTripsChart extends StatefulWidget {
  const MonthlyTripsChart({super.key, required this.data});

  final List<MonthBucket> data;

  @override
  State<MonthlyTripsChart> createState() => _MonthlyTripsChartState();
}

class _MonthlyTripsChartState extends State<MonthlyTripsChart> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final month = DateFormat('MMM', 'de');
    final full = DateFormat('MMMM yyyy', 'de');

    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontSize: 11);

    final maxTrips = data.isEmpty
        ? 0
        : data.map((b) => b.trips).reduce(math.max);
    final ticks = axisTicks(maxTrips);

    return Semantics(
      label: data.map((b) => '${full.format(b.date)}: ${b.trips}').join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height:
            AppChart.columnPlotHeight +
            AppSpacing.xl +
            AppChart.columnScrollbarStrip,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomPaint(
              painter: _ValueAxisPainter(
                ticks: ticks,
                labelStyle: labelStyle,
                monthLabelHeight: _textHeight(
                  month.format(DateTime(2026)),
                  labelStyle,
                ),
              ),
              child: SizedBox(width: _axisWidth(ticks, labelStyle)),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final needed = data.length * AppChart.columnMinSlot;
                  final width = math.max(constraints.maxWidth, needed);
                  final scrolls = needed > constraints.maxWidth;
                  return ScrollConfiguration(
                    // Flutter lässt auf Web und Desktop von Haus aus **nur**
                    // Finger ziehen, nicht die Maus. Im Browser hinge die
                    // Historie damit am Mausrad — auf dem Handy fiele es nie
                    // auf, und die PWA nutzt die Gruppe genauso.
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: Scrollbar(
                      controller: _controller,
                      // Nur zeigen, wenn es wirklich etwas zu holen gibt: Der
                      // Balken IST der Hinweis, dass links noch mehr liegt.
                      thumbVisibility: scrolls,
                      child: SingleChildScrollView(
                        controller: _controller,
                        scrollDirection: Axis.horizontal,
                        // Der Blick steht beim aktuellen Monat; gewischt wird
                        // in die Vergangenheit. Andersherum landete man 2023.
                        reverse: true,
                        child: SizedBox(
                          width: width,
                          child: CustomPaint(
                            painter: _MonthlyTripsPainter(
                              data: data,
                              ticks: ticks,
                              barColor: theme.colorScheme.primary,
                              axisColor: theme.colorScheme.outlineVariant,
                              labelStyle: labelStyle,
                              monthLabel: (bucket) => month.format(bucket.date),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _textHeight(String value, TextStyle style) => (TextPainter(
  text: TextSpan(text: value, style: style),
  textDirection: TextDirection.ltr,
)..layout()).height;

/// Breite der Achsenspalte: die längste Zahl, die dort stehen wird.
double _axisWidth(List<int> ticks, TextStyle style) {
  var widest = 0.0;
  for (final tick in ticks) {
    final painter = TextPainter(
      text: TextSpan(text: '$tick', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    widest = math.max(widest, painter.width);
  }
  return widest;
}

/// Die Zahlen der Wertachse – rechtsbündig, auf Höhe ihrer Hilfslinie.
class _ValueAxisPainter extends CustomPainter {
  _ValueAxisPainter({
    required this.ticks,
    required this.labelStyle,
    required this.monthLabelHeight,
  });

  final List<int> ticks;
  final TextStyle labelStyle;

  /// Die Monatskürzel stehen unter der Grundlinie; die Achse muss denselben
  /// Streifen frei lassen, sonst sitzen ihre Zahlen zu tief.
  final double monthLabelHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (ticks.isEmpty) return;
    final axisY =
        size.height -
        AppChart.columnScrollbarStrip -
        monthLabelHeight -
        AppSpacing.xs;
    final plotTop = _textHeight('0', labelStyle) / 2;
    final maxTick = ticks.last;

    for (final tick in ticks) {
      final painter = TextPainter(
        text: TextSpan(text: '$tick', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = _tickY(tick, maxTick, plotTop, axisY);
      painter.paint(
        canvas,
        Offset(size.width - painter.width, y - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_ValueAxisPainter old) =>
      old.monthLabelHeight != monthLabelHeight ||
      old.labelStyle != labelStyle ||
      !listEquals(old.ticks, ticks);
}

class _MonthlyTripsPainter extends CustomPainter {
  _MonthlyTripsPainter({
    required this.data,
    required this.ticks,
    required this.barColor,
    required this.axisColor,
    required this.labelStyle,
    required this.monthLabel,
  });

  final List<MonthBucket> data;
  final List<int> ticks;
  final Color barColor;
  final Color axisColor;
  final TextStyle labelStyle;
  final String Function(MonthBucket) monthLabel;

  TextPainter _text(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final labels = [for (final b in data) _text(monthLabel(b), labelStyle)];
    final maxTick = ticks.isEmpty ? 0 : ticks.last;

    // Die Fläche muss das Achsenband einschließen, sonst wird es abgeschnitten.
    // Oben bleibt eine halbe Zeilenhöhe frei: Dort sitzt die Zahl des obersten
    // Hilfsstrichs, auf ihrer Linie zentriert (siehe _ValueAxisPainter).
    // Unten bleibt der Streifen der Scrollleiste frei.
    final axisY =
        size.height -
        AppChart.columnScrollbarStrip -
        labels.first.height -
        AppSpacing.xs;
    final plotTop = _text('0', labelStyle).height / 2;
    if (axisY - plotTop <= 0) return;

    final slot = size.width / data.length;
    final barWidth = math.min(AppChart.barMaxThickness, slot - AppSpacing.s);
    if (barWidth <= 0) return;

    // Hilfslinien inklusive der Grundlinie bei 0: haarfein, durchgezogen, eine
    // Stufe vom Untergrund entfernt. Sie tragen seit #119 die Werte, die
    // vorher an den Säulen standen — deshalb liegen sie hinter den Balken,
    // nicht darüber.
    final linePaint = Paint()
      ..color = axisColor
      ..strokeWidth = AppChart.hairline;
    for (final tick in ticks) {
      final y = _tickY(tick, maxTick, plotTop, axisY);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final barPaint = Paint()..color = barColor;
    for (final (index, bucket) in data.indexed) {
      if (bucket.trips == 0) continue;
      final center = slot * index + slot / 2;
      // Gegen den obersten Hilfsstrich gerechnet, nicht gegen das Maximum —
      // sonst stieße die höchste Säule immer an die Decke und läge nicht auf
      // ihrem Wert.
      final top = _tickY(bucket.trips, maxTick, plotTop, axisY);
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          center - barWidth / 2,
          top,
          center + barWidth / 2,
          axisY,
          topLeft: const Radius.circular(AppChart.barEndRadius),
          topRight: const Radius.circular(AppChart.barEndRadius),
        ),
        barPaint,
      );
    }

    // Passt ein Kürzel nicht in sein Raster, wird nur jedes zweite gesetzt –
    // gezählt vom neuesten Monat, damit der immer beschriftet ist.
    final widest = labels.map((l) => l.width).reduce(math.max);
    final everySecond = widest > slot - AppSpacing.xs;
    for (final (index, label) in labels.indexed) {
      if (everySecond && (labels.length - 1 - index).isOdd) continue;
      final center = slot * index + slot / 2;
      label.paint(
        canvas,
        Offset(center - label.width / 2, axisY + AppSpacing.xs),
      );
    }
  }

  @override
  bool shouldRepaint(_MonthlyTripsPainter old) =>
      old.barColor != barColor ||
      old.axisColor != axisColor ||
      old.data.length != data.length ||
      !listEquals(old.ticks, ticks) ||
      !identical(old.data, data);
}

/// Wie die Einzelnen unterwegs waren, als gestapelte Balken auf gemeinsamer
/// Skala: die Länge zeigt die Beteiligung, die Aufteilung deren Art.
///
/// Stapelreihenfolge gefahren → 1-way → mitgefahren ist danach sortiert, wie
/// viel man mitgenommen wurde (0 / 0,5 / 1,0). Sie hält zugleich die beiden
/// ähnlichsten Farben auseinander – geprüft mit dem Paletten-Validator.
class ParticipationMixChart extends StatelessWidget {
  const ParticipationMixChart({super.key, required this.rows});

  final List<ParticipationRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxTotal = rows.map((r) => r.total).fold(0, math.max).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MixLegend(),
        const SizedBox(height: AppSpacing.m),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: Semantics(
              label:
                  '${row.label}: ${row.driven} mal gefahren, '
                  '${row.oneWay} mal eine Richtung, '
                  '${row.ridden} mal mitgefahren',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      row.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: SizedBox(
                      height: AppChart.stackedBarThickness,
                      child: CustomPaint(
                        painter: _StackedBarPainter(
                          segments: [
                            (value: row.driven, color: AppColors.driver),
                            (value: row.oneWay, color: AppColors.oneWay),
                            (value: row.ridden, color: AppColors.passenger),
                          ],
                          maxTotal: maxTotal,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  // Wert an der Spitze; die Aufteilung trägt die Legende.
                  // Feste Breite mit Tabellenziffern, damit die Spalte
                  // untereinander fluchtet – und einzeilig bleibt, statt bei
                  // dreistelligen Werten umzubrechen.
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${row.total}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MixLegend extends StatelessWidget {
  const _MixLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.xs,
      children: [
        _LegendItem(color: AppColors.driver, label: 'gefahren'),
        _LegendItem(color: AppColors.oneWay, label: '1-way'),
        _LegendItem(color: AppColors.passenger, label: 'mitgefahren'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppChart.surfaceGap),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StackedBarPainter extends CustomPainter {
  _StackedBarPainter({required this.segments, required this.maxTotal});

  final List<({int value, Color color})> segments;
  final double maxTotal;

  @override
  void paint(Canvas canvas, Size size) {
    final total = maxTotal <= 0 ? 1.0 : maxTotal;
    final visible = segments.where((s) => s.value > 0).toList();

    var x = 0.0;
    for (final (index, segment) in visible.indexed) {
      final isLast = index == visible.length - 1;
      final width = segment.value / total * size.width;
      // Die Lücke schneidet vom Segment ab, statt einen Rahmen zu ziehen.
      // Sehr kleine Anteile behalten einen sichtbaren Rest.
      final end = math.max(
        x + 0.5,
        x + width - (isLast ? 0 : AppChart.surfaceGap),
      );
      final radius = isLast
          ? const Radius.circular(AppChart.barEndRadius)
          : Radius.zero;
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          x,
          0,
          math.min(end, size.width),
          size.height,
          topRight: radius,
          bottomRight: radius,
        ),
        Paint()..color = segment.color,
      );
      x += width;
    }
  }

  @override
  bool shouldRepaint(_StackedBarPainter old) =>
      old.maxTotal != maxTotal ||
      old.segments.length != segments.length ||
      !identical(old.segments, segments);
}
