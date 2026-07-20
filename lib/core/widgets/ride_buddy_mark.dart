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
    final content = AspectRatio(aspectRatio: 120 / 100, child: painter);
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

class _RideBuddyMarkPainter extends CustomPainter {
  _RideBuddyMarkPainter(this.variant);

  final RideBuddyMarkVariant variant;

  static const _designWidth = 120.0;
  static const _designHeight = 100.0;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = _Palette.of(variant);
    final scale = size.width / _designWidth;

    canvas.save();
    canvas.scale(scale);
    // Streaks laufen im Entwurf über den Rahmen hinaus.
    canvas.clipRect(const Rect.fromLTWH(0, 0, _designWidth, _designHeight));

    void rrect(double x, double y, double w, double h, double r, Paint paint) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(r),
          ),
          paint,
        );

    // Speed-Streaks (nicht mitverschoben, leicht transparent).
    final streak = Paint()..color = palette.streak.withValues(alpha: 0.9);
    rrect(106, 38, 20, 5, 2.5, streak);
    rrect(108, 54, 18, 5, 2.5, streak);
    rrect(106, 70, 19, 5, 2.5, streak);

    // Fahrzeug – im Entwurf um 10 nach links versetzt.
    canvas.translate(-10, 0);

    final wheel = Paint()..color = palette.wheel;
    final hub = Paint()..color = palette.hub;
    canvas.drawCircle(const Offset(36, 80), 12, wheel);
    canvas.drawCircle(const Offset(92, 80), 12, wheel);
    canvas.drawCircle(const Offset(36, 80), 5, hub);
    canvas.drawCircle(const Offset(92, 80), 5, hub);

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
    canvas.drawCircle(const Offset(45, 45), 5, head);
    canvas.drawCircle(const Offset(72, 45), 5, head);
    canvas.drawCircle(const Offset(95, 45), 5, head);

    rrect(11, 57, 7, 10, 3, Paint()..color = const Color(0xFFFACC15));
    rrect(108, 57, 6, 10, 3, Paint()..color = const Color(0xFFEF4444));

    canvas.restore();
  }

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
