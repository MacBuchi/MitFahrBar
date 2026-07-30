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
import '../../core/widgets/marked_date_picker.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/plan_ride.dart';
import '../../models/trip.dart';
import 'trip_editor_seed.dart';

class TripEditorScreen extends ConsumerStatefulWidget {
  const TripEditorScreen({super.key, this.tripId, this.seed});

  final String? tripId;

  /// Vorbelegung aus dem Eintragen-je-Auto-Ablauf des Planers (Issue #62).
  final TripEditorSeed? seed;

  @override
  ConsumerState<TripEditorScreen> createState() => _TripEditorScreenState();
}

class _TripEditorScreenState extends ConsumerState<TripEditorScreen> {
  DateTime _date = _today();
  final Set<String> _full = {};
  final Set<String> _oneWay = {};
  String? _manualDriverId;
  bool _initialized = false;

  /// Für welchen Tag die Auswahl zuletzt aus dem Wochenplan vorbelegt wurde —
  /// `null`, solange die Plan-Daten noch nicht da sind.
  DateTime? _prefilledFor;

  /// Sobald von Hand gewählt wurde, wird nie mehr vorbelegt — auch dann
  /// nicht, wenn die Plan-Daten erst nach dem ersten Tipp eintreffen.
  bool _dirty = false;
  bool _saving = false;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isEdit => widget.tripId != null;

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null && !_isEdit) {
      _date = seed.date;
      _full.addAll(seed.fullIds);
      _oneWay.addAll(seed.oneWayIds);
      _manualDriverId = seed.driverId;
      // Der Seed ist eine getroffene Entscheidung, keine Vorauswahl:
      // `_dirty` sperrt den Plan-Prefill (Issue #65) von Anfang an, damit
      // spät eintreffende Plan-Daten die Insassen dieses Autos nie räumen —
      // die wären die des GANZEN Tages, nicht die dieses Autos.
      _dirty = true;
      _prefilledFor = seed.date;
    }
  }

  String get _title {
    if (_isEdit) return 'Fahrt bearbeiten';
    final seed = widget.seed;
    if (seed == null) return 'Fahrt eintragen';
    return 'Fahrt eintragen · Auto ${seed.carNumber}/${seed.carCount}';
  }

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
      _dirty = true;
      if (_full.contains(personId)) {
        _full.remove(personId);
        // 1-way braucht jemanden, der wirklich fährt: Bleibt sonst niemand
        // voll dabei, geht es direkt auf „raus" statt in einen Zustand, in
        // dem kein Fahrer mehr möglich ist (Issue #61).
        if (_full.isNotEmpty) _oneWay.add(personId);
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
    // versehentlicher Doppel-Eintrag soll auffallen -> Rückfrage. Der
    // Je-Auto-Ablauf des Planers sagt vorher an, wie viele Fahrten es am
    // Tag schon geben muss — bis zu dieser Zahl schweigt die Rückfrage,
    // eine unerwartete Fremd-Fahrt liegt darüber und fragt weiter nach.
    if (!_isEdit) {
      final sameDay = ref
          .read(tripsProvider)
          .value!
          .where((t) => _sameDay(t.date, _date))
          .length;
      final seed = widget.seed;
      final expected = seed != null && _sameDay(seed.date, _date)
          ? seed.expectedSameDayTrips
          : 0;
      if (sameDay > expected) {
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
        // `true` ist der Rückgabekanal des Je-Auto-Ablaufs im Planer: Erst
        // ein erfolgreiches Speichern öffnet dort das nächste Auto.
        context.pop(true);
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

  /// Wer am Tag [day] schon in einer ANDEREN Fahrt voll drinsteht (Fahrer
  /// oder Mitfahrer), ist hier nicht mehr wählbar — eine Doppel-Teilnahme
  /// zählte die Punkte doppelt (#143). 1-way sperrt bewusst nicht: Wer nur
  /// eine Richtung mitgefahren ist, dem kann der Rückweg noch fehlen.
  static Set<String> _bookedElsewhere(
    List<Trip> trips,
    DateTime day,
    String? ownTripId,
  ) => {
    for (final t in trips)
      if (t.id != ownTripId && _sameDay(t.date, day))
        for (final e in t.participations.entries)
          if (e.value != ParticipationStatus.oneWay) e.key,
  };

  /// „Anna", „Anna und Bernd", „Anna, Bernd und Clara" — für Meldungen,
  /// die Personen aufzählen.
  static String _joinNames(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} und ${names.last}';

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
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isEdit && !_initialized) {
      final trip = trips.where((t) => t.id == widget.tripId).firstOrNull;
      if (trip != null) _initFromTrip(trip);
      _initialized = true;
    }

    // Vor dem Prefill-Block berechnen: Der mutiert _full/_oneWay, und
    // Belegte dürfen gar nicht erst in die Vorauswahl geraten.
    final booked = _bookedElsewhere(trips, _date, widget.tripId);

    // Neue Fahrt: Teilnehmer aus dem Wochenplan des gewählten Tages
    // vorbelegen (Issue #65). Mutation im Build wie bei _initFromTrip —
    // der restliche Build rechnet direkt mit der frischen Auswahl
    // (Fahrer-Vorschlag, Kachel-Zustand).
    if (!_isEdit && !_dirty) {
      final rides = ref.watch(dayAvailabilityProvider(_date)).value;
      if (_prefilledFor != _date) {
        // Sofort leeren: Zwischen Datumswechsel und Datenankunft darf keine
        // Vorauswahl des alten Tages stehen — sonst speichert ein schneller
        // Tipp die falschen Leute.
        _full.clear();
        _oneWay.clear();
        if (rides != null) {
          for (final e in rides.entries) {
            // Auf einem Tag mit bestehender Fahrt wählte der Prefill sonst
            // genau die schon Eingetragenen vor — ein schnelles „Speichern"
            // legte dieselben Leute ein zweites Mal an (#143).
            if (booked.contains(e.key)) continue;
            (e.value == PlanRide.full ? _full : _oneWay).add(e.key);
          }
          _prefilledFor = _date;
        }
      }
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

    // Ausgewählt bleibt immer bedienbar — eine Auswahl (Bearbeiten,
    // Planner-Seed, Datumswechsel) fällt nie still weg. Wer trotzdem
    // anderswo belegt ist, wird stattdessen unten namentlich gemeldet.
    bool tileEnabled(Person p) =>
        !booked.contains(p.id) ||
        _full.contains(p.id) ||
        _oneWay.contains(p.id);
    final doubleBooked = [
      for (final p in visible)
        if (booked.contains(p.id) &&
            (_full.contains(p.id) || _oneWay.contains(p.id)))
          p.name,
    ];

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
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          _DateRow(
            date: _date,
            // Tage mit Fahrt bekommen im Kalender einen Punkt (#83) — so
            // sieht man beim Nachtragen sofort, welche Tage noch fehlen.
            tripDates: {
              for (final t in trips)
                DateTime(t.date.year, t.date.month, t.date.day),
            },
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.m),
          _DriverSlot(
            driver: driverId == null ? null : byId[driverId],
            suggested: suggestedId == null ? null : byId[suggestedId],
            overridden: driverId != suggestedId,
            onAccept: (id) => setState(() {
              _manualDriverId = id;
              _dirty = true;
            }),
            onReset: () => setState(() => _manualDriverId = null),
          ),
          if (_seatWarning(byId[driverId]) case final warning?) ...[
            const SizedBox(height: AppSpacing.s),
            _EditorWarning(
              icon: Icons.airline_seat_recline_normal_outlined,
              text: warning,
            ),
          ],
          // Die Speichern-Rückfrage („Weitere Fahrt an diesem Tag?") nennt
          // keine Namen — dieses Banner schließt die Lücke, wenn Gewählte
          // anderswo belegt sind (Datumswechsel, Doppel-Eintrag von einem
          // zweiten Gerät).
          if (doubleBooked.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            _EditorWarning(
              icon: Icons.event_repeat,
              text:
                  '${_joinNames(doubleBooked)} '
                  '${doubleBooked.length == 1 ? 'steht' : 'stehen'} an diesem '
                  'Tag schon in einer anderen Fahrt — nochmal gespeichert '
                  'zählen die Punkte doppelt.',
            ),
          ],
          const SizedBox(height: AppSpacing.m),
          Text(
            'Wer ist dabei?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!_isEdit &&
              !_dirty &&
              _prefilledFor == _date &&
              (_full.isNotEmpty || _oneWay.isNotEmpty))
            Text(
              'Vorauswahl aus dem Wochenplan übernommen.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          // Schließt sich mit der Zeile darüber aus: Der Seed setzt `_dirty`.
          if (widget.seed case final seed?
              when !_isEdit && _sameDay(_date, seed.date))
            Text(
              'Vorbelegt aus dem Wochenplan · '
              'Auto ${seed.carNumber} von ${seed.carCount}.',
              style: Theme.of(context).textTheme.bodySmall,
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
                  enabled: tileEnabled(person),
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
                    enabled: tileEnabled(person),
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
/// Fahrt einzutragen, die tatsächlich so stattgefunden hat. Gleiche Linie
/// beim Doppel-Belegt-Hinweis: Die Auswahl bleibt bedienbar, gemeldet wird
/// namentlich.
class _EditorWarning extends StatelessWidget {
  const _EditorWarning({required this.icon, required this.text});

  final IconData icon;
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
          Icon(icon, size: 18, color: scheme.onErrorContainer),
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
  const _DateRow({
    required this.date,
    required this.tripDates,
    required this.onChanged,
  });

  final DateTime date;

  /// Tage mit bereits eingetragener Fahrt — der Kalender markiert sie (#83).
  final Set<DateTime> tripDates;

  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Kein `subtract(Duration(days: 1))`: Am Montag nach der Zeitumstellung
    // im Oktober wäre das Sonntag 23 Uhr statt gestern Mitternacht.
    final yesterday = DateTime(today.year, today.month, today.day - 1);
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
            final picked = await showMarkedDatePicker(
              context: context,
              initialDate: date.isAfter(today) ? today : date,
              firstDate: DateTime(2020),
              // Kein Tag in der Zukunft — dieselbe Regel wie im Planer.
              lastDate: today,
              markedDates: tripDates,
              markedLabel: 'Fahrt schon eingetragen',
            );
            if (picked != null) onChanged(picked);
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
    required this.enabled,
    required this.onTap,
  });

  final Person person;
  final bool isDriver;
  final bool isFull;
  final bool isOneWay;

  /// `false`, wenn die Person am gewählten Tag schon in einer anderen Fahrt
  /// steht (#143) — dann blass und nicht antippbar, wie die gesperrte
  /// Plantag-Kachel im Wochenplaner.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = _buildTile(context);
    if (!isFull || !enabled) return tile;
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
      // Das sichtbare „eingetragen" erklärt die blasse Kachel — ein stummes
      // „–" läse sich nur als „nicht ausgewählt", und der Tap täte nichts.
      _ => (
        scheme.surfaceContainerLow,
        scheme.outlineVariant,
        enabled ? '–' : 'eingetragen',
      ),
    };
    final selected = isFull || isOneWay;

    final tile = InkWell(
      onTap: enabled ? onTap : null,
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
    if (enabled) return tile;
    // Muster der gesperrten Plantag-Kachel im Wochenplaner: blass, Tap tot,
    // der Grund steht für Screenreader in den Semantics.
    return Semantics(
      label: '${person.name}, an diesem Tag schon in einer Fahrt eingetragen',
      enabled: false,
      button: false,
      child: Opacity(opacity: 0.38, child: tile),
    );
  }
}
