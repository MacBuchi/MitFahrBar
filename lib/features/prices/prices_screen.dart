/// prices_screen.dart – Preisarchiv: Bereich einrichten und Verlauf ansehen.
///
/// **Entwicklungsstand, bewusst.** Die Kosten-/Ersparnisrechnung rührt das
/// hier nicht an: `fairness.dart` und `computeStats` sehen die Preisreihen
/// nie. Erst wenn für JEDE gefahrene Woche ein Wert vorliegt, ist eine
/// Umstellung mehr als eine Rechnung mit Löchern — bis dahin zeigt der
/// Screen, was da ist, und sagt, was fehlt.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/price_series.dart';
import '../../core/widgets/price_chart.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';
import '../../models/price_area.dart';

class PricesScreen extends ConsumerWidget {
  const PricesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(priceAreaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Spritpreise')),
      body: area.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const _Message(
          text: 'Die Preisdaten konnten nicht geladen werden.',
        ),
        data: (value) =>
            value == null ? const _AreaSetup() : _PriceOverview(area: value),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// Einrichtung: Ort suchen, einen Treffer wählen, fertig.
class _AreaSetup extends ConsumerStatefulWidget {
  const _AreaSetup();

  @override
  ConsumerState<_AreaSetup> createState() => _AreaSetupState();
}

class _AreaSetupState extends ConsumerState<_AreaSetup> {
  final _query = TextEditingController();
  List<GeoPlace> _hits = const [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await ref.read(priceRepositoryProvider).searchPlace(query);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _error = hits.isEmpty ? 'Dazu wurde kein Ort gefunden.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Die Ortssuche ist gerade nicht erreichbar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(GeoPlace place) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(priceRepositoryProvider)
          .saveArea(
            PriceArea(label: place.label, lat: place.lat, lng: place.lng),
          );
      ref.invalidate(priceAreaProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Der Bereich konnte nicht gespeichert werden.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Wo tankt ihr?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'MitFahrBar sieht sich die Tankstellen im Umkreis von '
          '${defaultRadiusKm.toStringAsFixed(0)} km an und merkt sich je '
          'Woche einen Preis. Die Preise stehen dann hier — in die '
          'Kostenrechnung gehen sie nicht ein.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Ort',
            hintText: 'z. B. Bad Rappenau',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _search(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _search,
          icon: const Icon(Icons.search),
          label: const Text('Ort suchen'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        for (final place in _hits)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(place.label),
            onTap: _busy ? null : () => _choose(place),
          ),
      ],
    );
  }
}

/// Der Verlauf, sobald ein Bereich steht.
class _PriceOverview extends ConsumerStatefulWidget {
  const _PriceOverview({required this.area});

  final PriceArea area;

  @override
  ConsumerState<_PriceOverview> createState() => _PriceOverviewState();
}

class _PriceOverviewState extends ConsumerState<_PriceOverview> {
  bool _busy = false;

  /// Wie viele Wochen das Diagramm zeigt.
  static const _weeks = 26;

  Future<void> _sampleNow() async {
    setState(() => _busy = true);
    // Der Knopf meldet keinen Erfolg, den er nicht geprüft hat: Die Function
    // antwortet auch bei gescheitertem Abruf mit 200 und nennt den Ausgang
    // im Rumpf. Dieselbe Klasse wie der tote Update-Knopf in 0.37.0.
    final result = await ref.read(priceRepositoryProvider).sampleNow();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? '${result.stored} Tankstellen abgefragt. Der Wochenwert '
                    'entsteht beim nächsten Verdichten.'
              : 'Die Preise konnten gerade nicht abgefragt werden.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = ref.watch(priceWeeksProvider);
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.area.label, style: theme.textTheme.titleMedium),
        Text(
          'Umkreis ${widget.area.radiusKm.toStringAsFixed(0)} km · '
          'je Woche das 10. Perzentil aller Messungen',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _sampleNow,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: const Text('Jetzt abfragen'),
        ),
        const SizedBox(height: 24),
        if (weeks.hasError || settings.hasError)
          const _Message(text: 'Die Wochenwerte konnten nicht geladen werden.')
        else if (weeks.isLoading || settings.isLoading)
          const Center(child: CircularProgressIndicator())
        else
          ..._charts(
            context,
            stored: weeks.value ?? const [],
            settingsValue: settings.value!,
          ),
        const SizedBox(height: 24),
        // Pflichtangabe der Quelle, nicht Höflichkeit: Die Daten stehen unter
        // CC BY 4.0 und stammen aus der Markttransparenzstelle für
        // Kraftstoffe.
        Text(
          'Preise: Tankerkönig-Spritpreis-API (CC BY 4.0), Daten der '
          'Markttransparenzstelle für Kraftstoffe. Strompreise kommen aus '
          'euren Parametern, nicht aus dem Netz.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _charts(
    BuildContext context, {
    required List<PricePoint> stored,
    required AppSettings settingsValue,
  }) {
    final theme = Theme.of(context);
    final to = IsoWeek.of(DateTime.now());
    var from = to;
    for (var i = 1; i < _weeks; i++) {
      from = IsoWeek.of(from.monday.subtract(const Duration(days: 7)));
    }

    Map<PriceSeries, List<PricePoint>> build(List<PriceSeries> series) => {
      for (final entry in series)
        entry: weeklySeries(
          series: entry,
          from: from,
          to: to,
          stored: stored,
          settings: settingsValue,
        ),
    };

    return [
      Text('Kraftstoff', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      PriceTrendChart(
        lines: build(const [
          PriceSeries.diesel,
          PriceSeries.e5,
          PriceSeries.e10,
        ]),
        unit: '€/l',
      ),
      const SizedBox(height: 24),
      Text('Strom', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      PriceTrendChart(
        lines: build(const [PriceSeries.housePower, PriceSeries.chargingPower]),
        unit: '€/kWh',
      ),
    ];
  }
}
