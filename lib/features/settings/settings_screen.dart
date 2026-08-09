/// settings_screen.dart – Parameter der Gruppe (Issues #91, #139).
///
/// Der lange offene „Parameter"-Screen aus KONZEPT.md 5.5: Bis v0.32 lagen
/// Arbeitsweg und Kraftstoffpreise zwar längst je Gruppe in `settings`,
/// aber ohne Oberfläche — für die Gruppen war die Strecke damit faktisch
/// fest verdrahtet (Issue #91).
///
/// **Das Kriterium für dieses Formular ist nicht „Kosten", sondern: Der Wert
/// darf die Punkte nie berühren.** Arbeitsweg und Kraftstoffpreise gehen in
/// Kilometer und Ersparnis ein, Abfahrtszeiten und Treffpunkt (#139) nur in
/// Banner und Benachrichtigung — beides lässt die Fairness-Rechnung
/// unangetastet. `one_way_factor` und `points_weight` fehlen deshalb weiter
/// mit Absicht: Sie verschieben rückwirkend die Punkte aller, und
/// `points_weight` ist die dokumentierte Rückfahrkarte der Fairness-Regel —
/// die gehört in eine Migration, nicht in ein Formular, das jedes Mitglied
/// öffnen kann.
///
/// Zwei Tabellen, ein Formular: Die Kosten-Werte liegen in `settings`
/// (`(group_id, key) → numeric`), die Vorgaben in `group_defaults` — eine
/// Uhrzeit und ein Treffpunkt passen in eine Zahlenspalte nicht hinein. Der
/// Speichern-Knopf schreibt beides, in dieser Reihenfolge.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_config.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/app_settings.dart';
import '../../models/group_defaults.dart';
import '../../models/notification_prefs.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final defaults = ref.watch(groupDefaultsProvider);

    // Erst mit BEIDEN Ständen bauen: Ein Formular, das die Vorgaben
    // nachlädt, überschriebe die frisch getippte Uhrzeit beim Eintreffen.
    return Scaffold(
      appBar: AppBar(title: const Text('Parameter')),
      body: switch ((settings, defaults)) {
        (AsyncData(value: final loaded), AsyncData(value: final vorgaben)) =>
          _Form(settings: loaded, defaults: vorgaben),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          Center(child: Text('Fehler beim Laden: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.settings, required this.defaults});

  final AppSettings settings;
  final GroupDefaults defaults;

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
  late final _meetingPoint = TextEditingController(
    text: widget.defaults.meetingPoint ?? '',
  );

  // Die Uhrzeiten liegen im State und nicht in einem Controller: Es gibt
  // nichts zu tippen, nur zu wählen — und `null` ist ein echter Wert
  // („nicht gepflegt"), kein leerer Text.
  late DayTime? _outbound = widget.defaults.outboundTime;
  late DayTime? _return = widget.defaults.returnTime;

  /// Der Gruppen-Schalter (#213). Er steht hier, obwohl er kein Preis ist:
  /// Das Kriterium dieses Screens ist „der Wert darf die Punkte nie
  /// berühren", und das hält er ein — er verschiebt keine einzige
  /// eingetragene Fahrt, nur künftige Vorschläge.
  late bool _carAssignment = widget.settings.carAssignmentEnabled;

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
    _meetingPoint.dispose();
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
      carAssignmentEnabled: _carAssignment,
    );

    // Frisch gebaut statt kopiert: Ein geleertes Feld muss den alten Wert
    // wirklich löschen. Genau deshalb hat `GroupDefaults` kein `copyWith`.
    final point = _meetingPoint.text.trim();
    final defaults = GroupDefaults(
      outboundTime: _outbound,
      returnTime: _return,
      meetingPoint: point.isEmpty ? null : point,
    );

    final repository = ref.read(carpoolRepositoryProvider);
    try {
      await repository.saveSettings(updated);
      await repository.saveGroupDefaults(defaults);
    } catch (error) {
      if (!mounted) return;
      // Auch im Fehlerfall neu laden: Scheitert der zweite Schreib, ist der
      // erste trotzdem draußen — ohne das zeigte der Screen zwei
      // verschiedene Wahrheiten über dieselbe Gruppe.
      ref.invalidate(settingsProvider);
      ref.invalidate(groupDefaultsProvider);
      setState(() {
        _saving = false;
        _error = 'Speichern fehlgeschlagen: $error';
      });
      return;
    }
    // Statistik, Ersparnis und Charts hängen alle am settingsProvider —
    // ohne die Invalidierung zeigten sie bis zum nächsten Login die alten
    // Kilometer. Am `groupDefaultsProvider` hängen Banner und Ausgangskorb.
    ref.invalidate(settingsProvider);
    ref.invalidate(groupDefaultsProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Parameter gespeichert.')));
    unawaited(Navigator.of(context).maybePop());
  }

  /// Zeit wählen — oder wieder leeren. Ohne den zweiten Weg wäre eine einmal
  /// gesetzte Abfahrtszeit nicht mehr loszuwerden; „nicht gepflegt" ist aber
  /// ein Zustand, den es geben muss (Gruppen ohne feste Zeiten).
  Future<void> _pickTime({
    required String helpText,
    required DayTime? current,
    required DayTime fallback,
    required ValueChanged<DayTime> onPicked,
  }) async {
    final start = current ?? fallback;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: start.hour, minute: start.minute),
      helpText: helpText,
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(DayTime(picked.hour, picked.minute)));
  }

  Widget _timeTile({
    required IconData icon,
    required String label,
    required String helpText,
    required DayTime? value,
    required DayTime fallback,
    required ValueChanged<DayTime?> onChanged,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(
      value == null ? 'Nicht festgelegt' : '${value.format()} Uhr',
    ),
    trailing: value == null
        ? null
        : IconButton(
            tooltip: '$label leeren',
            icon: const Icon(Icons.backspace_outlined),
            onPressed: _saving ? null : () => setState(() => onChanged(null)),
          ),
    onTap: _saving
        ? null
        : () => unawaited(
            _pickTime(
              helpText: helpText,
              current: value,
              fallback: fallback,
              onPicked: onChanged,
            ),
          ),
    contentPadding: EdgeInsets.zero,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: [
        Text(
          'Diese Werte gelten für eure Gruppe. Die Punkte ändern sich '
          'dadurch nicht — weder rückwirkend noch künftig.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.l),
        Text('Strecke & Kosten', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Gehen in Kilometer und gesparte Kosten ein.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s),
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
        const Divider(height: 40),
        Text('Fahrt & Treffpunkt', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Was für jede Fahrt gilt. MitFahrBar schreibt es auf die Übersicht '
          'und in die Benachrichtigung, damit niemand nachfragen muss. '
          'Leer lassen ist in Ordnung — dann steht dort nichts davon.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s),
        _timeTile(
          icon: Icons.wb_twilight,
          label: 'Abfahrt hin',
          helpText: 'Abfahrt zur Arbeit',
          value: _outbound,
          // Nur der Startwert des Wählers, nichts Gespeichertes — eine
          // Vorgabezeit zu erfinden hieße, sie der Gruppe unterzuschieben.
          fallback: const DayTime(7, 30),
          onChanged: (value) => _outbound = value,
        ),
        _timeTile(
          icon: Icons.nights_stay_outlined,
          label: 'Abfahrt zurück',
          helpText: 'Abfahrt nach Hause',
          value: _return,
          fallback: const DayTime(16, 30),
          onChanged: (value) => _return = value,
        ),
        const SizedBox(height: AppSpacing.s),
        TextField(
          controller: _meetingPoint,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Treffpunkt',
            helperText: 'Zum Beispiel „Parkplatz Rathaus".',
          ),
        ),
        const Divider(height: 40),
        Text('Autos & Zuordnung', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'An: Wer fährt, kann die Abfahrt seines Autos für einen einzelnen '
          'Tag verschieben; Mitfahrende sagen zu oder ab und suchen sich ihr '
          'Auto aus.\n'
          'Aus: Für alle gilt die Abfahrt von oben — auch in den '
          'Benachrichtigungen.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _carAssignment,
          onChanged: (value) => setState(() => _carAssignment = value),
          title: const Text('Leute einzelnen Autos zuordnen'),
          subtitle: Text(
            _carAssignment
                // Der Rückweg ist der halbe Zweck des Schalters: Abgelegte
                // Zeiten und Zusagen werden inert, nicht gelöscht.
                ? 'Ausschalten nimmt nichts weg — eingetragene Zeiten und '
                      'Zusagen gelten wieder, sobald ihr es erneut einschaltet.'
                : 'Zeiten je Auto und Zusagen sind ausgeblendet und wirken '
                      'nicht. Gespeichert bleiben sie.',
          ),
        ),
        Text(
          'Umgelegt mitten in der Woche gilt es sofort — auch für Tage, zu '
          'denen schon eine Erinnerung verschickt wurde.',
          style: theme.textTheme.bodySmall,
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
          'Alles hier pflegt ihr selbst. Für die Ersparnis reicht ein '
          'grober Wert.',
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
