/// mood_face.dart – Die Gesichter aus dem Design-Set, gezeichnet statt
/// eingebunden.
///
/// Wie die Diagramme (`widgets/charts.dart`) bewusst ohne Fremd-Paket: Ein
/// SVG-Renderer nur für acht Gesichter wäre eine Abhängigkeit mehr, als das
/// Projekt trägt. Die Geometrie ist 1:1 aus den SVGs übernommen, deshalb
/// rechnet alles in deren Koordinatensystem (viewBox 0 0 100 100) und wird
/// erst beim Zeichnen skaliert — so bleiben die Zahlen mit der Vorlage
/// vergleichbar.
library;

import 'package:flutter/material.dart';

import '../mood.dart';
import '../tokens.dart';

/// Ein Stimmungs-Gesicht in [size] × [size].
///
/// [semanticLabel] ist keine Kür: Ein Gesicht allein sagt einem Screenreader
/// nichts.
class MoodFace extends StatelessWidget {
  const MoodFace({
    super.key,
    required this.mood,
    this.size = 24,
    this.semanticLabel,
  });

  final Mood mood;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final face = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MoodFacePainter(mood)),
    );
    return semanticLabel == null
        ? face
        : Semantics(label: semanticLabel, child: face);
  }
}

/// Kantenlänge des Koordinatensystems der Vorlage.
const _viewBox = 100.0;

class _MoodFacePainter extends CustomPainter {
  const _MoodFacePainter(this.mood);

  final Mood mood;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    if (mood == Mood.celebrating) {
      _paintCelebrating(canvas);
    } else {
      _paintScaleFace(canvas);
    }
    canvas.restore();
  }

  /// Die sieben Skalen-Gesichter teilen sich Kopf und Aufbau; sie
  /// unterscheiden sich in Farbe, Augenform und Mundkurve.
  void _paintScaleFace(Canvas canvas) {
    final (fill, ink) = switch (mood) {
      Mood.ecstatic => (AppFace.ecstaticFill, AppFace.ecstaticInk),
      Mood.happy => (AppFace.happyFill, AppFace.happyInk),
      Mood.good => (AppFace.goodFill, AppFace.goodInk),
      Mood.neutral => (AppFace.neutralFill, AppFace.neutralInk),
      Mood.meh => (AppFace.mehFill, AppFace.mehInk),
      Mood.sad => (AppFace.sadFill, AppFace.sadInk),
      Mood.angry => (AppFace.angryFill, AppFace.angryInk),
      Mood.celebrating => (AppFace.celebrateFill, AppFace.celebrateInk),
    };

    canvas.drawCircle(const Offset(50, 50), 47, Paint()..color = fill);

    final inkFill = Paint()..color = ink;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (mood) {
      case Mood.ecstatic:
        // Zusammengekniffene Augen als Bögen — kein Punktauge.
        stroke.strokeWidth = 5;
        canvas.drawPath(_quad(27, 44, 36, 33, 45, 44), stroke);
        canvas.drawPath(_quad(55, 44, 64, 33, 73, 44), stroke);
      case Mood.happy:
        canvas.drawCircle(const Offset(37, 42), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 42), 5.5, inkFill);
      case Mood.good || Mood.neutral || Mood.meh:
        canvas.drawCircle(const Offset(37, 43), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 43), 5.5, inkFill);
      case Mood.sad:
        stroke.strokeWidth = 5;
        canvas.drawLine(const Offset(28, 36), const Offset(45, 32), stroke);
        canvas.drawLine(const Offset(72, 36), const Offset(55, 32), stroke);
        canvas.drawCircle(const Offset(37, 45), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 45), 5.5, inkFill);
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(63, 58),
            width: 3.4 * 2,
            height: 5.4 * 2,
          ),
          Paint()..color = AppFace.tear,
        );
      case Mood.angry:
        stroke.strokeWidth = 5;
        canvas.drawLine(const Offset(28, 32), const Offset(45, 39), stroke);
        canvas.drawLine(const Offset(72, 32), const Offset(55, 39), stroke);
        canvas.drawCircle(const Offset(37, 47), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 47), 5.5, inkFill);
      case Mood.celebrating:
        break; // eigener Zweig, siehe _paintCelebrating
    }

    stroke.strokeWidth = 6;
    switch (mood) {
      case Mood.ecstatic:
        // Offenes Lachen: gefüllte Fläche statt Linie.
        canvas.drawPath(
          _quad(30, 56, 50, 84, 70, 56)..quadraticBezierTo(50, 66, 30, 56),
          inkFill,
        );
      case Mood.happy:
        canvas.drawPath(_quad(34, 58, 50, 77, 66, 58), stroke);
      case Mood.good:
        canvas.drawPath(_quad(37, 60, 50, 70, 63, 60), stroke);
      case Mood.neutral:
        canvas.drawLine(const Offset(37, 63), const Offset(63, 63), stroke);
      case Mood.meh:
        canvas.drawPath(_quad(37, 66, 50, 60, 63, 66), stroke);
      case Mood.sad:
        canvas.drawPath(_quad(36, 69, 50, 57, 64, 69), stroke);
      case Mood.angry:
        canvas.drawPath(_quad(36, 68, 50, 60, 64, 68), stroke);
      case Mood.celebrating:
        break;
    }
  }

  /// Der Kopf sitzt hier kleiner und höher als in der Skala, damit das
  /// Konfetti ringsum Platz hat.
  void _paintCelebrating(Canvas canvas) {
    _confettiSquare(canvas, 12, 16, 25, AppFace.confettiGold);
    _confettiSquare(canvas, 80, 12, -15, AppFace.confettiGreen);
    canvas.drawCircle(
      const Offset(88, 52),
      3.6,
      Paint()..color = AppFace.confettiGold,
    );
    canvas.drawCircle(
      const Offset(10, 55),
      3.2,
      Paint()..color = AppFace.confettiRed,
    );
    _confettiCross(canvas, 20, 78, AppFace.confettiViolet);
    _confettiCross(canvas, 82, 82, AppFace.confettiGreen);

    canvas.drawCircle(
      const Offset(50, 52),
      38,
      Paint()..color = AppFace.celebrateFill,
    );

    final ink = Paint()..color = AppFace.celebrateInk;
    final stroke = Paint()
      ..color = AppFace.celebrateInk
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5;
    canvas.drawPath(_quad(28, 46, 37, 36, 46, 46), stroke);
    canvas.drawPath(_quad(54, 46, 63, 36, 72, 46), stroke);
    canvas.drawPath(
      _quad(33, 58, 50, 82, 67, 58)..quadraticBezierTo(50, 66, 33, 58),
      ink,
    );
    canvas.drawPath(
      _quad(44, 70, 50, 76, 56, 70)..quadraticBezierTo(50, 74, 44, 70),
      Paint()..color = AppFace.celebrateTongue,
    );
  }

  void _confettiSquare(
    Canvas canvas,
    double x,
    double y,
    double degrees,
    Color color,
  ) {
    canvas.save();
    // Die Vorlage dreht um den Mittelpunkt des Quadrats (x+3, y+3).
    canvas.translate(x + 3, y + 3);
    canvas.rotate(degrees * 3.141592653589793 / 180);
    canvas.translate(-(x + 3), -(y + 3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 7, 7),
        const Radius.circular(1.5),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  void _confettiCross(Canvas canvas, double x, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    canvas.drawLine(Offset(x, y), Offset(x + 4, y + 4), paint);
    canvas.drawLine(Offset(x + 4, y), Offset(x, y + 4), paint);
  }

  /// Eine quadratische Bézierkurve, wie `Q` im SVG-Pfad.
  Path _quad(
    double x0,
    double y0,
    double cx,
    double cy,
    double x1,
    double y1,
  ) => Path()
    ..moveTo(x0, y0)
    ..quadraticBezierTo(cx, cy, x1, y1);

  @override
  bool shouldRepaint(_MoodFacePainter oldDelegate) => oldDelegate.mood != mood;
}
