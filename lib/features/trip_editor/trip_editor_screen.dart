/// trip_editor_screen.dart – Fahrt anlegen/bearbeiten im Kachel-Flow:
/// Teilnehmer antippen (1× dabei, 2× 1-way), Fahrer wird automatisch
/// nach Fairness-Rang gesetzt und kann per Drag/Tap übersteuert werden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/tokens.dart';
import '../../data/carpool_repository.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/trip.dart';

class TripEditorScreen extends ConsumerStatefulWidget {
  const TripEditorScreen({super.key, this.tripId});

  final String? tripId;

  @override
  ConsumerState<TripEditorScreen> createState() => _TripEditorScreenState();
}

class _TripEditorScreenState extends ConsumerState<TripEditorScreen> {
  DateTime _date = _today();
  final Set<String> _full = {};
  final Set<String> _oneWay = {};
  String? _manualDriverId;
  bool _initialized = false;
  bool _saving = false;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isEdit => widget.tripId != null;

  void _initFromTrip(Trip trip) {
    _date = trip.date;
    for (final e in trip.participations.entries) {
      switch (e.value) {
        case ParticipationStatus.driver:
          _full.add(e.key);
          // Beim Bearbeiten den eingetragenen Fahrer nicht stillschweigend
          // durch den aktuellen Vorschlag ersetzen.
          _manualDriverId = e.key;
        case ParticipationStatus.passenger:
          _full.add(e.key);
        case ParticipationStatus.oneWay:
          _oneWay.add(e.key);
      }
    }
  }

  void _cycle(String personId) {
    setState(() {
      if (_full.contains(personId)) {
        _full.remove(personId);
        _oneWay.add(personId);
        if (_manualDriverId == personId) _manualDriverId = null;
      } else if (_oneWay.contains(personId)) {
        _oneWay.remove(personId);
      } else {
        _full.add(personId);
      }
    });
  }

  Future<void> _save(String driverId) async {
    setState(() => _saving = true);
    final participations = <String, ParticipationStatus>{
      for (final id in _full)
        id: id == driverId
            ? ParticipationStatus.driver
            : ParticipationStatus.passenger,
      for (final id in _oneWay) id: ParticipationStatus.oneWay,
    };
    final repository = ref.read(carpoolRepositoryProvider);
    try {
      if (_isEdit) {
        final existing = ref
            .read(tripsProvider)
            .value!
            .firstWhere((t) => t.id == widget.tripId);
        await repository.updateTrip(
            existing.copyWith(date: _date, participations: participations));
      } else {
        await repository.createTrip(_date, participations);
      }
      ref.invalidate(tripsProvider);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } on DuplicateTripException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Für diesen Tag gibt es schon eine Fahrt.'),
        action: SnackBarAction(
          label: 'Bearbeiten',
          onPressed: () => context.pushReplacement('/trip/${e.existingTripId}'),
        ),
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personsAsync = ref.watch(personsProvider);
    final tripsAsync = ref.watch(tripsProvider);
    final settingsAsync = ref.watch(settingsProvider);

    final persons = personsAsync.value;
    final trips = tripsAsync.value;
    final settings = settingsAsync.value;
    if (persons == null || trips == null || settings == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'Fahrt bearbeiten' : 'Fahrt eintragen')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isEdit && !_initialized) {
      final trip = trips.where((t) => t.id == widget.tripId).firstOrNull;
      if (trip != null) _initFromTrip(trip);
      _initialized = true;
    }

    // Fahrer-Vorschlag aus der Historie OHNE die gerade bearbeitete Fahrt,
    // sonst beeinflusst der bisherige Eintrag seinen eigenen Vorschlag.
    final stats = computeStats(
      [
        for (final t in trips)
          if (t.id != widget.tripId) t,
      ],
      settings,
    );
    final suggestedId = suggestDriver(_full, stats, settings);
    final driverId =
        _manualDriverId != null && _full.contains(_manualDriverId)
            ? _manualDriverId
            : suggestedId;

    final byId = {for (final p in persons) p.id: p};
    final visible = [
      for (final p in persons)
        if (p.active || _full.contains(p.id) || _oneWay.contains(p.id)) p,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Fahrt bearbeiten' : 'Fahrt eintragen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          _DateRow(
            date: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.m),
          _DriverSlot(
            driver: driverId == null ? null : byId[driverId],
            suggested: suggestedId == null ? null : byId[suggestedId],
            overridden: driverId != suggestedId,
            onAccept: (id) => setState(() => _manualDriverId = id),
            onReset: () => setState(() => _manualDriverId = null),
          ),
          const SizedBox(height: AppSpacing.m),
          Text('Wer ist dabei?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final person in visible)
                _PersonTile(
                  person: person,
                  isDriver: person.id == driverId,
                  isFull: _full.contains(person.id),
                  isOneWay: _oneWay.contains(person.id),
                  onTap: () => _cycle(person.id),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Tippen: dabei → 1-way → raus. Fahrer-Kachel aufs Fahrer-Feld '
            'ziehen, um den Vorschlag zu übersteuern.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.l),
          FilledButton.icon(
            onPressed: driverId == null || _saving
                ? null
                : () => _save(driverId),
            icon: const Icon(Icons.check),
            label: Text(_saving
                ? 'Speichern …'
                : driverId == null
                    ? 'Mindestens 1 Person auswählen'
                    : 'Speichern – ${byId[driverId]?.name} fährt'),
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final format = DateFormat('EE, dd.MM.yyyy', 'de');

    return Wrap(
      spacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Heute'),
          selected: date == today,
          onSelected: (_) => onChanged(today),
        ),
        ChoiceChip(
          label: const Text('Morgen'),
          selected: date == tomorrow,
          onSelected: (_) => onChanged(tomorrow),
        ),
        ActionChip(
          avatar: const Icon(Icons.calendar_month, size: 18),
          label: Text(format.format(date)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: today.add(const Duration(days: 30)),
              locale: const Locale('de'),
            );
            if (picked != null) {
              onChanged(DateTime(picked.year, picked.month, picked.day));
            }
          },
        ),
      ],
    );
  }
}

class _DriverSlot extends StatelessWidget {
  const _DriverSlot({
    required this.driver,
    required this.suggested,
    required this.overridden,
    required this.onAccept,
    required this.onReset,
  });

  final Person? driver;
  final Person? suggested;
  final bool overridden;
  final ValueChanged<String> onAccept;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: hovering
                ? scheme.primaryContainer
                : driver == null
                    ? scheme.surfaceContainerHighest
                    : scheme.primaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.l),
            border: Border.all(
              color: hovering ? scheme.primary : scheme.outlineVariant,
              width: hovering ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.directions_car,
                  size: 32,
                  color: driver == null
                      ? scheme.onSurfaceVariant
                      : AppColors.driver),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fahrer',
                        style: Theme.of(context).textTheme.labelMedium),
                    Text(
                      driver?.name ?? 'Teilnehmer auswählen …',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (overridden && suggested != null)
                      Text('Vorschlag wäre: ${suggested!.name}',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (overridden)
                IconButton(
                  tooltip: 'Zurück zum Vorschlag',
                  icon: const Icon(Icons.undo),
                  onPressed: onReset,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.isDriver,
    required this.isFull,
    required this.isOneWay,
    required this.onTap,
  });

  final Person person;
  final bool isDriver;
  final bool isFull;
  final bool isOneWay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = _buildTile(context);
    if (!isFull) return tile;
    // Nur volle Teilnehmer können Fahrer sein — nur sie sind ziehbar.
    return LongPressDraggable<String>(
      data: person.id,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.85, child: _buildTile(context)),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _buildTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, border, label) = switch ((isDriver, isFull, isOneWay)) {
      (true, _, _) => (
          AppColors.driver.withValues(alpha: 0.15),
          AppColors.driver,
          'fährt'
        ),
      (_, true, _) => (
          AppColors.passenger.withValues(alpha: 0.12),
          AppColors.passenger,
          'dabei'
        ),
      (_, _, true) => (
          AppColors.oneWay.withValues(alpha: 0.12),
          AppColors.oneWay,
          '1-way'
        ),
      _ => (scheme.surfaceContainerLow, scheme.outlineVariant, '–'),
    };
    final selected = isFull || isOneWay;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.m),
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.m,
          horizontal: AppSpacing.s,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: border, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
