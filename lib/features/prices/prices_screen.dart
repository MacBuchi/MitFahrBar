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

import '../../data/providers.dart';
import '../../models/price_area.dart';
import 'price_history_charts.dart';
import '../../core/system_insets.dart';

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
      padding: withSystemBottom(context, const EdgeInsets.all(16)),
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
///
/// **Kein „Jetzt abfragen" mehr.** Bis zum Abschalten des Live-Takts stand
/// hier ein Knopf, der eine Umkreisabfrage auslöste; die Wochenwerte kommen
/// jetzt ausschließlich aus dem Archiv, und der Knopf hätte nur noch eine
/// Rohschicht gefüllt, die niemand mehr verdichtet — also sichtbar nichts
/// getan. Ein späterer „Tankdaumen" (aktueller Preis gegen das Perzentil
/// der Woche) bekommt seinen eigenen Weg; er ist eine Nutzeraktion und
/// genau die Nutzung, um die Tankerkönig bittet.
class _PriceOverview extends ConsumerWidget {
  const _PriceOverview({required this.area});

  final PriceArea area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: withSystemBottom(context, const EdgeInsets.all(16)),
      children: [
        Text(area.label, style: theme.textTheme.titleMedium),
        Text(
          'Umkreis ${area.radiusKm.toStringAsFixed(0)} km · '
          'je Woche das 10. Perzentil aller Messungen',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        // Verläufe + Quellenangabe: dasselbe Widget wie die Sektion
        // „Spritpreise" der Statistik-Seite.
        const PriceHistoryCharts(),
      ],
    );
  }
}
