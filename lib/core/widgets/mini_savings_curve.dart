/// mini_savings_curve.dart – die fokussierte Ersparnis-Kurve der
/// Statistik-Seite: NUR die Gruppenlinie, mit weicher Fläche darunter,
/// Endpunkt und Meilenstein-Marker.
///
/// Bewusst kein zweites `SavingsTrendChart`: kein Zoom, keine
/// Personen-Linien, kein Text auf dem Canvas. Die große Summe steht als
/// Widget über der Kurve, der Meilenstein als Widget-Zeile darunter — beides
/// bleibt damit für Tests auffindbar. Die Wertachse beginnt bei null
/// (eine kumulierte Summe ist eine Menge, siehe `savings_chart.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chart_data.dart';

class MiniSavingsCurve extends StatelessWidget {
  const MiniSavingsCurve({
    super.key,
    required this.chart,
    required this.color,
    this.milestoneIndex,
    this.height = 110,
  });

  final SavingsChart chart;

  /// Linienfarbe — gemessen gegen die Kartenfläche (`AppStatsColors.eco`).
  final Color color;

  /// Wochen-Index des Meilensteins auf der Kurve (aus `savingsMilestone`).
  final int? milestoneIndex;

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _MiniCurvePainter(
          values: chart.group,
          color: color,
          milestoneIndex: milestoneIndex,
          surface: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
      ),
    );
  }
}

class _MiniCurvePainter extends CustomPainter {
  _MiniCurvePainter({
    required this.values,
    required this.color,
    required this.milestoneIndex,
    required this.surface,
  });

  final List<double> values;
  final Color color;
  final int? milestoneIndex;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final max = values.fold(0.0, math.max);
    if (max <= 0) return;

    // Rechts Platz für den Endpunkt, oben für den Meilenstein-Ring.
    const inset = 6.0;
    final drawWidth = size.width - inset;
    final drawHeight = size.height - 2 * inset;
    Offset pointAt(int i) => Offset(
      i / (values.length - 1) * drawWidth,
      inset + (1 - values[i] / max) * drawHeight,
    );

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pointAt(i).dx, pointAt(i).dy);
    }

    final area = Path.from(line)
      ..lineTo(pointAt(values.length - 1).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Meilenstein: heller Punkt mit farbigem Ring — ein Halt AUF der Kurve.
    if (milestoneIndex case final int index when index < values.length) {
      final at = pointAt(index);
      canvas.drawCircle(at, 4.5, Paint()..color = surface);
      canvas.drawCircle(
        at,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }

    // Endpunkt: der aktuelle Stand.
    canvas.drawCircle(pointAt(values.length - 1), 4.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MiniCurvePainter old) =>
      old.color != color ||
      old.milestoneIndex != milestoneIndex ||
      old.surface != surface ||
      !identical(old.values, values);
}
