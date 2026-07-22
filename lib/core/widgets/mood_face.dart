/// mood_face.dart – Die Gesichter aus dem Design-Set, gezeichnet statt
/// eingebunden.
///
/// Wie die Diagramme (`widgets/charts.dart`) bewusst ohne Fremd-Paket: Ein
/// SVG-Renderer nur für acht Gesichter wäre eine Abhängigkeit mehr, als das
/// Projekt trägt. Die Geometrie ist 1:1 aus den SVGs übernommen, deshalb
/// rechnet alles in deren Koordinatensystem (viewBox 0 0 100 100) und wird
/// erst beim Zeichnen skaliert — so bleiben die Zahlen mit der Vorlage
/// vergleichbar.
///
/// Seit dem Design-Stand „Animated versions" (2026-07-22) leben die
/// Gesichter: Jede Stimmung hat ihre eigene Schleife (Blinzeln, Wippen,
/// Zittern, Konfetti …). Die Keyframes stehen 1:1 als Stützstellen aus dem
/// CSS des Design-Sets im Code — bei einer Änderung dort neu übernehmen,
/// nicht nachempfinden. Bei „Bewegung reduzieren" (Systemeinstellung) und
/// in Widget-Tests (`pumpApp` setzt genau diese Flagge) ruht das Gesicht
/// im 0-%-Zustand der Vorlage.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mood.dart';
import '../tokens.dart';

/// Ein Stimmungs-Gesicht in [size] × [size].
///
/// [semanticLabel] ist keine Kür: Ein Gesicht allein sagt einem Screenreader
/// nichts.
class MoodFace extends StatefulWidget {
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
  State<MoodFace> createState() => _MoodFaceState();
}

class _MoodFaceState extends State<MoodFace>
    with SingleTickerProviderStateMixin {
  /// Schleifendauer je Stimmung — die `animation`-Dauern aus dem Design-Set.
  /// Celebrating nutzt die Konfetti-Periode (3,2 s); das Gesicht hüpft mit
  /// 1,6 s, also genau zweimal je Runde.
  static Duration _loopOf(Mood mood) => switch (mood) {
    Mood.ecstatic => const Duration(milliseconds: 2000),
    Mood.happy => const Duration(milliseconds: 1800),
    Mood.good => const Duration(milliseconds: 3000),
    Mood.neutral => const Duration(milliseconds: 3600),
    Mood.meh => const Duration(milliseconds: 4000),
    Mood.sad => const Duration(milliseconds: 3200),
    Mood.angry => const Duration(milliseconds: 2400),
    Mood.celebrating => const Duration(milliseconds: 3200),
  };

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _loopOf(widget.mood),
  );

  @override
  void didUpdateWidget(MoodFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _controller.duration = _loopOf(widget.mood);
      if (_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate && !_controller.isAnimating) _controller.repeat();
    if (!animate && _controller.isAnimating) _controller.stop();

    final face = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _MoodFacePainter(
            widget.mood,
            animate ? _controller.value : null,
          ),
        ),
      ),
    );
    return widget.semanticLabel == null
        ? face
        : Semantics(label: widget.semanticLabel, child: face);
  }
}

/// Kantenlänge des Koordinatensystems der Vorlage.
const _viewBox = 100.0;

/// Der Feder-Verlauf der Hüpf-Animationen (`cubic-bezier(.34,1.56,.64,1)`
/// im Design-Set) — schwingt über das Ziel hinaus.
const _bounce = Cubic(0.34, 1.56, 0.64, 1);

/// Ein `@keyframes`-Wert als Stützstellen (Schleifenanteil 0..1 → Wert),
/// zwischen den Stützstellen mit [curve] verbunden — so übersetzt sich
/// `animation: … infinite` aus dem Design-Set wörtlich.
double _kf(
  double t,
  List<(double, double)> stops, [
  Curve curve = Curves.easeInOut,
]) {
  if (t <= stops.first.$1) return stops.first.$2;
  for (var i = 0; i < stops.length - 1; i++) {
    final (ta, va) = stops[i];
    final (tb, vb) = stops[i + 1];
    if (t <= tb) {
      final u = ((t - ta) / (tb - ta)).clamp(0.0, 1.0);
      return va + (vb - va) * curve.transform(u);
    }
  }
  return stops.last.$2;
}

class _MoodFacePainter extends CustomPainter {
  const _MoodFacePainter(this.mood, this.t);

  final Mood mood;

  /// Position in der Schleife (0..1); `null` heißt: das ruhende Gesicht
  /// (0-%-Zustand der Vorlage, Träne sichtbar wie im statischen Set).
  final double? t;

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

  /// Wie eine SVG-Gruppe mit `transform` + `transform-origin`: erst um
  /// [origin] verschieben, dann bewegen, dann zurück.
  void _group(
    Canvas canvas, {
    double dx = 0,
    double dy = 0,
    double deg = 0,
    double sx = 1,
    double sy = 1,
    Offset origin = Offset.zero,
    required void Function() paint,
  }) {
    canvas.save();
    canvas.translate(dx + origin.dx, dy + origin.dy);
    if (deg != 0) canvas.rotate(deg * math.pi / 180);
    if (sx != 1 || sy != 1) canvas.scale(sx, sy);
    canvas.translate(-origin.dx, -origin.dy);
    paint();
    canvas.restore();
  }

  /// Die sieben Skalen-Gesichter teilen sich Kopf und Aufbau; sie
  /// unterscheiden sich in Farbe, Augenform, Mundkurve — und Schleife.
  void _paintScaleFace(Canvas canvas) {
    final t = this.t;

    // Ganzkörper-Bewegung (rb-wg/bn/nd/sg/dr/sh im Design-Set).
    var dx = 0.0, dy = 0.0, deg = 0.0, sx = 1.0, sy = 1.0;
    var origin = const Offset(50, 50);
    if (t != null) {
      switch (mood) {
        case Mood.ecstatic: // rb-wg: freudiges Pendeln.
          deg = _kf(t, const [(0, 0), (.20, -4), (.45, 4), (.70, -2), (1, 0)]);
        case Mood.happy: // rb-bn: Hüpfer mit Quetschung, Fußpunkt unten.
          origin = const Offset(50, 97);
          dy = _kf(t, const [
            (0, 0),
            (.30, -6),
            (.50, 0),
            (.65, -2),
            (1, 0),
          ], _bounce);
          sx = _kf(t, const [
            (0, 1),
            (.30, .98),
            (.50, 1.03),
            (.65, 1),
            (1, 1),
          ], _bounce);
          sy = _kf(t, const [
            (0, 1),
            (.30, 1.02),
            (.50, .97),
            (.65, 1),
            (1, 1),
          ], _bounce);
        case Mood.good: // rb-nd: zufriedenes Kopfnicken.
          deg = _kf(t, const [(0, 0), (.30, 2.5), (.60, -1.5), (1, 0)]);
        case Mood.neutral:
          break; // Nur das Blinzeln, siehe unten.
        case Mood.meh: // rb-sg: müdes Seufzen (Atmen).
          sx = sy = _kf(t, const [(0, 1), (.40, 1.03), (.60, .985), (1, 1)]);
        case Mood.sad: // rb-dr: hängende Schultern.
          dy = _kf(t, const [(0, 0), (.50, 1.8), (1, 0)]);
        case Mood.angry: // rb-sh: aufgestautes Zittern am Schleifenende.
          dx = _kf(t, const [
            (0, 0),
            (.78, 0),
            (.82, -2.2),
            (.86, 2.2),
            (.90, -1.6),
            (.94, 1.6),
            (1, 0),
          ]);
          deg = _kf(t, const [
            (0, 0),
            (.78, 0),
            (.82, -2),
            (.86, 2),
            (.90, 0),
            (1, 0),
          ]);
        case Mood.celebrating:
          break; // eigener Zweig
      }
    }

    _group(
      canvas,
      dx: dx,
      dy: dy,
      deg: deg,
      sx: sx,
      sy: sy,
      origin: origin,
      paint: () => _paintScaleFaceParts(canvas),
    );

    // Die Träne fällt außerhalb der Körpergruppe (wie im Design: die
    // Ellipse steht neben dem `g`), sonst sackte sie beim Seufzen mit.
    if (mood == Mood.sad) _paintTear(canvas);
  }

  void _paintScaleFaceParts(Canvas canvas) {
    final t = this.t;
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

    // Punktaugen blinzeln (rb-bl1/2/3): je Stimmung ein anderer Moment,
    // damit nebeneinanderstehende Gesichter nicht synchron klimpern.
    final blink = t == null
        ? 1.0
        : switch (mood) {
            Mood.meh => _kf(t, const [
              (0, 1),
              (.42, 1),
              (.45, .1),
              (.48, 1),
              (1, 1),
            ]),
            Mood.neutral => _kf(t, const [
              (0, 1),
              (.90, 1),
              (.93, .1),
              (.96, 1),
              (1, 1),
            ]),
            Mood.good => _kf(t, const [
              (0, 1),
              (.84, 1),
              (.87, .1),
              (.90, 1),
              (1, 1),
            ]),
            _ => 1.0,
          };
    void eyes(double y, void Function() paint) =>
        _group(canvas, sy: blink, origin: Offset(50, y), paint: paint);

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
        eyes(43, () {
          canvas.drawCircle(const Offset(37, 43), 5.5, inkFill);
          canvas.drawCircle(const Offset(63, 43), 5.5, inkFill);
        });
      case Mood.sad:
        stroke.strokeWidth = 5;
        canvas.drawLine(const Offset(28, 36), const Offset(45, 32), stroke);
        canvas.drawLine(const Offset(72, 36), const Offset(55, 32), stroke);
        canvas.drawCircle(const Offset(37, 45), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 45), 5.5, inkFill);
      case Mood.angry:
        // rb-br: Die Brauen senken sich, während das Gesicht zittert.
        stroke.strokeWidth = 5;
        final brows = t == null
            ? 0.0
            : _kf(t, const [(0, 0), (.75, 0), (.80, 2), (.92, 2), (1, 0)]);
        _group(
          canvas,
          dy: brows,
          paint: () {
            canvas.drawLine(const Offset(28, 32), const Offset(45, 39), stroke);
            canvas.drawLine(const Offset(72, 32), const Offset(55, 39), stroke);
          },
        );
        canvas.drawCircle(const Offset(37, 47), 5.5, inkFill);
        canvas.drawCircle(const Offset(63, 47), 5.5, inkFill);
      case Mood.celebrating:
        break; // eigener Zweig, siehe _paintCelebrating
    }

    stroke.strokeWidth = 6;
    switch (mood) {
      case Mood.ecstatic:
        // rb-lg: Das offene Lachen wird kurz größer.
        final lx = t == null
            ? 1.0
            : _kf(t, const [(0, 1), (.25, 1.06), (.60, 1.06), (1, 1)]);
        final ly = t == null
            ? 1.0
            : _kf(t, const [(0, 1), (.25, 1.12), (.60, 1.12), (1, 1)]);
        _group(
          canvas,
          sx: lx,
          sy: ly,
          origin: const Offset(50, 62),
          paint: () => canvas.drawPath(
            _quad(30, 56, 50, 84, 70, 56)..quadraticBezierTo(50, 66, 30, 56),
            inkFill,
          ),
        );
      case Mood.happy:
        canvas.drawPath(_quad(34, 58, 50, 77, 66, 58), stroke);
      case Mood.good:
        // rb-sm: Das Lächeln zieht kurz breiter.
        final smile = t == null
            ? 1.0
            : _kf(t, const [(0, 1), (.40, 1.08), (1, 1)]);
        _group(
          canvas,
          sx: smile,
          sy: smile,
          origin: const Offset(50, 62),
          paint: () => canvas.drawPath(_quad(37, 60, 50, 70, 63, 60), stroke),
        );
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

  /// rb-tr: Die Träne löst sich, fällt und verblasst — im Ruhebild steht
  /// sie wie im statischen Set bei (63, 58).
  void _paintTear(Canvas canvas) {
    final t = this.t;
    if (t == null) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(63, 58),
          width: 3.4 * 2,
          height: 5.4 * 2,
        ),
        Paint()..color = AppFace.tear,
      );
      return;
    }
    final opacity = _kf(t, const [
      (0, 0),
      (.15, 0),
      (.25, 1),
      (.70, 1),
      (.80, 0),
      (1, 0),
    ], Curves.easeIn);
    if (opacity <= 0.01) return;
    final fall = _kf(t, const [
      (0, 0),
      (.15, 0),
      (.70, 26),
      (.80, 30),
      (1, 30),
    ], Curves.easeIn);
    canvas.drawOval(
      Rect.fromCenter(
        // Die animierte Vorlage startet bei y = 56, nicht 58.
        center: Offset(63, 56 + fall),
        width: 3.4 * 2,
        height: 5.4 * 2,
      ),
      Paint()..color = AppFace.tear.withValues(alpha: opacity),
    );
  }

  /// Der Kopf sitzt hier kleiner und höher als in der Skala, damit das
  /// Konfetti ringsum Platz hat. Das Gesicht hüpft doppelt so schnell wie
  /// das Konfetti flattert (1,6 s zu 3,2 s — wie im Design-Set).
  void _paintCelebrating(Canvas canvas) {
    final t = this.t;

    // rb-fl: sechs Konfetti-Teile, gleiche Schleife, versetzte Startpunkte
    // (die negativen animation-delays der Vorlage).
    void flutterPiece(double delay, void Function() paint) {
      if (t == null) {
        paint();
        return;
      }
      final local = (t + delay) % 1.0;
      _group(
        canvas,
        dy: _kf(local, const [(0, 0), (.5, -5), (1, 0)]),
        // Die Vorlage dreht um die viewBox-Mitte — das kleine Kreisen der
        // Teile um das Gesicht ist Absicht, kein Versehen.
        deg: _kf(local, const [(0, 0), (.5, 12), (1, 0)]),
        origin: const Offset(50, 50),
        paint: paint,
      );
    }

    flutterPiece(
      0,
      () => _confettiSquare(canvas, 12, 16, 25, AppFace.confettiGold),
    );
    flutterPiece(
      .6 / 3.2,
      () => _confettiSquare(canvas, 80, 12, -15, AppFace.confettiGreen),
    );
    flutterPiece(
      1.2 / 3.2,
      () => canvas.drawCircle(
        const Offset(88, 52),
        3.6,
        Paint()..color = AppFace.confettiGold,
      ),
    );
    flutterPiece(
      1.8 / 3.2,
      () => canvas.drawCircle(
        const Offset(10, 55),
        3.2,
        Paint()..color = AppFace.confettiRed,
      ),
    );
    flutterPiece(
      2.4 / 3.2,
      () => _confettiCross(canvas, 20, 78, AppFace.confettiViolet),
    );
    flutterPiece(
      2.9 / 3.2,
      () => _confettiCross(canvas, 82, 82, AppFace.confettiGreen),
    );

    // rb-pt: der Party-Hüpfer, Fußpunkt unten, mit Überschwingen.
    final t2 = t == null ? null : (t * 2) % 1.0;
    _group(
      canvas,
      dy: t2 == null
          ? 0
          : _kf(t2, const [
              (0, 0),
              (.30, -7),
              (.55, 0),
              (.75, -3),
              (1, 0),
            ], _bounce),
      deg: t2 == null
          ? 0
          : _kf(t2, const [
              (0, 0),
              (.30, -3),
              (.55, 2),
              (.75, 0),
              (1, 0),
            ], _bounce),
      origin: const Offset(50, 90),
      paint: () {
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
      },
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
    canvas.rotate(degrees * math.pi / 180);
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
  bool shouldRepaint(_MoodFacePainter oldDelegate) =>
      oldDelegate.mood != mood || oldDelegate.t != t;
}
