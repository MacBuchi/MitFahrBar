/// notifications_screen.dart – Benachrichtigungen einrichten (Issue #101).
///
/// **Wer** benachrichtigt wird, steht seit #121 nicht mehr hier, sondern in
/// der Geräte-Zuordnung („Ich bin" im Menü, `data/device_identity.dart`).
/// Sie wirkt auch dort, wo es kein Push gibt, und gehörte deshalb nicht in
/// ein Untermenü, das ohne Push gar nicht erreichbar ist. Hier bleibt, was
/// wirklich zu den Benachrichtigungen gehört: ob dieses Gerät welche bekommt
/// und wann.
///
/// Der Schalter oben ist zugleich der einzige Ort, an dem die App die
/// Berechtigung erfragen darf — ungefragt gefragt wird sie weggetippt, und
/// Android fragt danach nie wieder.
///
/// Die Uhrzeiten stehen bewusst **nicht** unter „Parameter": Dort liegen die
/// gruppenweiten Werte, die für alle gelten — seit #139 auch die
/// Abfahrtszeiten der Fahrt selbst. Hier entscheidet jede Person für sich,
/// wann ihr Gerät sie anspricht.
///
/// **Daher die Namen.** Die „Abfahrt" auf diesem Schirm ist eine persönliche
/// Deadline: Danach nützt keine Meldung mehr, und ein nachgeholter Lauf soll
/// niemanden nachts wecken (`notification_prefs.departure_time`). Die Abfahrt
/// der Gruppe heißt in der Datenbank deshalb `outbound_time` /
/// `return_time` — zwei Bedeutungen unter einem Spaltennamen sieht man beim
/// Lesen einer Query nicht.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_health.dart';
import '../../core/notification_health_probe.dart';
import '../../core/push_messaging.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/group_defaults.dart';
import '../../models/notification_prefs.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with WidgetsBindingObserver {
  String? _token;

  /// Auf welche Person dieses Gerät in `push_devices` steht — `null` heißt
  /// „bekommt keine". Nicht zu verwechseln mit der Geräte-Zuordnung: Die sagt,
  /// wer hier sitzt, diese hier, ob er auch etwas zugestellt bekommt.
  String? _registeredPersonId;
  NotificationPrefs? _prefs;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;

  /// Was Android gerade zulässt (#180). Vorbelegt mit „unbekannt", damit vor
  /// der ersten Antwort nichts behauptet wird.
  NotificationHealth _health = NotificationHealth.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// **Beim Zurückkehren neu lesen, nicht nur beim Öffnen.**
  ///
  /// Der ganze Ablauf schickt den Menschen in die Systemeinstellungen und
  /// erwartet ihn zurück. Ohne das hier stünde nach dem Erlauben weiter die
  /// alte Warnung, und niemand wüsste, ob es geklappt hat. Es ist zugleich
  /// der Grund, warum es diesen Schirm gibt: Android kann jederzeit
  /// widerrufen — und nimmt die Berechtigung nach Monaten der Nichtnutzung
  /// von selbst zurück, ohne sie beim Aufwachen neu zu erteilen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readHealth());
  }

  Future<void> _readHealth() async {
    final health = await ref
        .read(notificationHealthProbeProvider)
        .read(androidPlanChannel);
    if (!mounted) return;
    setState(() => _health = health);
  }

  /// Beim Öffnen wird **nicht** nach der Berechtigung gefragt, nur
  /// nachgesehen: Ein ungefragter Dialog wird weggetippt, und Android fragt
  /// danach nie wieder.
  Future<void> _load() async {
    // Vor allem anderen und unabhängig davon: Ist die Berechtigung entzogen,
    // liefert `pushToken` gar kein Token, und der Schirm sähe schlicht
    // ausgeschaltet aus — ohne zu sagen, warum sich nichts einschalten lässt.
    unawaited(_readHealth());
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
        _registeredPersonId = state.personId;
        _prefs = state.prefs;
        _loading = false;
      });
      // Wer sich seit der letzten Registrierung umbenannt hat — also im Menü
      // eine andere Person gewählt hat —, bekäme sonst weiter die Meldungen
      // der alten. Die Zuordnung im Menü ist die Wahrheit, `push_devices`
      // folgt ihr.
      await _syncPerson();
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

  /// Zieht `push_devices` auf die im Menü gewählte Person nach.
  ///
  /// Läuft still: Wer den Screen öffnet, hat nicht um eine Registrierung
  /// gebeten — nur darum, dass das Richtige eingestellt ist.
  Future<void> _syncPerson() async {
    final registered = _registeredPersonId;
    final token = _token;
    final platform = pushPlatform;
    final me = ref.read(myPersonProvider);
    if (registered == null || token == null || platform == null) return;
    if (me == null || me.id == registered) return;

    await _guard(() async {
      final repository = ref.read(pushRepositoryProvider);
      await repository.register(
        token: token,
        personId: me.id,
        platform: platform,
      );
      final state = await repository.stateFor(token);
      final prefs = state.prefs ?? NotificationPrefs.initial(me.id);
      if (state.prefs == null) await repository.savePrefs(prefs);
      if (!mounted) return;
      setState(() {
        _registeredPersonId = me.id;
        _prefs = prefs;
      });
    });
  }

  /// Der Hauptschalter: Bekommt dieses Gerät Benachrichtigungen?
  ///
  /// Früher war das die Personen-Auswahl — die ist seit #121 im Menü, also
  /// braucht es hier einen eigenen. Er ist zugleich der einzige Ort, an dem
  /// die Berechtigung erfragt werden darf: Der Nutzer hat gerade eingeschaltet.
  Future<void> _setEnabled(bool value) async {
    final platform = pushPlatform;
    final me = ref.read(myPersonProvider);
    if (platform == null || me == null) return;

    await _guard(() async {
      final repository = ref.read(pushRepositoryProvider);

      if (!value) {
        final token = _token;
        if (token != null) await repository.unregister(token);
        if (!mounted) return;
        setState(() {
          _registeredPersonId = null;
          _prefs = null;
        });
        return;
      }

      final token = _token ?? await ref.read(pushTokenProvider)(ask: true);
      if (token == null) {
        _report('Ohne erlaubte Benachrichtigungen geht es nicht.');
        return;
      }
      await repository.register(
        token: token,
        personId: me.id,
        platform: platform,
      );
      // Keine Zeile heißt „keine Benachrichtigungen". Wer hier einschaltet,
      // will welche — also legen wir sie mit der Vorbelegung an.
      final state = await repository.stateFor(token);
      final prefs = state.prefs ?? NotificationPrefs.initial(me.id);
      if (state.prefs == null) await repository.savePrefs(prefs);
      if (!mounted) return;
      setState(() {
        _token = token;
        _registeredPersonId = me.id;
        _prefs = prefs;
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

  /// Der Vorlauf als Auswahl, nicht als Zeitwähler: Gefragt ist eine Dauer
  /// („zehn Minuten vorher"), keine Uhrzeit — ein Zifferblatt dafür wäre die
  /// falsche Frage in der richtigen Optik.
  ///
  /// **Beide Richtungen in EINEM Dialog** (#168). Der Wunsch kam mit einer
  /// Begründung, die den einen Wert widerlegt: Zum Morgen-Treffpunkt sind es
  /// fünfzehn Minuten, zum Treffpunkt für die Rückfahrt dreißig. Zwei
  /// getrennte Zeilen im Screen wären die naheliegende Umsetzung und die
  /// falsche — es bliebe eine Frage, nur eben zweimal gestellt, und der
  /// Screen wüchse um eine Zeile für nichts. Chips statt Radios, weil sieben
  /// Werte × zwei Richtungen als Liste ein scrollender Dialog wären.
  Future<void> _pickLead(NotificationPrefs prefs) async {
    var out = prefs.reminderLeadMinutes;
    var back = prefs.reminderLeadReturnMinutes;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Widget row(String label, int value, void Function(int) onPick) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      for (final minutes in reminderLeadChoices)
                        ChoiceChip(
                          label: Text('$minutes'),
                          selected: value == minutes,
                          onSelected: (_) => setLocal(() => onPick(minutes)),
                        ),
                    ],
                  ),
                ],
              );

          return AlertDialog(
            title: const Text('Wie lange vorher?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('Hinfahrt (Minuten)', out, (v) => out = v),
                const SizedBox(height: AppSpacing.m),
                row('Rückfahrt (Minuten)', back, (v) => back = v),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Übernehmen'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    await _save(
      prefs.copyWith(reminderLeadMinutes: out, reminderLeadReturnMinutes: back),
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
              // Die Liste selbst braucht der Rumpf nicht mehr — nur, dass sie
              // da ist, denn `myPersonProvider` schlägt darin nach.
              data: (_) => _body(),
            ),
    );
  }

  /// Je Blockade eine Karte: was im Weg steht, und der Knopf, der genau
  /// dorthin führt (#180).
  ///
  /// **Der Knopf muss tippbar sein, nicht nur sichtbar.** Genau daran ist
  /// der tote Update-Knopf in 0.37.0 durchgerutscht — deshalb tippt der
  /// Flow-Test ihn an, statt ihn zu finden.
  List<Widget> _blockCards() {
    final probe = ref.read(notificationHealthProbeProvider);
    return [
      for (final block in _health.blocks)
        switch (block) {
          NotificationBlock.permission => _BlockCard(
            icon: Icons.notifications_off_outlined,
            title: 'Android lässt keine Benachrichtigungen zu',
            body:
                'Ohne diese Erlaubnis kommt nichts an — auch nicht, wenn hier '
                'alles eingeschaltet ist. Android nimmt sie auch von selbst '
                'zurück, wenn die App monatelang ungenutzt bleibt.',
            action: 'Erlauben',
            onPressed: probe.openAppNotifications,
          ),
          NotificationBlock.batteryRestricted => _BlockCard(
            icon: Icons.battery_alert_outlined,
            title: 'Der Akkuverbrauch steht auf „Eingeschränkt"',
            body:
                'In diesem Zustand stellt Android gar keine Meldungen mehr zu. '
                'Die normale Akkuoptimierung ist damit nicht gemeint — die '
                'darf anbleiben und stört nicht.',
            action: 'Akku-Einstellung öffnen',
            onPressed: probe.openAppDetails,
          ),
          NotificationBlock.channelOff => _BlockCard(
            icon: Icons.layers_clear_outlined,
            title: 'Die Kategorie „Fahrgemeinschaft" ist ausgeschaltet',
            body:
                'Der Schalter der App kann dabei an sein — Android führt für '
                'jede Kategorie einen eigenen.',
            action: 'Kategorie öffnen',
            onPressed: () => probe.openChannel(androidPlanChannel),
          ),
          NotificationBlock.dndBlocks => _BlockCard(
            icon: Icons.do_not_disturb_on_outlined,
            title: '„Nicht stören" hält die Meldungen zurück',
            body:
                'Du kannst dieser Kategorie erlauben, „Nicht stören" zu '
                'ignorieren. Sie trägt heute alles: den Blick am Abend ebenso '
                'wie die Erinnerung vor der Abfahrt.',
            action: 'Kategorie öffnen',
            onPressed: () => probe.openChannel(androidPlanChannel),
          ),
          // Bewusst ohne Knopf: `setBypassDnd` gilt nur für „nur
          // Prioritäten". Bei totaler Stille kommt nichts durch, und ein
          // Knopf, der nichts löst, wäre ein Versprechen.
          NotificationBlock.dndSilences => const _BlockCard(
            icon: Icons.notifications_paused_outlined,
            title: '„Nicht stören" steht auf völliger Stille',
            body:
                'In diesem Modus lässt Android nichts durch — auch keine '
                'Ausnahme. Solange er läuft, kommt die Erinnerung nicht an; '
                'daran kann die App nichts ändern.',
          ),
          NotificationBlock.channelSilent => _BlockCard(
            icon: Icons.volume_off_outlined,
            title: 'Die Meldungen kommen lautlos an',
            body:
                'Sie erscheinen, machen aber nicht auf sich aufmerksam. Kurz '
                'vor der Abfahrt ist das so gut wie keine Meldung.',
            action: 'Kategorie öffnen',
            onPressed: () => probe.openChannel(androidPlanChannel),
          ),
        },
    ];
  }

  Widget _body() {
    final me = ref.watch(myPersonProvider);

    // Ohne gewählte Person gibt es niemanden, für den man etwas einstellen
    // könnte. Über das Menü ist der Punkt dann ausgegraut — direkt über die
    // Adresse ist er trotzdem erreichbar, und dann erklärt der Screen das,
    // statt leer zu bleiben.
    if (me == null) {
      return const _Hint(
        'Erst festlegen, wer du bist: Das steht im Menü oben rechts unter '
        '„Ich bin". Ohne diese Angabe weiß dieses Gerät nicht, wessen Tag es '
        'melden soll.',
      );
    }

    // Registriert ist das Gerät genau dann, wenn eine Person daran hängt.
    final enabled = _registeredPersonId != null;
    final prefs = enabled ? _prefs : null;

    // Ohne Gruppenzeiten (#139) gibt es nichts, woran eine Erinnerung hinge.
    // Beim Laden gilt „noch nicht da" wie „nicht gepflegt": Der Schalter
    // bleibt kurz gesperrt, statt anzugehen und wieder auszufallen.
    final defaults =
        ref.watch(groupDefaultsProvider).value ?? const GroupDefaults();
    final hasLegTimes =
        defaults.outboundTime != null || defaults.returnTime != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Dieses Gerät kann abends zeigen, wie der nächste Tag aussieht, '
          'Bescheid sagen, wenn sich bis zur Abfahrt noch etwas ändert — und '
          'kurz vor der Abfahrt erinnern.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // Ganz oben, weil alles darunter wirkungslos ist, solange Android
        // blockiert: Ein Schalter, der auf „an" steht, während nichts
        // ankommt, ist die Falle, die #175 gekostet hat.
        ..._blockCards(),
        const Divider(height: 32),
        SwitchListTile(
          value: enabled,
          onChanged: _busy ? null : _setEnabled,
          title: const Text('Benachrichtigungen auf diesem Gerät'),
          subtitle: Text('für ${me.name}'),
          contentPadding: EdgeInsets.zero,
        ),
        Text(
          'Wer das ist, änderst du im Menü unter „Ich bin". Das ist keine '
          'Anmeldung — die Gruppe teilt sich einen Zugang.',
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
          // Der Änderungs-Schalter hängt am Abend-Blick, und das ist keine
          // Anzeigefrage: `dueMessages` in core/push_digest.dart meldet eine
          // Änderung nur, wenn für den Tag schon ein Abend-Push in
          // `push_log` steht — sonst wäre sie die erste Nachricht des Tages
          // und ohne Bezug. Ohne Abend-Blick entsteht diese Zeile nie, der
          // Schalter liefe also vollständig leer. Zwei gleichwertig
          // aussehende Schalter, von denen einer heimlich wirkungslos ist,
          // fallen erst auf, wenn eine Umstellung unbemerkt bleibt.
          //
          // Der GESPEICHERTE Wert bleibt dabei unberührt: Wer den Abend-Blick
          // wieder einschaltet, findet seine Einstellung vor, statt sie neu
          // setzen zu müssen.
          SwitchListTile(
            value: prefs.eveningEnabled && prefs.changesEnabled,
            onChanged: _busy || !prefs.eveningEnabled
                ? null
                : (value) => _save(prefs.copyWith(changesEnabled: value)),
            title: const Text('Änderungen bis zur Abfahrt'),
            subtitle: Text(
              prefs.eveningEnabled
                  ? 'Wenn jemand den Plan für den Tag noch umstellt — oder '
                        'eine Anmerkung schreibt.'
                  // Anmerkungen (#127) reisen als Änderungs-Meldung mit und
                  // hängen damit an derselben Bedingung. Das gehört
                  // ausgesprochen, sonst ist es eine stille Lücke.
                  : 'Braucht den Abend-Blick — ohne ihn wäre eine Änderung '
                        'die erste Nachricht des Tages, ohne Bezug. Auch '
                        'Anmerkungen kommen dann nicht an.',
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
          // Erinnerung zur Abfahrt (#164) — bewusst als Opt-in und bewusst
          // OHNE Bindung an den Abend-Blick: Sie hängt nicht an `push_log`
          // wie die Änderungs-Meldung, sondern an der Uhr der Gruppe. Wer nur
          // den Schubs kurz vorher will, bekommt ihn auch allein.
          //
          // Ohne Gruppenzeiten (#139) liefe der Schalter dagegen wirklich
          // leer — dann sagt der Untertitel, wo sie herkommen, statt ihn
          // stumm zu sperren.
          SwitchListTile(
            value: prefs.remindersEnabled,
            onChanged: _busy || !hasLegTimes
                ? null
                : (value) => _save(prefs.copyWith(remindersEnabled: value)),
            title: const Text('Erinnerung zur Abfahrt'),
            subtitle: Text(
              hasLegTimes
                  ? 'Kurz bevor es losgeht — hin und zurück.'
                  : 'Braucht die Abfahrtszeiten der Gruppe. Die stehen unter '
                        'Parameter → „Fahrt & Treffpunkt".',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          // Beide Vorläufe in EINER Zeile (#168): Der Wunsch kam ausdrücklich
          // mit „kompakt, nicht unnötig neuer Space". Zwei getrennte Zeilen
          // wären die naheliegende Umsetzung gewesen und hätten den Screen um
          // eine Zeile wachsen lassen, ohne mehr zu sagen.
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Vorlauf'),
            subtitle: const Text('Hinfahrt · Rückfahrt'),
            trailing: Text(
              '${prefs.reminderLeadMinutes} · '
              '${prefs.reminderLeadReturnMinutes} min',
            ),
            enabled: !_busy && prefs.remindersEnabled && hasLegTimes,
            onTap: () => unawaited(_pickLead(prefs)),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),
          // Sofort-Meldungen (#163). Bewusst NICHT an den Abend-Blick
          // gekoppelt: Sie feuern außerhalb jedes Fensters — ihn zu koppeln
          // hieße, sie genau dann abzuschalten, wenn sie gebraucht werden.
          //
          // Die Grenze der Selbst-Unterdrückung steht im Untertitel, statt
          // sie zu verschweigen: Sie hängt an „Ich bin", und das ist keine
          // Anmeldung (#121). Ohne gewählte Person meldet sich auch die
          // eigene Änderung.
          SwitchListTile(
            value: prefs.instantEnabled,
            onChanged: _busy
                ? null
                : (value) => _save(prefs.copyWith(instantEnabled: value)),
            title: const Text('Sofort-Meldungen'),
            subtitle: const Text(
              'Wenn dich jemand anderes ein- oder austrägt, und wenn eine '
              'eingetragene Fahrt geändert oder gelöscht wird — auch eine '
              'ältere. Eigene Änderungen bleiben still, sofern im Menü unter '
              '„Ich bin" jemand gewählt ist.',
            ),
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

/// Eine Blockade, benannt und mit dem Weg dorthin (#180).
///
/// [onPressed] darf fehlen — bei völliger Stille gibt es keinen Schirm, der
/// hilft, und ein Knopf ohne Wirkung wäre schlimmer als keiner.
class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      // Warnfarbe statt Fehlerfarbe: Es ist nichts kaputt, es ist etwas
      // ausgeschaltet — und der Weg zurück steht daneben.
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodySmall),
            if (action != null && onPressed != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: () => unawaited(onPressed!()),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(action!),
                ),
              ),
            ],
          ],
        ),
      ),
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
