/// weekly_bars.dart – „Fahrten pro Woche" auf der Statistik-Seite.
///
/// Zwölf Balken, eine Ø-Linie, zwei hervorgehobene Balken (Rekord, laufende
/// Woche). Nach den Regeln aus `charts.dart`: keine Wertachse UND keine
/// Balkenbeschriftung zugleich — die Zahlen tragen der Karten-Untertitel
/// und das Rekord-Label; die Ø-Linie ist durchgezogen (gestrichelt hieße
/// hier „nicht gemessen", siehe Ersparnis- und Preis-Diagramm).
///
/// Alle Beschriftungen sind Widgets UNTER dem Canvas, kein `TextPainter`:
/// Auf Canvas gezeichneter Text taucht in keinem Widget-Finder auf.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../stats_data.dart';
import '../tokens.dart';

class WeeklyBarsChart extends StatelessWidget {
  const WeeklyBarsChart({super.key, required this.bars, this.height = 120});

  final WeeklyTripBars bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final scheme = theme.colorScheme;
    final n = bars.counts.length;

    final record = bars.recordIndex;
    // Die laufende Woche ist der letzte Balken; ist sie zugleich der Rekord,
    // gewinnt der Rekord — zwei Farben auf einem Balken gibt es nicht.
    final current = bars.counts.last > 0 && record != n - 1 ? n - 1 : null;
    final colors = [
      for (var i = 0; i < n; i++)
        if (i == record)
          AppStatsColors.record(brightness)
        else if (i == current)
          AppStatsColors.eco(brightness)
        // Die übrigen Balken sind bewusst blass — Kontext wie die Säulen im
        // Ersparnis-Diagramm; Rekord und laufende Woche sind gemessen.
        else
          scheme.primary.withValues(alpha: 0.35),
    ];

    // Das Rekord-Label steht unter seinem Balken — aber nur, wenn es den
    // Randbeschriftungen nicht in die Quere kommt; der Untertitel der Karte
    // nennt die Rekordwoche ohnehin.
    final showRecordLabel = record != null && record >= 2 && record <= n - 3;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Semantics(
      label: _semanticsLabel(),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeeklyBarsPainter(
                counts: bars.counts,
                colors: colors,
                average: bars.average,
                baseline: scheme.outlineVariant,
                averageLine: scheme.outline,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 16,
            width: double.infinity,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    weekShortLabel(
                      bars.weeks.first,
                      reference: bars.weeks.last,
                    ),
                    style: labelStyle,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('diese Woche', style: labelStyle),
                ),
                if (showRecordLabel)
                  Align(
                    alignment: Alignment(-1 + 2 * (record + 0.5) / n, 0),
                    child: Text(
                      '${weekShortLabel(bars.recordWeek, reference: bars.weeks.last)} · ${bars.recordCount}',
                      style: labelStyle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.xs,
            children: [
              if (record != null)
                _LegendChip(
                  color: AppStatsColors.record(brightness),
                  label: 'Rekord',
                ),
              if (current != null)
                _LegendChip(
                  color: AppStatsColors.eco(brightness),
                  label: 'diese Woche',
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _semanticsLabel() {
    final parts = <String>[
      'Fahrten je Woche, letzte ${bars.counts.length} Wochen',
      'im Schnitt ${bars.average.toStringAsFixed(1)} Fahrten',
      'Rekordwoche ${bars.recordWeek} mit ${bars.recordCount} Fahrten',
    ];
    return parts.join(', ');
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

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

class _WeeklyBarsPainter extends CustomPainter {
  _WeeklyBarsPainter({
    required this.counts,
    required this.colors,
    required this.average,
    required this.baseline,
    required this.averageLine,
  });

  final List<int> counts;
  final List<Color> colors;
  final double average;
  final Color baseline;
  final Color averageLine;

  @override
  void paint(Canvas canvas, Size size) {
    final maxCount = counts.fold(0, math.max);
    if (maxCount == 0) return;
    final drawable = size.height - AppChart.hairline;
    double heightOf(num value) => value / maxCount * drawable;

    final slot = size.width / counts.length;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] == 0) continue;
      final left = i * slot + AppChart.surfaceGap / 2;
      final right = (i + 1) * slot - AppChart.surfaceGap / 2;
      final top = size.height - AppChart.hairline - heightOf(counts[i]);
      // Nur das Datenende (oben) ist gerundet, die Grundlinie bleibt eckig.
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          left,
          top,
          right,
          size.height - AppChart.hairline,
          topLeft: const Radius.circular(AppChart.barEndRadius),
          topRight: const Radius.circular(AppChart.barEndRadius),
        ),
        Paint()..color = colors[i],
      );
    }

    // Grundlinie: Haarlinie eine Stufe vom Untergrund entfernt.
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        size.height - AppChart.hairline,
        size.width,
        AppChart.hairline,
      ),
      Paint()..color = baseline,
    );

    // Ø-Linie: durchgezogen — gestrichelt läse sich als „nicht gemessen".
    final averageY = size.height - AppChart.hairline - heightOf(average);
    canvas.drawRect(
      Rect.fromLTWH(0, averageY, size.width, AppChart.hairline),
      Paint()..color = averageLine,
    );
  }

  @override
  bool shouldRepaint(_WeeklyBarsPainter old) =>
      old.average != average ||
      !identical(old.counts, counts) ||
      !identical(old.colors, colors);
}
