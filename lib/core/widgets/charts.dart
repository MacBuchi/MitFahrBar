/// charts.dart – Die Diagramme der Startseite, von Hand gezeichnet.
///
/// Bewusst ohne Diagramm-Bibliothek: wenige Formen reichen, und so bleiben
/// Marken, Abstände und Farben in denselben Tokens wie der Rest der App.
///
/// Gestaltungsregeln, die hier durchgehalten werden:
/// * Getrennt wird durch Fläche (2 px Lücke), nie durch einen Rahmen.
/// * Nur das Datenende ist gerundet, die Grundlinie bleibt eckig.
/// * Beschriftungen tragen Text-, niemals Datenfarben – die Zuordnung
///   übernimmt die farbige Marke daneben.
/// * Achsen und Hilfslinien sind durchgezogene Haarlinien, eine Stufe vom
///   Untergrund entfernt – nie gestrichelt, das läse sich als Schwellwert.
/// * **Werte trägt entweder die Direktbeschriftung oder die Achse, nie
///   beides.** Der gestapelte Balken hat wenige Zeilen und bleibt deshalb
///   bei der Direktbeschriftung; Wochen-Zeitreihen (Ersparnis, Preise)
///   tragen eine Wertachse und leben in eigenen Dateien
///   (`savings_chart.dart`, `price_chart.dart`).
///
/// Das Monats-Säulendiagramm „Fahrten pro Monat" wurde am 02.08.2026 durch
/// die Wochen-Säulen im Ersparnis-Diagramm ersetzt — eine Zeitachse statt
/// zwei (Entscheidung der Gruppe: eine Karte, ein Zoom). Seine
/// Jahresgrenzen-Marke (#129) lebt dort weiter.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chart_data.dart';
import '../tokens.dart';

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
        const MixLegend(),
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
                    child: StackedMixBar(row: row, maxTotal: maxTotal),
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

/// Der Balken einer Person allein — öffentlich, weil die Statistik-Seite ihn
/// in einem zweizeiligen Layout (Kopfzeile mit Saldo, darunter der Balken)
/// wiederverwendet. Farben und Stapelreihenfolge bleiben an genau einer
/// Stelle: hier.
class StackedMixBar extends StatelessWidget {
  const StackedMixBar({super.key, required this.row, required this.maxTotal});

  final ParticipationRow row;

  /// Größte Zeilensumme der Karte — gemeinsame Skala aller Balken.
  final double maxTotal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
    );
  }
}

/// Die Legende zu [StackedMixBar] — Startseite und Statistik-Seite zeigen
/// dieselben drei Begriffe, sonst hießen dieselben Farben zweierlei.
class MixLegend extends StatelessWidget {
  const MixLegend({super.key});

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
