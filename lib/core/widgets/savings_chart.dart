/// savings_chart.dart – Fahrten und Ersparnis über die Wochen, EINE Karte.
///
/// Selbst gezeichnet wie alle Diagramme hier: `core/chart_data.dart` rechnet
/// (`weeklySavings`), dieser CustomPainter zeichnet nur.
///
/// **Warum Säulen und Kurven zusammen** (entschieden 02.08.2026): Das
/// Monats-Diagramm und die Ersparnis beantworteten dieselbe Frage — was über
/// die Zeit passiert ist — auf zwei getrennten Zeitachsen. Jetzt liegen die
/// Fahrten je Woche als blasse Säulen HINTER den Kurven: eine Zeitachse,
/// ein Zoom, ein Bild. Die Säulen tragen bewusst **keine eigene Wertachse**;
/// sie zeigen, *wann* gefahren wurde, nicht wie oft genau — das war der
/// ausgesprochene Preis der Zusammenlegung.
///
/// **Die Wertachse beginnt bei null**, anders als beim Preis-Diagramm. Dort
/// trägt der Verlauf die Aussage und eine Null-Achse machte jede Schwankung
/// flach; hier trägt die *Höhe* sie — „wie viel ist zusammengekommen" ist
/// eine Menge, und eine abgeschnittene Achse verdoppelte sie optisch.
///
/// Bedienung: Zwei Finger zoomen die Zeitachse, ein Finger schiebt den
/// Ausschnitt, Doppeltipp setzt zurück. Die senkrechte Liste bleibt dabei
/// bedienbar — der Zoom greift erst ab zwei Fingern, das Schieben nur
/// waagerecht. In der Legende blendet ein Tipp auf einen Namen dessen Linie
/// aus; die „Zusammen"-Linie bleibt immer, sie ist die Wahrheit der Karte.
library;

import 'package:flutter/material.dart';

import '../chart_data.dart';
import '../price_series.dart';
import '../tokens.dart';

/// Kleinster Zoom-Ausschnitt. Enger als acht Wochen zeigt nur noch
/// Liniensegmente ohne Verlauf.
const int _minZoomWeeks = 8;

/// Fahrten (Säulen) und kumulierte Ersparnis (Kurven) über die Wochen.
class SavingsTrendChart extends StatefulWidget {
  const SavingsTrendChart({
    super.key,
    required this.chart,
    required this.names,
    this.highlightPersonId,
    this.height = 200,
  });

  final SavingsChart chart;

  /// personId -> Anzeigename, für die Legende.
  final Map<String, String> names;

  /// Wer an diesem Gerät „ich" ist (#121) — die eigene Linie wird dicker
  /// gezeichnet. Ohne Zuordnung (Browser, Demo-Modus) bleibt sie `null` und
  /// alle Linien sind gleich stark.
  final String? highlightPersonId;

  final double height;

  @override
  State<SavingsTrendChart> createState() => _SavingsTrendChartState();
}

class _SavingsTrendChartState extends State<SavingsTrendChart> {
  /// Sichtbarer Ausschnitt als Wochen-Indizes; `null` = alles.
  double? _zoomFrom;
  double? _zoomTo;

  /// Ausgeblendete Personenlinien — reiner Anzeige-Zustand dieses Widgets.
  final Set<String> _hidden = {};

  double _panStartFrom = 0;
  double _panStartTo = 0;
  double _startFocalX = 0;

  int get _lastIndex => widget.chart.weeks.length - 1;
  double get _visibleFrom => _zoomFrom ?? 0;
  double get _visibleTo => _zoomTo ?? _lastIndex.toDouble();
  void _applyWindow(double from, double span) {
    final total = _lastIndex.toDouble();
    final clampedSpan = span.clamp(_minZoomWeeks.toDouble(), total);
    final clampedFrom = from.clamp(0.0, total - clampedSpan);
    setState(() {
      if (clampedSpan >= total) {
        _zoomFrom = null;
        _zoomTo = null;
      } else {
        _zoomFrom = clampedFrom;
        _zoomTo = clampedFrom + clampedSpan;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chart = widget.chart;
    if (chart.weeks.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Noch keine zwei Wochen beisammen.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final ordered = savingsOrder(widget.chart);
    final colors = <String, Color>{
      for (var i = 0; i < ordered.length; i++)
        ordered[i]: personLineColor(i, ordered.length, theme.brightness),
    };
    final textStyle =
        theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    // Achsenspalte hier statt im Painter: Die Gesten brauchen die exakte
    // Breite der Zeichenfläche, sonst zoomt der Finger neben den Punkt.
    final ticks = chart.total > 0
        ? axisTicks(chart.total.ceil(), count: 3)
        : const <int>[];
    final leftPad = ticks.isEmpty
        ? 0.0
        : ticks
                  .map((tick) => _textWidth('$tick €', textStyle))
                  .reduce((a, b) => a > b ? a : b) +
              _SavingsPainter.labelGap;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final plotWidth = constraints.maxWidth - leftPad;
            return GestureDetector(
              // ALLES läuft über den Scale-Erkenner: Zwei Finger zoomen,
              // einer schiebt (scale bleibt dann 1). Ein zusätzlicher
              // Horizontal-Erkenner daneben gewänne die Pinch-Geste, bevor
              // der Zoom sie je sieht — der erste Finger überschreitet
              // seine Wegschwelle waagerecht, der Erkenner schlägt zu, und
              // der Pinch ist tot (im Interaktionstest genau so gemessen,
              // auf dem Gerät wäre es dasselbe). Die senkrechte Liste
              // bleibt bedienbar: Ihr Drag-Erkenner greift bei kleinerem
              // Weg als der Scale-Erkenner.
              onScaleStart: (details) {
                _panStartFrom = _visibleFrom;
                _panStartTo = _visibleTo;
                _startFocalX = details.localFocalPoint.dx;
              },
              onScaleUpdate: (details) {
                final startSpan = _panStartTo - _panStartFrom;
                final focal = ((_startFocalX - leftPad) / plotWidth).clamp(
                  0.0,
                  1.0,
                );
                // Die Woche unter den Fingern bleibt stehen: Der Anker aus
                // dem Gestenbeginn hält den Punkt fest, um den gezoomt
                // wird. Ohne ihn klebte `from` bei 0 und jeder Zoom zöge
                // nach links.
                final anchor = _panStartFrom + focal * startSpan;
                final newSpan = startSpan / details.scale;
                final panned =
                    (details.localFocalPoint.dx - _startFocalX) /
                    plotWidth *
                    newSpan;
                _applyWindow(anchor - focal * newSpan - panned, newSpan);
              },
              onDoubleTap: () => _applyWindow(0, _lastIndex.toDouble()),
              child: Semantics(
                label: _semanticsLabel(ordered),
                excludeSemantics: true,
                child: SizedBox(
                  height: widget.height,
                  child: CustomPaint(
                    painter: _SavingsPainter(
                      chart: chart,
                      order: [
                        for (final id in ordered)
                          if (!_hidden.contains(id)) id,
                      ],
                      colors: colors,
                      highlightPersonId: widget.highlightPersonId,
                      visibleFrom: _visibleFrom,
                      visibleTo: _visibleTo,
                      ticks: ticks,
                      leftPad: leftPad,
                      groupColor: AppColors.eco,
                      columnColor: theme.colorScheme.primary.withValues(
                        alpha: 0.22,
                      ),
                      gridColor: theme.colorScheme.outlineVariant,
                      boundaryColor: theme.colorScheme.outline,
                      textStyle: textStyle,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s),
        _Legend(
          order: ordered,
          colors: colors,
          names: widget.names,
          hidden: _hidden,
          onToggle: (id) => setState(() {
            if (!_hidden.remove(id)) _hidden.add(id);
          }),
          columnColor: theme.colorScheme.primary.withValues(alpha: 0.35),
          estimated: chart.estimatedFrom.isNotEmpty,
          showSavings: chart.total > 0,
        ),
      ],
    );
  }

  double _textWidth(String value, TextStyle style) => (TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: TextDirection.ltr,
  )..layout()).width;

  String _semanticsLabel(List<String> ordered) {
    final chart = widget.chart;
    final parts = <String>[
      if (chart.total > 0) 'Ersparnis zusammen ${chart.total.round()} €',
      for (final id in ordered)
        '${widget.names[id] ?? '—'} ${chart.perPerson[id]!.last.round()} €',
      'Fahrten je Woche als Säulen',
    ];
    return parts.join(', ');
  }

}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.order,
    required this.colors,
    required this.names,
    required this.hidden,
    required this.onToggle,
    required this.columnColor,
    required this.estimated,
    required this.showSavings,
  });

  final List<String> order;
  final Map<String, Color> colors;
  final Map<String, String> names;
  final Set<String> hidden;
  final ValueChanged<String> onToggle;
  final Color columnColor;
  final bool estimated;
  final bool showSavings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Die Säulen brauchen ihre Erklärung genau wie jede Linie — sie
        // haben keine Achse, die sie benennt.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 10, color: columnColor),
            const SizedBox(width: 6),
            Text('Fahrten je Woche', style: theme.textTheme.bodySmall),
          ],
        ),
        if (showSavings)
          const _Swatch(color: AppColors.eco, label: 'Zusammen', bold: true),
        // Ein Tipp auf den Namen blendet die Linie aus — „einzelne Personen
        // abhaken". Nur die Anzeige: An den Zahlen und der Summe ändert ein
        // ausgeblendeter Name nichts.
        for (final id in order)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.s),
            onTap: () => onToggle(id),
            child: Opacity(
              opacity: hidden.contains(id) ? 0.35 : 1,
              child: _Swatch(color: colors[id]!, label: names[id] ?? '—'),
            ),
          ),
        // Die Strichelung braucht ihre eigene Erklärung, sonst liest sie
        // sich als Stilmittel statt als „hier steckt ein Preis drin, den
        // niemand gemessen hat".
        if (estimated)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(14, 3),
                painter: _DashSwatch(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Text(
                'Preis geschätzt',
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

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label, this.bold = false});

  final Color color;
  final String label;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: bold ? 4 : 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: bold
              ? theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.bodySmall,
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

class _SavingsPainter extends CustomPainter {
  _SavingsPainter({
    required this.chart,
    required this.order,
    required this.colors,
    required this.highlightPersonId,
    required this.visibleFrom,
    required this.visibleTo,
    required this.ticks,
    required this.leftPad,
    required this.groupColor,
    required this.columnColor,
    required this.gridColor,
    required this.boundaryColor,
    required this.textStyle,
  });

  final SavingsChart chart;
  final List<String> order;
  final Map<String, Color> colors;
  final String? highlightPersonId;

  /// Sichtbarer Ausschnitt in Wochen-Indizes — der Zoom.
  final double visibleFrom;
  final double visibleTo;

  /// Achsenwerte und Spaltenbreite kommen aus dem Widget: Die Gesten
  /// brauchen dieselbe Geometrie, und zwei Rechnungen drifteten auseinander.
  final List<int> ticks;
  final double leftPad;

  final Color groupColor;
  final Color columnColor;
  final Color gridColor;
  final Color boundaryColor;
  final TextStyle textStyle;

  /// Anteil der Zeichenhöhe, den die höchste Fahrten-Säule bekommt. Bewusst
  /// unten und flach: Die Säulen sind Kontext, nicht die Aussage.
  static const _columnBand = 0.30;

  static const labelGap = 6.0;
  static const _bottomPad = 18.0;

  TextPainter _text(String value) => TextPainter(
    text: TextSpan(text: value, style: textStyle),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - leftPad;
    // Oben bleibt eine halbe Zeilenhöhe frei: Das oberste Achsenlabel sitzt
    // mittig auf seiner Hilfslinie — ohne den Rand malte es über den Canvas
    // hinaus in die Karte (ein CustomPaint schneidet von sich aus nichts ab;
    // im Bildtest lag deshalb Pixel (0,0) mitten im Label).
    final topPad = ticks.isEmpty ? 0.0 : _text('0 €').height / 2;
    final plotHeight = size.height - _bottomPad;
    if (plotWidth <= 0 || plotHeight <= topPad) return;

    final span = visibleTo - visibleFrom;
    if (span <= 0) return;
    double x(double index) =>
        leftPad + (index - visibleFrom) / span * plotWidth;

    // Wertachse: runde Beträge aus `axisTicks`, keine Bruchteile des
    // Maximums — `max / 2` ergab Beschriftungen wie „917 €", eine Zahl, die
    // niemand liest. Ohne Ersparnis (alles 0) entfällt die Achse; die
    // Säulen tragen bewusst keine.
    final max = ticks.isEmpty ? 1.0 : ticks.last.toDouble();
    double y(double value) => plotHeight - value / max * (plotHeight - topPad);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = AppChart.hairline;
    for (final tick in ticks) {
      final position = y(tick.toDouble());
      canvas.drawLine(
        Offset(leftPad, position),
        Offset(size.width, position),
        grid,
      );
      final label = _text('$tick €');
      label.paint(
        canvas,
        Offset(leftPad - label.width - labelGap, position - label.height / 2),
      );
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(leftPad, 0, plotWidth, plotHeight));

    _drawColumns(canvas, x, plotHeight);
    _drawYearBoundaries(canvas, x, plotHeight);

    for (final id in order) {
      _drawLine(
        canvas,
        chart.perPerson[id]!,
        x,
        y,
        colors[id]!,
        id == highlightPersonId ? 3.0 : 1.6,
        // Jede Linie kennt ihre eigene Grenze. Global gestrichelt hätte
        // eine gemessene Diesel-Linie mitgestrichelt, nur weil jemand
        // anderes elektrisch fährt und Strom nie gemessen wird.
        chart.estimatedFrom[id],
      );
    }
    if (chart.total > 0) {
      _drawLine(
        canvas,
        chart.group,
        x,
        y,
        groupColor,
        3.0,
        chart.groupEstimatedFrom,
      );
    }

    canvas.restore();

    // Zeitachse: die Enden des SICHTBAREN Ausschnitts — beim Zoomen wandern
    // sie mit, sonst beschriftete die Achse einen anderen Zeitraum, als das
    // Bild zeigt. Ob die Jahreszahl mit muss, entscheidet `axisLabels`; dort
    // ist es geprüft, auf Canvas wäre es das nicht.
    final firstWeek =
        chart.weeks[visibleFrom.floor().clamp(0, chart.weeks.length - 1)];
    final lastWeek =
        chart.weeks[visibleTo.ceil().clamp(0, chart.weeks.length - 1)];
    final (firstLabel, lastLabel) = axisLabels(firstWeek, lastWeek);
    final first = _text(firstLabel);
    final last = _text(lastLabel);
    final baseline = size.height - first.height;
    first.paint(canvas, Offset(leftPad, baseline));
    last.paint(canvas, Offset(size.width - last.width, baseline));
  }

  /// Fahrten je Woche als blasse Säulen im unteren Band.
  void _drawColumns(
    Canvas canvas,
    double Function(double) x,
    double plotHeight,
  ) {
    var maxCount = 0;
    for (final count in chart.tripCounts) {
      if (count > maxCount) maxCount = count;
    }
    if (maxCount == 0) return;

    final step = x(1) - x(0);
    final width = (step * 0.6).clamp(1.0, AppChart.barMaxThickness);
    final paint = Paint()..color = columnColor;
    for (var i = 0; i < chart.tripCounts.length; i++) {
      final count = chart.tripCounts[i];
      if (count == 0) continue;
      final height = count / maxCount * _columnBand * plotHeight;
      canvas.drawRect(
        Rect.fromLTWH(
          x(i.toDouble()) - width / 2,
          plotHeight - height,
          width,
          height,
        ),
        paint,
      );
    }
  }

  /// Die Jahresgrenze als senkrechte Linie mit Jahreszahl (#129) — aus dem
  /// Monats-Diagramm übernommen: „Im Fahrtendiagramm fehlt eine Abgrenzung
  /// zu den Jahreszahlen." Ohne Marke sieht über Jahre hinweg jede Woche
  /// aus wie die vorige.
  void _drawYearBoundaries(
    Canvas canvas,
    double Function(double) x,
    double plotHeight,
  ) {
    final paint = Paint()
      ..color = boundaryColor
      ..strokeWidth = AppChart.hairline;
    for (var i = 1; i < chart.weeks.length; i++) {
      if (chart.weeks[i].year == chart.weeks[i - 1].year) continue;
      final position = x(i - 0.5);
      canvas.drawLine(Offset(position, 0), Offset(position, plotHeight), paint);
      final label = TextPainter(
        text: TextSpan(
          text: '${chart.weeks[i].year}',
          style: textStyle.copyWith(color: boundaryColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(position + 3, 2));
    }
  }

  void _drawLine(
    Canvas canvas,
    List<double> values,
    double Function(double) x,
    double Function(double) y,
    Color color,
    double width,
    int? estimatedFrom,
  ) {
    // **Ein Pfad je Abschnitt, nicht eine Linie je Woche.** Einzelne
    // Segmente mit rundem Ende ergeben bei rund vier Pixeln Wochenbreite
    // eine Perlenschnur statt einer Kurve — jeder Cap verdickt die Naht.
    // Bei 90 Wochen auf Handybreite sah die durchgezogene Linie dadurch
    // gestrichelt aus, also genau wie das Gegenteil dessen, was sie sagen
    // sollte (gesehen im Demo-Build am 02.08.2026).
    Offset at(int i) => Offset(x(i.toDouble()), y(values[i]));

    // Ab der ersten geschätzten Woche trägt jede folgende Summe sie mit —
    // die Kurve ist kumuliert. Nur den einen Abschnitt zu stricheln
    // behauptete, danach sei wieder alles gemessen.
    final split = (estimatedFrom ?? values.length).clamp(0, values.length - 1);

    if (split > 0) {
      final solid = Path()..moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i <= split; i++) {
        solid.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(
        solid,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    if (split < values.length - 1) {
      final dashedPath = Path()..moveTo(at(split).dx, at(split).dy);
      for (var i = split + 1; i < values.length; i++) {
        dashedPath.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(
        _dash(dashedPath),
        Paint()
          ..color = color.withValues(alpha: 0.55)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.butt
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  /// Denselben Pfad, aber nur jedes zweite Stück.
  ///
  /// Über die **Pfadlänge** gemessen, nicht je Segment: Bei kurzen
  /// Wochenschritten begänne eine segmentweise Strichelung jedes Mal von
  /// vorn und zeichnete damit wieder eine durchgehende Linie.
  Path _dash(Path source) {
    const on = 5.0;
    const off = 4.0;
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + on).clamp(0.0, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + off;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_SavingsPainter old) =>
      old.chart != chart ||
      old.highlightPersonId != highlightPersonId ||
      old.visibleFrom != visibleFrom ||
      old.visibleTo != visibleTo ||
      old.order.join(',') != order.join(',') ||
      old.colors != colors;
}
