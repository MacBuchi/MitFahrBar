/// settings_screen.dart – Kosten-Parameter der Gruppe (Issue #91).
///
/// Der lange offene „Parameter"-Screen aus KONZEPT.md 5.5: Bis v0.32 lagen
/// Arbeitsweg und Kraftstoffpreise zwar längst je Gruppe in `settings`,
/// aber ohne Oberfläche — für die Gruppen war die Strecke damit faktisch
/// fest verdrahtet (Issue #91).
///
/// Hier stehen **nur** die Werte, die in Kilometer und Ersparnis eingehen.
/// `one_way_factor` und `points_weight` fehlen mit Absicht: Sie würden
/// rückwirkend die Punkte aller verschieben, und `points_weight` ist die
/// dokumentierte Rückfahrkarte der Fairness-Regel — die gehört in eine
/// Migration, nicht in ein Formular, das jedes Mitglied öffnen kann.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_config.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Parameter')),
      body: switch (settings) {
        AsyncData(value: final loaded) => _Form(settings: loaded),
        AsyncError(:final error) => Center(
          child: Text('Fehler beim Laden: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _commute = TextEditingController(
    text: _format(widget.settings.commuteKm),
  );
  late final _electricity = TextEditingController(
    text: _format(widget.settings.electricityPricePerKwh),
  );
  late final _diesel = TextEditingController(
    text: _format(widget.settings.dieselPricePerLiter),
  );
  late final _petrol = TextEditingController(
    text: _format(widget.settings.petrolPricePerLiter),
  );

  String? _error;
  bool _saving = false;

  /// Deutsche Schreibweise im Feld — dieselbe, die die Gruppe auch tippt.
  static String _format(double value) =>
      value.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _commute.dispose();
    _electricity.dispose();
    _diesel.dispose();
    _petrol.dispose();
    super.dispose();
  }

  double? _read(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final commute = _read(_commute);
    if (commute == null || commute <= 0) {
      setState(() => _error = 'Arbeitsweg bitte als Zahl größer 0.');
      return;
    }
    final prices = {
      'Strompreis': _read(_electricity),
      'Dieselpreis': _read(_diesel),
      'Benzinpreis': _read(_petrol),
    };
    for (final entry in prices.entries) {
      final value = entry.value;
      if (value == null || value < 0) {
        setState(() => _error = '${entry.key} bitte als Zahl ab 0.');
        return;
      }
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    // copyWith statt neuem AppSettings: `one_way_factor` und
    // `points_weight` der Gruppe gehen unverändert wieder mit raus —
    // `saveSettings` schreibt immer die ganze Tabelle.
    final updated = widget.settings.copyWith(
      commuteKm: commute,
      electricityPricePerKwh: prices['Strompreis'],
      dieselPricePerLiter: prices['Dieselpreis'],
      petrolPricePerLiter: prices['Benzinpreis'],
    );

    try {
      await ref.read(carpoolRepositoryProvider).saveSettings(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen: $error';
      });
      return;
    }
    // Statistik, Ersparnis und Charts hängen alle am settingsProvider —
    // ohne die Invalidierung zeigten sie bis zum nächsten Login die alten
    // Kilometer.
    ref.invalidate(settingsProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Parameter gespeichert.')));
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        Text(
          'Diese Werte gelten für eure Gruppe und gehen in Kilometer und '
          'gesparte Kosten ein. Die Punkte ändern sich dadurch nicht.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.l),
        TextField(
          controller: _commute,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Arbeitsweg einfach (km)',
            helperText: 'Hin und zurück rechnet die App selbst.',
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _electricity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Strompreis (€ je kWh)'),
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _diesel,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Dieselpreis (€ je Liter)',
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _petrol,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Benzinpreis (€ je Liter)',
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: AppSpacing.m),
          Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Speichern'),
        ),
        const SizedBox(height: AppSpacing.l),
        Text(
          'Diese Werte pflegt ihr selbst — sie gehen in Kilometer und '
          'Ersparnis ein. Für die Ersparnis reicht ein grober Wert.',
          style: theme.textTheme.bodySmall,
        ),
        // Der Weg zum Preisarchiv sitzt hier und nicht im Hauptmenü: Er
        // gehört neben die Werte, die er eines Tages ablösen soll — und das
        // Menü ist ohnehin lang genug. Nur mit echtem Backend, denn im
        // Demo-Modus gibt es nichts abzufragen (dort entstehen auch die
        // README-Screenshots).
        if (SupabaseConfig.isConfigured) ...[
          const SizedBox(height: AppSpacing.m),
          OutlinedButton.icon(
            onPressed: () => unawaited(context.push('/prices')),
            icon: const Icon(Icons.local_gas_station_outlined),
            label: const Text('Spritpreise ansehen'),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'MitFahrBar merkt sich seit Kurzem selbst, was Diesel und Benzin '
            'in eurem Umkreis kosten. Das ist noch in Arbeit und zählt hier '
            'nicht mit.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
