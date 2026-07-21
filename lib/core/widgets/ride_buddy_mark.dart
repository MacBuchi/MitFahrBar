/// ride_buddy_mark.dart – Die Bildmarke von RideBuddy.
///
/// Seitenansicht mit drei Köpfen und Speed-Streaks, 1:1 nach dem Design-Set
/// („RideBuddyMark"). Gezeichnet im Entwurfsraster 120 × 100 und auf die
/// verfügbare Fläche skaliert. Die Streaks laufen rechts bewusst aus dem
/// Rahmen — das erzeugt den Bewegungseindruck.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

enum RideBuddyMarkVariant {
  /// Karosserie im Markenverlauf – Standard auf hellem Grund.
  gradient,

  /// Dunkle Karosserie – für helle, ruhige Flächen.
  ink,

  /// Vollflächig weiß – für App-Icon, Banner und farbige Untergründe.
  white,
}

class RideBuddyMark extends StatelessWidget {
  const RideBuddyMark({
    super.key,
    this.variant = RideBuddyMarkVariant.gradient,
    this.size,
  });

  final RideBuddyMarkVariant variant;

  /// Breite; die Höhe folgt dem Seitenverhältnis 120:100.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      painter: _RideBuddyMarkPainter(variant),
      child: const SizedBox.expand(),
    );
    final content = AspectRatio(
      aspectRatio: rideBuddyMarkAspect,
      child: painter,
    );
    return Semantics(
      label: 'RideBuddy',
      child: size == null ? content : SizedBox(width: size, child: content),
    );
  }
}

class _Palette {
  const _Palette({
    required this.body,
    required this.window,
    required this.head,
    required this.wheel,
    required this.hub,
    required this.streak,
    this.bodyGradient = false,
  });

  final Color body;
  final Color window;
  final Color head;
  final Color wheel;
  final Color hub;
  final Color streak;
  final bool bodyGradient;

  static const _gradient = _Palette(
    body: AppColors.brand,
    bodyGradient: true,
    window: Colors.white,
    head: AppColors.brand,
    wheel: Color(0xFF1A1030),
    hub: AppColors.accent,
    streak: AppColors.brandBright,
  );

  static const _ink = _Palette(
    body: Color(0xFF0C3038),
    window: AppColors.paper,
    head: AppColors.brand,
    wheel: Color(0xFF04161B),
    hub: Color(0xFF0E5661),
    streak: AppColors.brand,
  );

  static const _white = _Palette(
    body: Colors.white,
    window: AppColors.brand,
    head: Colors.white,
    wheel: Colors.white,
    hub: AppColors.brand,
    streak: Color(0x8CFFFFFF),
  );

  static _Palette of(RideBuddyMarkVariant v) => switch (v) {
    RideBuddyMarkVariant.gradient => _gradient,
    RideBuddyMarkVariant.ink => _ink,
    RideBuddyMarkVariant.white => _white,
  };
}

/// Seitenverhältnis der Marke (Breite : Höhe) — für alle, die sie selbst
/// zeichnen (Splash-Animation) statt über [RideBuddyMark] einzubinden.
const rideBuddyMarkAspect = 120 / 100;

/// Momentaufnahme des Fahrzeugs für die Splash-Animation. Die Default-Pose
/// ist exakt die statische Marke — [RideBuddyMark] zeichnet mit ihr, damit
/// Animation und Logo nie zweierlei Geometrie haben.
class RideBuddyPose {
  const RideBuddyPose({
    this.pitch = 0,
    this.lift = 0,
    this.streakOpacity = 1,
    this.headScales = const [1, 1, 1],
  });

  /// Nick-Winkel in Radiant. Positiv = die Nase (links, Fahrtrichtung)
  /// taucht ein — die Bremsfeder, gedreht um das **vordere** Rad. Negativ =
  /// Anfahren: die Front hebt sich, gedreht um das **hintere** Rad — sonst
  /// tauchte das Heck unter die Straße.
  final double pitch;

  /// Hub der Karosserie in Entwurfseinheiten (positiv = angehoben) —
  /// das Wippen während der Fahrt. Räder bleiben auf der Straße.
  final double lift;

  /// Speed-Streaks: 1 in voller Fahrt, 0 im Stand.
  final double streakOpacity;

  /// Größe der drei Köpfe in Fahrtrichtung: [Fahrer, Mitte, hinten].
  /// 0 = nicht da, kurz über 1 = das Aufploppen.
  final List<double> headScales;

  static const resting = RideBuddyPose();
}

/// Zeichnet die Marke ins Entwurfsraster 120 × 100, skaliert auf
/// [size]-Breite. Einzige Stelle mit der Fahrzeug-Geometrie (1:1 aus dem
/// Design-Set) — Logo und Splash rufen beide hierher.
void paintRideBuddyMark(
  Canvas canvas,
  Size size,
  RideBuddyMarkVariant variant, [
  RideBuddyPose pose = RideBuddyPose.resting,
]) {
  const designWidth = 120.0;
  const designHeight = 100.0;
  final palette = _Palette.of(variant);
  final scale = size.width / designWidth;

  canvas.save();
  canvas.scale(scale);
  // Streaks laufen im Entwurf über den Rahmen hinaus.
  canvas.clipRect(const Rect.fromLTWH(0, 0, designWidth, designHeight));

  void rrect(double x, double y, double w, double h, double r, Paint paint) =>
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        paint,
      );

  // Speed-Streaks (nicht mitverschoben, leicht transparent).
  if (pose.streakOpacity > 0.01) {
    final streak = Paint()
      ..color = palette.streak.withValues(alpha: 0.9 * pose.streakOpacity);
    rrect(106, 38, 20, 5, 2.5, streak);
    rrect(108, 54, 18, 5, 2.5, streak);
    rrect(106, 70, 19, 5, 2.5, streak);
  }

  // Fahrzeug – im Entwurf um 10 nach links versetzt.
  canvas.translate(-10, 0);

  // Räder bleiben auf der Straße — nur die Karosserie nickt und wippt.
  final wheel = Paint()..color = palette.wheel;
  final hub = Paint()..color = palette.hub;
  canvas.drawCircle(const Offset(36, 80), 12, wheel);
  canvas.drawCircle(const Offset(92, 80), 12, wheel);
  canvas.drawCircle(const Offset(36, 80), 5, hub);
  canvas.drawCircle(const Offset(92, 80), 5, hub);

  canvas.save();
  // Drehpunkt je nach Vorzeichen: Bremsen nickt um das vordere Rad (36, 80),
  // Anfahren bäumt sich um das hintere (92, 80) auf — so bleiben die Räder
  // in beiden Fällen auf der Straße. Negatives Rotations-Vorzeichen, weil
  // die Canvas-Drehung sonst das Heck senkte.
  final pivotX = pose.pitch >= 0 ? 36.0 : 92.0;
  canvas.translate(pivotX, 80);
  canvas.rotate(-pose.pitch);
  canvas.translate(-pivotX, -80 - pose.lift);

  final body = Paint();
  if (palette.bodyGradient) {
    body.shader = AppColors.brandGradient.createShader(
      const Rect.fromLTWH(12, 31, 102, 47),
    );
  } else {
    body.color = palette.body;
  }
  rrect(12, 54, 102, 24, 11, body); // Unterbau
  rrect(26, 31, 84, 27, 9, body); // Kabine

  rrect(32, 37, 72, 15, 5, Paint()..color = palette.window);
  rrect(60, 35, 4, 19, 2, body); // Säule
  rrect(83, 35, 4, 19, 2, body); // Säule

  final head = Paint()..color = palette.head;
  // In Fahrtrichtung (nach links): vorn sitzt der Fahrer.
  const centers = [Offset(45, 45), Offset(72, 45), Offset(95, 45)];
  for (final (i, center) in centers.indexed) {
    final headScale = i < pose.headScales.length ? pose.headScales[i] : 1.0;
    if (headScale > 0.01) canvas.drawCircle(center, 5 * headScale, head);
  }

  rrect(11, 57, 7, 10, 3, Paint()..color = const Color(0xFFFACC15));
  rrect(108, 57, 6, 10, 3, Paint()..color = const Color(0xFFEF4444));

  canvas.restore();
  canvas.restore();
}

class _RideBuddyMarkPainter extends CustomPainter {
  _RideBuddyMarkPainter(this.variant);

  final RideBuddyMarkVariant variant;

  @override
  void paint(Canvas canvas, Size size) =>
      paintRideBuddyMark(canvas, size, variant);

  @override
  bool shouldRepaint(_RideBuddyMarkPainter oldDelegate) =>
      oldDelegate.variant != variant;
}

/// Wortmarke „RideBuddy" – „Ride" in Textfarbe, „Buddy" im Markenton.
class RideBuddyWordmark extends StatelessWidget {
  const RideBuddyWordmark({super.key, this.fontSize = 28, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppFonts.display,
      fontWeight: FontWeight.w700,
      fontSize: fontSize,
      letterSpacing: -0.02 * fontSize,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Ride', style: base),
          TextSpan(
            text: 'Buddy',
            style: base.copyWith(
              color: color ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      semanticsLabel: 'RideBuddy',
    );
  }
}
