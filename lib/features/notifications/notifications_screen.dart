/// notifications_screen.dart – Benachrichtigungen einrichten (Issue #101).
///
/// Der Screen ordnet **dieses Gerät** einer Person zu und pflegt deren
/// Uhrzeiten. Die Zuordnung ist ausdrücklich **kein Login**: Jeder kann jeden
/// wählen, genau wie im Planer jeder für jeden einträgt. Sie ist eine
/// Zustelladresse — „eine Gruppe = ein Login" bleibt unangetastet.
///
/// Die Uhrzeiten stehen bewusst **nicht** unter „Parameter": Dort liegen die
/// gruppenweiten Kosten-Werte, die für alle gelten. Hier entscheidet jede
/// Person für sich.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push_messaging.dart';
import '../../data/providers.dart';
import '../../models/notification_prefs.dart';
import '../../models/person.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String? _token;
  String? _personId;
  NotificationPrefs? _prefs;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Beim Öffnen wird **nicht** nach der Berechtigung gefragt, nur
  /// nachgesehen: Ein ungefragter Dialog wird weggetippt, und Android fragt
  /// danach nie wieder.
  Future<void> _load() async {
    try {
      final token = await ref.read(pushTokenProvider)(ask: false);
      if (!mounted) return;
      if (token == null) {
        setState(() => _loading = false);
        return;
      }
      final state = await ref.read(pushRepositoryProvider).stateFor(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _personId = state.personId;
        _prefs = state.prefs;
        _loading = false;
      });
    } catch (_) {
      // Ohne diesen Zweig bliebe der Ladekreis für immer stehen: Die
      // Ausnahme verschwände still in der async-Funktion, und der Screen
      // sähe aus wie ein Hänger. Bewusst ohne den Fehlertext — er trüge
      // sonst Details aus der Datenbank in die Oberfläche.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    unawaited(_load());
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Führt [action] aus und meldet einen Fehler, statt ihn zu verschlucken.
  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      _report('Speichern fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePerson(String? personId) async {
    final platform = pushPlatform;
    if (platform == null) return;
    await _guard(() async {
      // Erst jetzt fragen — der Nutzer hat gerade eingeschaltet.
      final token = _token ?? await ref.read(pushTokenProvider)(ask: true);
      if (token == null) {
        _report('Ohne erlaubte Benachrichtigungen geht es nicht.');
        return;
      }
      final repository = ref.read(pushRepositoryProvider);
      await repository.register(
        token: token,
        personId: personId,
        platform: platform,
      );

      var prefs = _prefs;
      if (personId != null && (prefs == null || prefs.personId != personId)) {
        // Keine Zeile heißt „keine Benachrichtigungen". Wer sich hier
        // zuordnet, will welche — also legen wir sie mit der Vorbelegung an.
        final state = await repository.stateFor(token);
        prefs = state.prefs ?? NotificationPrefs.initial(personId);
        if (state.prefs == null) await repository.savePrefs(prefs);
      }
      if (!mounted) return;
      setState(() {
        _token = token;
        _personId = personId;
        _prefs = personId == null ? null : prefs;
      });
    });
  }

  Future<void> _save(NotificationPrefs next) => _guard(() async {
    await ref.read(pushRepositoryProvider).savePrefs(next);
    if (mounted) setState(() => _prefs = next);
  });

  Future<void> _pickTime(bool evening) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final current = evening ? prefs.eveningTime : prefs.departureTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: evening ? 'Abends benachrichtigen um' : 'Abfahrt um',
    );
    if (picked == null || !mounted) return;
    final value = DayTime(picked.hour, picked.minute);
    await _save(
      evening
          ? prefs.copyWith(eveningTime: value)
          : prefs.copyWith(departureTime: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final persons = ref.watch(personsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Benachrichtigungen')),
      body: !pushSupported
          ? const _Hint(
              'Auf dieser Plattform gibt es keine Benachrichtigungen. '
              'Sie funktionieren in der Android-App und in der Web-App, '
              'wenn sie zum Startbildschirm hinzugefügt wurde.',
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? _Hint(
              'Die Einstellungen konnten nicht geladen werden. Prüfe die '
              'Verbindung und versuche es noch einmal.',
              onRetry: _retry,
            )
          : persons.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  _Hint('Personen nicht geladen.', onRetry: _retry),
              data: _body,
            ),
    );
  }

  Widget _body(List<Person> persons) {
    final active = [
      for (final p in persons)
        if (p.active) p,
    ]..sort((a, b) => a.name.compareTo(b.name));

    // Die gemerkte Person muss es noch geben: Wird sie auf einem anderen
    // Gerät inaktiv gesetzt — oder wechselt die Anmeldung die Gruppe —,
    // zeigte das Dropdown sonst auf einen Wert ohne Eintrag und Flutter
    // bricht mit „exactly one item" ab.
    final selected = active.any((p) => p.id == _personId) ? _personId : null;
    final prefs = selected == null ? null : _prefs;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Dieses Gerät kann abends zeigen, wie der nächste Tag aussieht — '
          'und Bescheid sagen, wenn sich bis zur Abfahrt noch etwas ändert.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String?>(
          initialValue: selected,
          decoration: const InputDecoration(
            labelText: 'Ich bin',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('niemand')),
            for (final person in active)
              DropdownMenuItem(value: person.id, child: Text(person.name)),
          ],
          onChanged: _busy ? null : _choosePerson,
        ),
        const SizedBox(height: 8),
        Text(
          'Das ist keine Anmeldung — die Gruppe teilt sich einen Zugang. '
          'Die Auswahl sagt nur, für wen dieses Gerät benachrichtigt wird.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (prefs != null) ...[
          const Divider(height: 32),
          SwitchListTile(
            value: prefs.eveningEnabled,
            onChanged: _busy
                ? null
                : (value) => _save(prefs.copyWith(eveningEnabled: value)),
            title: const Text('Abends der Blick auf morgen'),
            subtitle: Text('um ${prefs.eveningTime} Uhr'),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Uhrzeit am Abend'),
            trailing: Text('${prefs.eveningTime} Uhr'),
            onTap: _busy ? null : () => _pickTime(true),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),
          SwitchListTile(
            value: prefs.changesEnabled,
            onChanged: _busy
                ? null
                : (value) => _save(prefs.copyWith(changesEnabled: value)),
            title: const Text('Änderungen bis zur Abfahrt'),
            subtitle: const Text(
              'Wenn jemand den Plan für den Tag noch umstellt.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          ListTile(
            leading: const Icon(Icons.directions_car_outlined),
            title: const Text('Abfahrt'),
            subtitle: const Text('Danach kommt nichts mehr.'),
            trailing: Text('${prefs.departureTime} Uhr'),
            onTap: _busy ? null : () => _pickTime(false),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),
          FilledButton.tonalIcon(
            onPressed: _busy || _token == null
                ? null
                : () => _guard(() async {
                    final sent = await ref
                        .read(pushRepositoryProvider)
                        .sendTest(_token!);
                    // Der Hinweis auf den Startbildschirm ist kein Beiwerk:
                    // Solange die App vorne ist, zeigt weder Android noch
                    // der Browser eine Benachrichtigung an — sie erscheint
                    // dann nur als Leiste in der App.
                    _report(
                      sent
                          ? 'Unterwegs — wechsle kurz zum Startbildschirm, '
                                'dann kommt sie als Benachrichtigung.'
                          : 'Konnte nicht zugestellt werden. Ordne dieses '
                                'Gerät noch einmal zu.',
                    );
                  }),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Test-Benachrichtigung senden'),
          ),
        ],
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.onRetry});

  final String text;

  /// Ohne Knopf bliebe dem Nutzer nur, den Screen zu verlassen und neu zu
  /// öffnen — die App weiß nicht, wann das Netz wiederkommt.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ],
      ],
    ),
  );
}
