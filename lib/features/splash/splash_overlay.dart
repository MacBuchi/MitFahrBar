/// splash_overlay.dart – Die Anfahrt: MitFahrBars Startbildschirm.
///
/// Das Auto kommt von rechts, bremst (die Nase nickt ein und federt zurück),
/// die hinteren Köpfe ploppen auf, dann fährt es links aus dem Bild — die
/// Bildmarke, nur in Bewegung. Gezeichnet wird über `paintMitFahrBarMark`
/// mit einer Pose: Geometrie und Farben bleiben die der Marke, hier lebt
/// nur die Choreografie. Keine Animations-Library — dieselbe Linie wie
/// Charts und Mood-Faces.
///
/// Ein Tipp überspringt alles; bei reduzierter Bewegung (Systemeinstellung)
/// erscheint der Splash gar nicht.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/widgets/mitfahrbar_mark.dart';
import '../../data/providers.dart';

/// Legt den Splash einmalig über den App-Start. Liegt im `builder` der
/// MaterialApp über allem — auch über Login und Sperr-Schirm: erst der
/// erste Eindruck, dann die Pflichten.
class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final wanted =
        ref.watch(splashEnabledProvider) &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    return Stack(
      children: [
        widget.child,
        if (wanted && !_done)
          SplashOverlay(onFinished: () => setState(() => _done = true)),
      ],
    );
  }
}

/// Die eigentliche Animation. Öffentlich, damit der Flow-Test sie finden
/// kann, ohne die Choreografie zu kennen.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 2600),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              setState(() => _fading = true);
            }
          })
          ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Wer den Auftritt kennt, muss ihn nicht noch einmal ansehen.
  void _skip() {
    if (!_fading) _controller.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        onEnd: () {
          if (_fading) widget.onFinished();
        },
        child: ColoredBox(
          color: theme.colorScheme.surface,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _Scene(t: _controller.value),
          ),
        ),
      ),
    );
  }
}

/// Ein Bild der Choreografie zum Zeitpunkt [t] ∈ [0, 1].
///
/// Drehbuch (Anteile der 2,6 s):
///   0,00–0,32  Einfahren von rechts, Streaks, nur der Fahrer vorn
///   0,30–0,64  Bremsen: Nase taucht ein, federt elastisch zurück
///   0,58–0,80  Hintere Köpfe ploppen auf, Schriftzug blendet ein
///   0,80–1,00  Losfahren nach links, Streaks wieder an
class _Scene extends StatelessWidget {
  const _Scene({required this.t});

  final double t;

  /// Teilstück [begin]–[end] von [t] auf 0–1, durch [curve] gezogen.
  double _seg(double begin, double end, Curve curve) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // „Nicht zu klein": die halbe Bildschirmbreite, mit Obergrenze
        // für Tablets und Desktop-Fenster.
        final carWidth = math.min(w * 0.5, 340.0);
        final carHeight = carWidth / mitFahrBarMarkAspect;

        // Fahrweg: von rechts außerhalb in die Mitte, am Ende nach links
        // hinaus. Die Kurven geben das Abbremsen/Beschleunigen her.
        final driveIn = _seg(0.0, 0.32, Curves.easeOutCubic);
        final driveOut = _seg(0.80, 1.0, Curves.easeInCubic);
        final centerX =
            lerpDouble(w + carWidth, w / 2, driveIn)! -
            (w / 2 + carWidth * 1.2) * driveOut;

        // Bremsnicken: Eintauchen, dann elastisches Zurückfedern — das
        // Überschwingen der Kurve ist das Nachwippen des Fahrwerks.
        final press = _seg(0.30, 0.42, Curves.easeOut);
        final release = _seg(0.42, 0.64, Curves.elasticOut);
        // Anfahren: ein Hauch Aufbäumen (~⅓ des Bremswinkels, bewusst
        // marginal), klingt bis zum Bildrand wieder ab.
        final launch =
            _seg(0.80, 0.86, Curves.easeOut) *
            (1 - _seg(0.90, 1.0, Curves.easeIn));
        final pitch = 0.10 * press * (1 - release) - 0.035 * launch;

        // In Fahrt wippt die Karosserie leicht; im Stand steht sie.
        final rolling = math.max(1 - _seg(0.26, 0.36, Curves.easeIn), driveOut);
        final lift = math.sin(t * math.pi * 14) * 1.1 * rolling;

        // Die hinteren beiden ploppen nacheinander auf; easeOutBack
        // schwingt kurz über 1 hinaus — das „Plopp".
        final pose = MitFahrBarPose(
          pitch: pitch,
          lift: lift,
          streakOpacity: rolling,
          headScales: [
            1,
            _seg(0.58, 0.70, Curves.easeOutBack),
            _seg(0.66, 0.78, Curves.easeOutBack),
          ],
        );

        final wordmark = _seg(0.58, 0.74, Curves.easeOut);

        return Stack(
          children: [
            Positioned(
              left: centerX - carWidth / 2,
              top: h / 2 - carHeight / 2,
              width: carWidth,
              height: carHeight,
              child: CustomPaint(painter: _SplashCarPainter(pose)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: h / 2 + carHeight / 2 + AppSpacing.l,
              child: Opacity(
                opacity: wordmark,
                child: Column(
                  children: [
                    const MitFahrBarWordmark(fontSize: 30),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Die faire App für eure Fahrgemeinschaft',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SplashCarPainter extends CustomPainter {
  _SplashCarPainter(this.pose);

  final MitFahrBarPose pose;

  @override
  void paint(Canvas canvas, Size size) =>
      paintMitFahrBarMark(canvas, size, MitFahrBarMarkVariant.gradient, pose);

  // Jedes Bild ist eine neue Pose — der AnimatedBuilder taktet ohnehin.
  @override
  bool shouldRepaint(_SplashCarPainter oldDelegate) => true;
}
