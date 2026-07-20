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
/// * Beschriftet wird sparsam: die Spitze, nicht jeder Wert.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
// Nur DateFormat: intl exportiert ebenfalls ein `TextDirection` und würde
// sonst das der Zeichen-API verdecken.
import 'package:intl/intl.dart' show DateFormat;

import '../chart_data.dart';
import '../tokens.dart';

/// Fahrten je Monat als Säulen – eine Reihe, daher eine Farbe und keine
/// Legende: die Überschrift sagt bereits, was gezeigt wird.
class MonthlyTripsChart extends StatelessWidget {
  const MonthlyTripsChart({super.key, required this.data});

  final List<MonthBucket> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = DateFormat('MMM', 'de');
    final full = DateFormat('MMMM yyyy', 'de');

    final labelStyle =
        theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontSize: 11);
    final valueStyle =
        theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(fontSize: 12);

    return Semantics(
      label: data.map((b) => '${full.format(b.date)}: ${b.trips}').join(', '),
      excludeSemantics: true,
      child: SizedBox(
        height: AppChart.columnPlotHeight + AppSpacing.xl,
        child: CustomPaint(
          painter: _MonthlyTripsPainter(
            data: data,
            barColor: theme.colorScheme.primary,
            axisColor: theme.colorScheme.outlineVariant,
            labelStyle: labelStyle,
            valueStyle: valueStyle,
            monthLabel: (bucket) => month.format(bucket.date),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MonthlyTripsPainter extends CustomPainter {
  _MonthlyTripsPainter({
    required this.data,
    required this.barColor,
    required this.axisColor,
    required this.labelStyle,
    required this.valueStyle,
    required this.monthLabel,
  });

  final List<MonthBucket> data;
  final Color barColor;
  final Color axisColor;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final String Function(MonthBucket) monthLabel;

  TextPainter _text(String value, TextStyle style) => TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final labels = [for (final b in data) _text(monthLabel(b), labelStyle)];
    final maxTrips = data.map((b) => b.trips).reduce(math.max);
    final peak = data.indexWhere((b) => b.trips == maxTrips);
    final peakLabel = _text('${data[peak].trips}', valueStyle);

    // Die Fläche muss das Achsenband einschließen, sonst wird es abgeschnitten.
    final labelHeight = labels.first.height;
    final axisY = size.height - labelHeight - AppSpacing.xs;
    final plotTop = peakLabel.height + AppSpacing.xs;
    final plotHeight = axisY - plotTop;
    if (plotHeight <= 0) return;

    final slot = size.width / data.length;
    final barWidth = math.min(AppChart.barMaxThickness, slot - AppSpacing.s);
    if (barWidth <= 0) return;

    // Grundlinie: haarfein, durchgezogen, eine Stufe vom Untergrund entfernt.
    canvas.drawLine(
      Offset(0, axisY),
      Offset(size.width, axisY),
      Paint()
        ..color = axisColor
        ..strokeWidth = AppChart.hairline,
    );

    final barPaint = Paint()..color = barColor;
    for (final (index, bucket) in data.indexed) {
      if (bucket.trips == 0) continue;
      final center = slot * index + slot / 2;
      final height = maxTrips == 0 ? 0.0 : bucket.trips / maxTrips * plotHeight;
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          center - barWidth / 2,
          axisY - height,
          center + barWidth / 2,
          axisY,
          topLeft: const Radius.circular(AppChart.barEndRadius),
          topRight: const Radius.circular(AppChart.barEndRadius),
        ),
        barPaint,
      );
    }

    // Beschriftet werden nur die Spitze und der laufende Monat – die eine
    // gibt der Achse ihren Maßstab, der andere beantwortet „wie stehen wir
    // gerade da". Eine Zahl an jeder Säule wäre Lärm.
    if (maxTrips > 0) {
      final labelled = {peak, data.length - 1};
      for (final index in labelled) {
        final bucket = data[index];
        if (bucket.trips == 0) continue;
        final value = index == peak
            ? peakLabel
            : _text('${bucket.trips}', valueStyle);
        final center = slot * index + slot / 2;
        value.paint(
          canvas,
          Offset(
            center - value.width / 2,
            axisY - bucket.trips / maxTrips * plotHeight - value.height,
          ),
        );
      }
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
