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
    final participations = <String, ParticipationStatus>{
      for (final id in _full)
        id: id == driverId
            ? ParticipationStatus.driver
            : ParticipationStatus.passenger,
      for (final id in _oneWay) id: ParticipationStatus.oneWay,
    };

    // Letzte Bremse gegen einen Eintrag in der Zukunft. Der Datumswähler
    // lässt ihn nicht mehr zu, eine ältere Fahrt kann aber ein künftiges
    // Datum tragen — dann soll das Speichern daran scheitern, nicht still
    // durchgehen.
    if (_date.isAfter(_today())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fahrten lassen sich frühestens am Fahrtag eintragen — '
            'für später ist der Wochenplan da.',
          ),
        ),
      );
      return;
    }

    // Eine bestehende Fahrt zu ändern verschiebt die Punkte aller
    // Beteiligten rückwirkend. Das soll niemand aus Versehen tun.
    if (_isEdit) {
      final proceed = await _confirmEdit();
      if (proceed != true) return;
    }

    // Mehrere Fahrten pro Tag sind erlaubt (z. B. zweites Auto), aber ein
    // versehentlicher Doppel-Eintrag soll auffallen -> Rückfrage.
    if (!_isEdit) {
      final sameDay = ref
          .read(tripsProvider)
          .value!
          .where((t) => _sameDay(t.date, _date))
          .length;
      if (sameDay > 0) {
        final proceed = await _confirmSecondTrip(sameDay);
        if (proceed != true) return;
      }
    }

    if (!mounted) return;
    setState(() => _saving = true);
    final repository = ref.read(carpoolRepositoryProvider);
    try {
      if (_isEdit) {
        final existing = ref
            .read(tripsProvider)
            .value!
            .firstWhere((t) => t.id == widget.tripId);
        await repository.updateTrip(
          existing.copyWith(date: _date, participations: participations),
        );
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmEdit() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eingetragene Fahrt ändern?'),
      content: const Text(
        'Diese Fahrt ist bereits eingetragen. Wird sie geändert, verschieben '
        'sich die Punkte aller Beteiligten rückwirkend.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Ändern'),
        ),
      ],
    ),
  );

  Future<bool?> _confirmSecondTrip(int existing) {
    final word = existing == 1 ? 'eine Fahrt' : '$existing Fahrten';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weitere Fahrt an diesem Tag?'),
        content: Text(
          'Für diesen Tag gibt es schon $word. Nur anlegen, wenn wirklich '
          'ein zweites Auto gefahren ist – sonst besser die bestehende '
          'Fahrt bearbeiten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zweite Fahrt anlegen'),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Hinweis, wenn mehr Leute dabei sind als ins Auto des Fahrers passen —
  /// `null`, solange alles passt.
  ///
  /// 1-way zählt als besetzter Platz: Wer eine Richtung mitfährt, sitzt auf
  /// dieser Strecke genauso im Auto.
  String? _seatWarning(Person? driver) {
    if (driver == null) return null;
    final people = _full.length + _oneWay.length;
    if (people <= driver.seats) return null;
    return '${driver.name}s Auto hat ${driver.seats} Sitzplätze — '
        'ihr seid $people.';
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
        appBar: AppBar(
          title: Text(_isEdit ? 'Fahrt bearbeiten' : 'Fahrt eintragen'),
        ),
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
    final stats = computeStats([
      for (final t in trips)
        if (t.id != widget.tripId) t,
    ], settings);
    final suggestedId = suggestDriver(_full, stats, settings);
    final driverId = _manualDriverId != null && _full.contains(_manualDriverId)
        ? _manualDriverId
        : suggestedId;

    final byId = {for (final p in persons) p.id: p};
    final visible = [
      for (final p in persons)
        if (p.active || _full.contains(p.id) || _oneWay.contains(p.id)) p,
    ]..sort((a, b) => a.name.compareTo(b.name));

    // Stammgäste zuerst. In einer rein alphabetischen Liste stehen Leute, die
    // seit Monaten nicht mehr mitfahren, gleichberechtigt zwischen denen, die
    // man täglich antippt — und je länger die Gruppe existiert, desto mehr
    // solcher Karteileichen sammeln sich an.
    bool isRegular(Person p) =>
        stats[p.id]?.participatedRecently(_date) ?? false;
    final regulars = [
      for (final p in visible)
        if (isRegular(p)) p,
    ];
    final occasional = [
      for (final p in visible)
        if (!isRegular(p)) p,
    ];
    // Ohne Historie wäre sonst jeder „länger nicht dabei" — dann lieber eine
    // ungeteilte Liste.
    final split = regulars.isNotEmpty && occasional.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Fahrt bearbeiten' : 'Fahrt eintragen'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          _DateRow(date: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: AppSpacing.m),
          _DriverSlot(
            driver: driverId == null ? null : byId[driverId],
            suggested: suggestedId == null ? null : byId[suggestedId],
            overridden: driverId != suggestedId,
            onAccept: (id) => setState(() => _manualDriverId = id),
            onReset: () => setState(() => _manualDriverId = null),
          ),
          if (_seatWarning(byId[driverId]) case final warning?) ...[
            const SizedBox(height: AppSpacing.s),
            _SeatWarning(text: warning),
          ],
          const SizedBox(height: AppSpacing.m),
          Text(
            'Wer ist dabei?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final person in split ? regulars : visible)
                _PersonTile(
                  person: person,
                  isDriver: person.id == driverId,
                  isFull: _full.contains(person.id),
                  isOneWay: _oneWay.contains(person.id),
                  onTap: () => _cycle(person.id),
                ),
            ],
          ),
          if (split) ...[
            const SizedBox(height: AppSpacing.m),
            Text(
              'Länger nicht dabei',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: AppSpacing.s),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                for (final person in occasional)
                  _PersonTile(
                    person: person,
                    isDriver: person.id == driverId,
                    isFull: _full.contains(person.id),
                    isOneWay: _oneWay.contains(person.id),
                    onTap: () => _cycle(person.id),
                  ),
              ],
            ),
          ],
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
            label: Text(
              _saving
                  ? 'Speichern …'
                  : driverId == null
                  ? 'Mindestens 1 Person auswählen'
                  : 'Speichern – ${byId[driverId]?.name} fährt',
            ),
          ),
        ],
      ),
    );
  }
}

/// Bewusst ein Hinweis und keine Sperre: Zur Not rückt man zusammen oder es
/// fahren zwei Autos. Eine harte Grenze würde jemanden daran hindern, eine
/// Fahrt einzutragen, die tatsächlich so stattgefunden hat.
class _SeatWarning extends StatelessWidget {
  const _SeatWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.s),
      ),
      child: Row(
        children: [
          Icon(
            Icons.airline_seat_recline_normal_outlined,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
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
    final yesterday = today.subtract(const Duration(days: 1));
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
        // Früher stand hier „Morgen". Eine Fahrt im Voraus einzutragen
        // verschiebt die Punkte aller anderen für etwas, das noch nicht
        // passiert ist — geplant wird im Wochenplaner, eingetragen wird
        // frühestens am Fahrtag. „Gestern" ist der häufige Fall dafür,
        // dass man das Eintragen vergessen hat.
        ChoiceChip(
          label: const Text('Gestern'),
          selected: date == yesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        ActionChip(
          avatar: const Icon(Icons.calendar_month, size: 18),
          label: Text(format.format(date)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date.isAfter(today) ? today : date,
              firstDate: DateTime(2020),
              // Kein Tag in der Zukunft — dieselbe Regel wie im Planer.
              lastDate: today,
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
              Icon(
                Icons.directions_car,
                size: 32,
                color: driver == null
                    ? scheme.onSurfaceVariant
                    : AppColors.driver,
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fahrer',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      driver?.name ?? 'Teilnehmer auswählen …',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (overridden && suggested != null)
                      Text(
                        'Vorschlag wäre: ${suggested!.name}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
        'fährt',
      ),
      (_, true, _) => (
        AppColors.passenger.withValues(alpha: 0.12),
        AppColors.passenger,
        'dabei',
      ),
      (_, _, true) => (
        AppColors.oneWay.withValues(alpha: 0.12),
        AppColors.oneWay,
        '1-way',
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
