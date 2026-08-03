/// ring_chart.dart – Ringe der Statistik-Seite: Segment-Ring (Ersparnis je
/// Person) und Fortschritts-Ring (CO₂ bis zum Etappenziel).
///
/// Selbst gezeichnet wie alle Diagramme (siehe `charts.dart`), mit denselben
/// Regeln, auf den Kreis übertragen: Getrennt wird durch eine Flächen-Lücke
/// (`AppChart.surfaceGap`, am mittleren Radius in einen Winkel umgerechnet),
/// nie durch einen Rahmen; beim Fortschritts-Ring ist NUR das Daten-Ende
/// gerundet, der Start an zwölf Uhr bleibt eckig.
///
/// **Die Ring-Mitte ist ein Widget-Slot, kein Canvas-Text.** Auf Canvas
/// gezeichneter Text taucht in keinem Widget-Finder auf — die Zahl in der
/// Mitte ist aber die Aussage der Karte und muss prüfbar bleiben.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ein geschlossener Ring aus Segmenten, deren Winkel ihre Werte teilen.
class SegmentRing extends StatelessWidget {
  const SegmentRing({
    super.key,
    required this.segments,
    required this.size,
    this.thickness = 26,
    this.center,
  });

  /// Wert + Farbe je Segment; Werte ≤ 0 werden übersprungen.
  final List<({double value, Color color})> segments;

  /// Kantenlänge des (quadratischen) Rings.
  final double size;

  final double thickness;

  /// Steht IN der Öffnung — als Widget, damit Tests die Zahl finden.
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _SegmentRingPainter(
                segments: segments,
                thickness: thickness,
              ),
            ),
          ),
          if (center case final Widget center) center,
        ],
      ),
    );
  }
}

class _SegmentRingPainter extends CustomPainter {
  _SegmentRingPainter({required this.segments, required this.thickness});

  final List<({double value, Color color})> segments;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = segments.where((s) => s.value > 0).toList();
    final total = visible.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final centerPoint = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: centerPoint, radius: radius);
    // Die 2-px-Lücke der Balken, am mittleren Radius in einen Winkel
    // umgerechnet — ein Segment allein ist ein voller Kreis ohne Lücke.
    final gapAngle = visible.length > 1 ? 2.0 / radius : 0.0;

    var start = -math.pi / 2;
    for (final segment in visible) {
      final sweep = segment.value / total * 2 * math.pi;
      // Sehr kleine Anteile behalten einen sichtbaren Rest, wie beim Balken.
      final drawn = math.max(sweep - gapAngle, 0.01);
      canvas.drawArc(
        rect,
        start,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..strokeCap = StrokeCap.butt
          ..color = segment.color,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      old.thickness != thickness || !identical(old.segments, segments);
}

/// Ein Fortschritts-Ring: blasse Spur, darauf ein Bogen von zwölf Uhr im
/// Uhrzeigersinn bis zum Anteil [progress].
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.size,
    this.thickness = 26,
    this.center,
  });

  /// Anteil 0..1; darüber ist der Ring schlicht voll.
  final double progress;

  final Color color;

  /// Die Spur ist Kontext, kein Datum — eine Stufe vom Untergrund entfernt.
  final Color trackColor;

  final double size;
  final double thickness;

  /// Steht IN der Öffnung — als Widget, damit Tests die Zahl finden.
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ProgressRingPainter(
                progress: progress.clamp(0, 1).toDouble(),
                color: color,
                trackColor: trackColor,
                thickness: thickness,
              ),
            ),
          ),
          if (center case final Widget center) center,
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.thickness,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final centerPoint = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: centerPoint, radius: radius);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = trackColor);
    if (progress <= 0) return;

    const start = -math.pi / 2;
    final sweep = progress * 2 * math.pi;
    canvas.drawArc(rect, start, sweep, false, stroke..color = color);
    // Nur das Daten-Ende ist gerundet (die Regel der Balken): ein
    // Halbkreis-Abschluss am Bogenende, der Start bleibt eckig. Bei vollem
    // Ring gibt es kein Ende, das man runden müsste.
    if (progress < 1) {
      final end = start + sweep;
      canvas.drawCircle(
        centerPoint + Offset(math.cos(end) * radius, math.sin(end) * radius),
        thickness / 2,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.thickness != thickness;
}
