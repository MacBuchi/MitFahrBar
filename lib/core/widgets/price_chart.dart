/// price_chart.dart – Wochenverlauf der Preisreihen als Linien.
///
/// Selbst gezeichnet wie alle Diagramme hier: `core/chart_data.dart` und
/// `core/price_series.dart` rechnen, dieser CustomPainter zeichnet nur.
///
/// **Die Wertachse beginnt NICHT bei null**, anders als bei den Säulen in
/// `charts.dart`. Dort trägt die Länge die Aussage, und eine abgeschnittene
/// Achse verfälscht den optischen Vergleich. Hier trägt der *Verlauf* die
/// Aussage: Spritpreise bewegen sich zwischen 1,60 und 2,20 €, auf einer
/// Null-Achse wäre jede Schwankung eine gerade Linie. Die Beschriftung nennt
/// deshalb beide Enden.
library;

import 'package:flutter/material.dart';

import '../price_series.dart';
import '../tokens.dart';

/// Farbe einer Reihe.
///
/// Bewusst aus den vorhandenen Diagramm-Farben statt neu erfunden: Sie stehen
/// schon auf denselben Flächen und sind dort gegen den Untergrund geprüft.
/// Kraftstoff und Strom liegen in getrennten Diagrammen — €/l und €/kWh auf
/// einer Achse wäre schlicht falsch —, deshalb reichen drei Töne.
Color colorOf(PriceSeries series) => switch (series) {
  PriceSeries.diesel => AppColors.driver,
  PriceSeries.e5 => AppColors.passenger,
  PriceSeries.e10 => AppColors.oneWay,
  PriceSeries.housePower => AppColors.driver,
  PriceSeries.chargingPower => AppColors.oneWay,
};

String labelOf(PriceSeries series) => switch (series) {
  PriceSeries.diesel => 'Diesel',
  PriceSeries.e5 => 'Super E5',
  PriceSeries.e10 => 'Super E10',
  PriceSeries.housePower => 'Hausstrom',
  PriceSeries.chargingPower => 'Ladesäule',
};

class PriceTrendChart extends StatelessWidget {
  const PriceTrendChart({
    super.key,
    required this.lines,
    required this.unit,
    this.height = 180,
  });

  /// Je Reihe die lückenlose Wochenfolge aus `weeklySeries` — gemessene und
  /// aus der Konstante gefüllte Punkte gemischt, in derselben Reihenfolge.
  final Map<PriceSeries, List<PricePoint>> lines;

  /// „€/l" oder „€/kWh". Steht an der Achse, weil zwei Diagramme mit
  /// unterschiedlicher Einheit nebeneinanderstehen.
  final String unit;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [
      for (final points in lines.values)
        for (final point in points) point.value,
    ];
    if (values.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Noch keine zwei Wochen erfasst.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    // Eine völlig flache Reihe (alles Konstante) hätte sonst die Höhe 0 und
    // läge auf der Achskante.
    if (max - min < 0.02) {
      min -= 0.01;
      max += 0.01;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _PriceTrendPainter(
              lines: lines,
              min: min,
              max: max,
              unit: unit,
              gridColor: theme.colorScheme.outlineVariant,
              textStyle:
                  theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 8),
        _Legend(series: lines.keys.toList()),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.series});

  final List<PriceSeries> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final entry in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: colorOf(entry),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(labelOf(entry), style: theme.textTheme.bodySmall),
            ],
          ),
        // Die Farbe trägt die Zuordnung nie allein — und die Strichelung
        // braucht ihre eigene Erklärung, sonst liest sie sich als Stilmittel
        // statt als „das ist gar nicht gemessen".
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(14, 3),
              painter: _DashSwatch(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Text(
              'aus den Parametern',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashSwatch extends CustomPainter {
  _DashSwatch({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 3).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashSwatch old) => old.color != color;
}

class _PriceTrendPainter extends CustomPainter {
  _PriceTrendPainter({
    required this.lines,
    required this.min,
    required this.max,
    required this.unit,
    required this.gridColor,
    required this.textStyle,
  });

  final Map<PriceSeries, List<PricePoint>> lines;
  final double min;
  final double max;
  final String unit;
  final Color gridColor;
  final TextStyle textStyle;

  static const _leftPad = 52.0;
  static const _bottomPad = 18.0;

  TextPainter _text(String value) => TextPainter(
    text: TextSpan(text: value, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPad;
    final plotHeight = size.height - _bottomPad;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    double y(double value) =>
        plotHeight - (value - min) / (max - min) * plotHeight;

    // Zwei Hilfslinien plus die Ränder: mehr wäre bei dieser Höhe Gitter
    // statt Orientierung.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final value = min + (max - min) * i / 2;
      final position = y(value);
      canvas.drawLine(
        Offset(_leftPad, position),
        Offset(size.width, position),
        grid,
      );
      final label = _text('${value.toStringAsFixed(2)} $unit');
      label.paint(
        canvas,
        Offset(_leftPad - label.width - 6, position - label.height / 2),
      );
    }

    for (final entry in lines.entries) {
      final points = entry.value;
      if (points.length < 2) continue;
      final step = plotWidth / (points.length - 1);
      final paint = Paint()
        ..color = colorOf(entry.key)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (var i = 0; i < points.length - 1; i++) {
        final from = Offset(_leftPad + i * step, y(points[i].value));
        final to = Offset(_leftPad + (i + 1) * step, y(points[i + 1].value));
        // Ein Abschnitt gilt als „nicht gemessen", sobald einer seiner
        // beiden Enden aus der Konstante stammt: Die Linie dorthin ist
        // erfunden, auch wenn sie an einem echten Wert beginnt.
        final guessed = points[i].isConstant || points[i + 1].isConstant;
        if (guessed) {
          _dashed(
            canvas,
            from,
            to,
            paint..color = paint.color.withValues(alpha: 0.45),
          );
          paint.color = colorOf(entry.key);
        } else {
          canvas.drawLine(from, to, paint);
        }
      }
    }
  }

  void _dashed(Canvas canvas, Offset from, Offset to, Paint paint) {
    final delta = to - from;
    final length = delta.distance;
    if (length == 0) return;
    final unitVector = delta / length;
    for (var travelled = 0.0; travelled < length; travelled += 8) {
      final start = from + unitVector * travelled;
      final end = from + unitVector * (travelled + 4).clamp(0.0, length);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_PriceTrendPainter old) =>
      old.lines != lines || old.min != min || old.max != max;
}
