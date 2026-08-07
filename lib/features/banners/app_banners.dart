/// app_banners.dart – Hinweisleisten über der Übersicht, in dieser
/// Reihenfolge: fehlende Personen-Auswahl, die nächste Fahrt, eine neue
/// App-Version und Feedback (Wunsch/Fehler).
///
/// Die Reihenfolge ist keine Laune: Oben stehen die dauerhaften (offene
/// Einrichtung, dann Information), unten die, die kommen und gehen. Andersherum
/// spränge der Inhalt, sobald ein Update-Hinweis auftaucht oder weggetippt wird.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/log.dart';
import '../../core/push_digest.dart';
import '../../core/push_messaging.dart';
import '../../core/release_notes.dart';
import '../../core/reload_app.dart';
import '../../core/router.dart';
import '../../core/tokens.dart';
import '../../core/update_check.dart';
import '../../data/feedback_repository.dart';
import '../../data/providers.dart';
import '../../models/group_defaults.dart';
import '../identity/identity_dialog.dart';

/// Banner nur für die laufende Sitzung ausblenden (bewusst ohne Persistenz).
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);
final feedbackBannerDismissedProvider = StateProvider<bool>((ref) => false);

class AppBanners extends ConsumerWidget {
  const AppBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateInfoProvider).value;
    final updateDismissed = ref.watch(updateBannerDismissedProvider);
    final feedbackDismissed = ref.watch(feedbackBannerDismissedProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ganz oben, weil es eine offene Einrichtung meldet und keine
        // Information: Solange niemand gewählt ist, funktioniert ein Teil der
        // App nicht. Verschwindet für immer, sobald jemand gewählt ist.
        const _IdentityBanner(),
        // Danach das dauerhafte Informations-Banner. Läge es unten, spränge
        // es, sobald ein Update-Hinweis kommt und geht.
        const _NextRideBanner(),
        if (update != null && !updateDismissed)
          _Banner(
            icon: Icons.system_update,
            text: 'Version ${update.latestVersion} ist verfügbar',
            // „Sunset Coral" — der einzige Ton außerhalb der Teal-Familie,
            // und das Design-Set weist ihn ausdrücklich den Release-News zu.
            // Der Hinweis kommt und geht, Herausfallen ist hier der Zweck.
            tone: AppBannerTones.update(Theme.of(context).brightness),
            onTap: () => showUpdateDialog(context, update),
            onDismiss: () =>
                ref.read(updateBannerDismissedProvider.notifier).state = true,
          ),
        if (!feedbackDismissed)
          _Banner(
            icon: Icons.lightbulb_outline,
            text: 'Wunsch oder Fehler melden',
            tone: AppBannerTones.quiet(Theme.of(context).brightness),
            onTap: () => showFeedbackDialog(context),
            onDismiss: () =>
                ref.read(feedbackBannerDismissedProvider.notifier).state = true,
          ),
      ],
    );
  }
}

/// „Niemand ausgewählt" — die Erinnerung an die übersprungene Startabfrage
/// (#121).
///
/// Sie steht **nur hier**, nicht zusätzlich als wiederkehrender Dialog: Zwei
/// Mahner sind einer zu viel, und was bei jedem Start aufpoppt, klickt man
/// blind weg. Nicht ausblendbar, dafür ist ein Tipp der Weg zur Lösung.
class _IdentityBanner extends ConsumerWidget {
  const _IdentityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Abgeschaltet heißt abgeschaltet: Sonst mahnte ein Feature, das es in
    // diesem Lauf gar nicht gibt. Deckt den Demo-Modus mit ab — der Provider
    // hängt selbst an `SupabaseConfig.isConfigured`.
    if (!ref.watch(identityEnabledProvider)) return const SizedBox.shrink();

    final identity = ref.watch(deviceIdentityProvider).value;
    // Vor der ersten Frage kein Banner — dort kommt der Dialog. Und solange
    // geladen wird, sagt ein Streifen, der nichts weiß, besser nichts.
    if (identity == null || !identity.asked) return const SizedBox.shrink();
    if (ref.watch(myPersonProvider) != null) return const SizedBox.shrink();

    return _Banner(
      icon: Icons.badge_outlined,
      text: 'Niemand ausgewählt',
      subtitle:
          'Tippen, um festzulegen, wer du bist — sonst gibt es hier '
          'keine Benachrichtigungen.',
      tone: AppBannerTones.quiet(Theme.of(context).brightness),
      onTap: () => unawaited(showIdentityDialog(context)),
    );
  }
}

/// „Wer fährt als Nächstes, wer ist dabei" — der Inhalt der Abend-Meldung,
/// aber ohne Handy (#122).
///
/// Bewusst **nicht** ausblendbar: Gewünscht war „alles auf einen Blick", und
/// das erfüllt ein weggetipptes Banner nicht.
///
/// Der Wortlaut kommt aus `push_digest.dart` und nicht von hier — was das
/// Handy meldet und was die App zeigt, darf nicht auseinanderlaufen.
class _NextRideBanner extends ConsumerWidget {
  const _NextRideBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(nextRideProvider).value;
    final persons = ref.watch(personsProvider).value;

    // Beim Laden und im Fehlerfall bleibt der Streifen weg: Ein ergänzender
    // Hinweis, der nichts weiß, sagt besser nichts, statt etwas Halbes zu
    // behaupten. Die Übersicht meldet Ladefehler ohnehin an ihrer Stelle.
    if (day == null || persons == null) return const SizedBox.shrink();

    final byId = {for (final person in persons) person.id: person};
    final tone = AppBannerTones.nextRide(Theme.of(context).brightness);
    // Anmerkungen des Tages (#127) — aus der Wochenladung, die der Planer
    // ohnehin braucht; das Banner kostet dadurch keine eigene Anfrage.
    final notes = ref.watch(weekNotesProvider).value?[day.date] ?? const [];
    // Feste Vorgaben (#139). Fehlen sie noch (Ladephase, Fehler), zeigt das
    // Banner den Tag ohne Zeiten statt gar nicht — anders als bei Plan und
    // Personen ist hier nichts halb, sondern nur weniger.
    //
    // Die Abweichung des Tages (#183) schlägt sie feldweise. **Dieselbe
    // Quelle wie die Meldung**: Stünde hier die Vorgabe, zeigte das Banner
    // 07:30, während das Handy um 06:45 weckt — und niemand wüsste, welche
    // der beiden Zeiten gilt.
    //
    // Bei EINEM Auto gilt dasselbe eine Ebene tiefer: Dessen Abweichung
    // betrifft alle, die an dem Tag fahren, und der Korb rechnet sie in die
    // Erinnerung ein — das Banner muss dieselbe Zeit nennen.
    //
    // Bei MEHREREN Autos bleibt hier die Tageszeit stehen — sie ist das,
    // was allen gemeinsam ist. Die abweichenden Zeiten stehen seit #189
    // nicht mehr nur im Planer, sondern an ihrem Auto in der Aufzählung
    // („Auto 2: Dora mit Emil (hin 06:45)"). Zwei Abfahrtszeiten in EINER
    // Zeile wären weiter falsch; zwei Zeilen mit je einer sind es nicht.
    final carDeviations =
        ref.watch(weekCarDefaultsProvider).value?[day.date] ??
        const <String, GroupDefaults>{};
    final defaults = effectiveDefaults(
      effectiveDefaults(
        ref.watch(groupDefaultsProvider).value ?? const GroupDefaults(),
        ref.watch(weekPlanDefaultsProvider).value?[day.date],
      ),
      day.cars.length == 1 ? carDeviations[day.cars.single.driverId] : null,
    );
    final iso =
        '${day.date.year.toString().padLeft(4, '0')}-'
        '${day.date.month.toString().padLeft(2, '0')}-'
        '${day.date.day.toString().padLeft(2, '0')}';

    return _Banner(
      icon: Icons.directions_car,
      text: dayLabel(day.date, ref.watch(nowProvider)()),
      subtitle: composeGroupBody(
        day,
        byId,
        notes: notes,
        defaults: defaults,
        // Nur ab zwei Autos ausgewertet — bei einem steckt die Abweichung
        // schon in `defaults` und stünde sonst zweimal da.
        carDefaults: carDeviations,
      ),
      // „Deep Teal Flow" aus dem Design-Set — dort mit genau dieser
      // Überschrift gezeichnet. Der Verlauf läuft hell nach dunkel, weil
      // rechts der Zähler sitzt; die Begründung steht am Token.
      tone: tone,
      // Dieselbe Adresse, die auch eine angetippte Benachrichtigung ansteuert.
      onTap: () => ref.read(routerProvider).go(pushTapRoute),
      // Eigener Knopf statt eines zweiten Tap-Ziels auf derselben Fläche:
      // Der Streifen führt weiter in die Woche, die Sprechblase in die
      // Anmerkungen. Der Tooltip ist bewusst NICHT „Ausblenden" — dieses
      // Banner lässt sich nicht ausblenden, und ein Test zählt genau das.
      action: IconButton(
        tooltip: 'Anmerkungen',
        onPressed: () => ref.read(routerProvider).push('/notes/$iso'),
        visualDensity: VisualDensity.compact,
        // **Die Sprechblase trägt den Akzent mit, sobald es Anmerkungen
        // gibt** (#189). Bis v0.66.2 blieb sie weiß und der Zähler allein
        // magenta — nach der Regel „nie zwei Akzente im selben Banner". Es
        // sind aber keine zwei: Chip und Blase sagen dieselbe Sache, und
        // gemeldet wurde genau das, „bei Kommentaren auch Chatsymbol in
        // gleicher Farbe".
        //
        // **Leer bleibt sie weiß.** Ein magentafarbenes Symbol ohne
        // Anmerkung wäre ein Akzent, der auf nichts zeigt.
        //
        // Der Ton ist derselbe wie der des Chips und sitzt am **dunklen**
        // Ende des Verlaufs — dort trägt er 4,06:1. Auf dem hellen Teal
        // wären es 1,61:1; deshalb steht der Knopf rechts und deshalb läuft
        // der Verlauf gespiegelt. `banner_contrast_test.dart` misst es.
        icon: Badge(
          isLabelVisible: notes.isNotEmpty,
          backgroundColor: AppAccents.notesChip,
          textColor: AppAccents.notesChipInk,
          label: Text('${notes.length}'),
          child: Icon(
            notes.isEmpty
                ? Icons.chat_bubble_outline
                : Icons.chat_bubble_rounded,
            size: 18,
            color: notes.isEmpty ? tone.foreground : AppAccents.notesChip,
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.tone,
    required this.onTap,
    this.subtitle,
    this.onDismiss,
    this.action,
  });

  final IconData icon;
  final String text;

  /// Zweite Zeile; ohne sie bleibt das Banner einzeilig wie bisher.
  final String? subtitle;

  /// Fläche und Vordergrund als Paar — siehe `core/tokens.dart`.
  final BannerTone tone;
  final VoidCallback onTap;

  /// Ohne Rückruf gibt es keinen „Ausblenden"-Knopf — das Banner bleibt.
  final VoidCallback? onDismiss;

  /// Eigener Knopf am rechten Rand, VOR dem Ausblenden-Knopf.
  ///
  /// Ein zweiter Slot statt [onDismiss] zweckzuentfremden: Dessen Zusicherung
  /// („ohne Rückruf kein Ausblenden") wäre sonst eine Zufälligkeit, und ein
  /// Knopf mit dem Tooltip „Ausblenden", der etwas anderes tut, ist die Art
  /// Falle, die erst auf dem Gerät auffällt.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        0,
      ),
      // Die Fläche liegt in `Ink` statt in `Material.color`: Nur so trägt
      // sie einen Verlauf, und der Ripple des InkWell bleibt erhalten. Der
      // Rahmen ist keine Zierde — die flächigen Töne heben sich nur mit
      // rund 1,2:1 vom Untergrund ab und wären sonst kaum ein Streifen.
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: tone.gradient == null ? tone.surface : null,
            gradient: tone.gradient,
            border: tone.gradient == null
                ? Border.all(color: AppBannerTones.hairlineOf(tone))
                : null,
            borderRadius: BorderRadius.circular(AppRadius.m),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.m),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: tone.foreground),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: subtitle == null
                        ? Text(text, style: TextStyle(color: tone.foreground))
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: TextStyle(
                                  color: tone.foreground,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                subtitle!,
                                style: TextStyle(color: tone.foreground),
                              ),
                            ],
                          ),
                  ),
                  ?action,
                  if (onDismiss != null)
                    IconButton(
                      tooltip: 'Ausblenden',
                      icon: Icon(Icons.close, size: 18, color: tone.foreground),
                      onPressed: onDismiss,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) =>
    showDialog<void>(
      context: context,
      builder: (_) => _UpdateDialog(info: info),
    );

/// Das Update im Browser öffnen — bevorzugt direkt die APK.
///
/// Bewusst frei von jedem `BuildContext`: Das ist der einzige Update-Weg, der
/// **keinen Navigator und kein Overlay** braucht, und damit die Rettungsleine
/// auf dem Sperr-Schirm. Wer hier wieder einen Dialog, eine SnackBar oder
/// einen Router-Aufruf einbaut, hängt sie an genau das, was im gesperrten
/// Zustand fehlen kann.
///
/// Liefert `false`, wenn kein Browser reagiert hat — der Aufrufer muss das
/// sichtbar machen, sonst wirkt der Knopf tot.
Future<bool> openUpdateInBrowser(UpdateInfo info) => launchUrl(
  Uri.parse(info.apkUrl ?? info.releaseUrl),
  mode: LaunchMode.externalApplication,
);

/// Ablauf des In-App-Updates. Sichtbar getrennt, weil jede Phase etwas
/// anderes von der Nutzerin verlangt: warten, bestätigen, ausweichen.
enum _UpdatePhase { idle, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  double _progress = 0;
  StreamSubscription<OtaEvent>? _subscription;

  @override
  void dispose() {
    // Ohne das folgt ein setState nach dem Dispose, sobald der Download
    // weiterläuft, während der Dialog schon zu ist.
    _subscription?.cancel();
    super.dispose();
  }

  /// Nur auf Android und nur mit APK im Release gibt es einen echten
  /// In-App-Weg; im Web genügt ein Neuladen.
  bool get _canInstallInApp => updateIsDownload && widget.info.apkUrl != null;

  void _start() {
    setState(() => _phase = _UpdatePhase.downloading);
    // Dreifach abgesichert: synchroner Wurf, Fehler-Callback, unbekannter
    // Status. Ein hängengebliebener Fortschrittsbalken wäre das Schlimmste.
    try {
      _subscription = OtaUpdate()
          .execute(
            widget.info.apkUrl!,
            destinationFilename: 'mitfahrbar-update.apk',
          )
          .listen(
            (event) {
              if (!mounted) return;
              switch (event.status) {
                case OtaStatus.DOWNLOADING:
                  setState(() {
                    _phase = _UpdatePhase.downloading;
                    // event.value ist ein Prozentwert 0–100.
                    _progress = (double.tryParse(event.value ?? '') ?? 0) / 100;
                  });
                case OtaStatus.INSTALLING:
                  setState(() => _phase = _UpdatePhase.installing);
                default:
                  setState(() => _phase = _UpdatePhase.error);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              log.e(
                'Update-Download fehlgeschlagen',
                error: error,
                stackTrace: stackTrace,
              );
              if (mounted) setState(() => _phase = _UpdatePhase.error);
            },
          );
    } catch (error, stackTrace) {
      log.e(
        'Update-Download fehlgeschlagen',
        error: error,
        stackTrace: stackTrace,
      );
      setState(() => _phase = _UpdatePhase.error);
    }
  }

  Future<void> _openInBrowser() async {
    final launched = await openUpdateInBrowser(widget.info);
    // launchUrl scheitert still, wenn kein Browser sichtbar ist – dann
    // wenigstens sagen, was los ist, statt so zu tun als sei nichts.
    if (!launched && mounted) {
      setState(() => _phase = _UpdatePhase.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('Version ${info.latestVersion} verfügbar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            switch (_phase) {
              _UpdatePhase.idle => Text(
                _canInstallInApp
                    ? 'Das Update lädt direkt in der App und öffnet dann den '
                          'Android-Installer – eure Daten bleiben erhalten. '
                          'Beim ersten Mal fragt Android einmalig um Erlaubnis.'
                    : updateIsDownload
                    ? 'Lade die neue Version herunter und installiere sie – '
                          'eure Daten bleiben erhalten.'
                    : 'Lade die Seite neu, dann läuft die neue Version.',
              ),
              _UpdatePhase.downloading => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lädt … ${(_progress * 100).round()} %'),
                  const SizedBox(height: AppSpacing.s),
                  LinearProgressIndicator(
                    // Bei 0 % unbestimmt, sonst stünde der Balken scheinbar.
                    value: _progress > 0 ? _progress : null,
                  ),
                ],
              ),
              _UpdatePhase.installing => const Text(
                'Download fertig – Android fragt jetzt, ob MitFahrBar '
                'aktualisiert werden soll. Einfach bestätigen.',
              ),
              _UpdatePhase.error => const Text(
                'Der Direkt-Download hat nicht geklappt. Du kannst das Update '
                'stattdessen über den Browser laden – nach dem Herunterladen '
                'in der Benachrichtigung auf die Datei tippen.',
              ),
            },
            // Geglättet statt roh: Der Body kommt als Markdown (heute der
            // CHANGELOG-Auszug, bei alten Releases auto-generierte
            // PR-Titel) — ungefiltert stünden Rauten und Sternchen im Text.
            if (_phase == _UpdatePhase.idle)
              switch (plainReleaseNotes(info.releaseNotes ?? '')) {
                '' => const SizedBox.shrink(),
                final notes => Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Was ist neu:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(notes, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              },
          ],
        ),
      ),
      actions: switch (_phase) {
        _UpdatePhase.idle => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (_canInstallInApp) {
                _start();
              } else if (updateIsDownload) {
                Navigator.pop(context);
                _openInBrowser();
              } else {
                Navigator.pop(context);
                reloadApp();
              }
            },
            icon: Icon(
              updateIsDownload ? Icons.download : Icons.refresh,
              size: 18,
            ),
            label: Text(updateIsDownload ? 'Jetzt aktualisieren' : 'Neu laden'),
          ),
        ],
        _UpdatePhase.error => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
          FilledButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('Im Browser laden'),
          ),
        ],
        _ => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      },
    );
  }
}

Future<void> showFeedbackDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _FeedbackDialog());

class _FeedbackDialog extends ConsumerStatefulWidget {
  const _FeedbackDialog();

  @override
  ConsumerState<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<_FeedbackDialog> {
  FeedbackType _type = FeedbackType.feature;
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Bewusst standardmäßig aus: Die Rückmeldung wird ein öffentliches Issue,
  /// also darf nichts ungefragt mitgehen.
  bool _attachLog = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.length < 3) {
      setState(() => _error = 'Bitte schreib ein paar Worte mehr.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final body = _attachLog && logRing.isNotEmpty
          ? '$message\n\n--- Protokoll ---\n${logRing.tail()}'
          : message;
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            _type,
            body,
            appVersion: ref.read(currentVersionProvider).value,
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
          );
      ref.read(feedbackBannerDismissedProvider.notifier).state = true;
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Danke! Deine Rückmeldung ist angekommen.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Senden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBug = _type == FeedbackType.bug;
    return AlertDialog(
      title: const Text('Rückmeldung'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<FeedbackType>(
              segments: const [
                ButtonSegment(
                  value: FeedbackType.feature,
                  label: Text('Wunsch'),
                ),
                ButtonSegment(value: FeedbackType.bug, label: Text('Fehler')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: isBug ? 'Was ist passiert?' : 'Dein Wunsch',
                hintText: isBug
                    ? 'z. B. „Nach dem Speichern fehlt die Fahrt in der Historie"'
                    : 'z. B. „Monatsübersicht wäre praktisch"',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            // Nur anbieten, wenn es wirklich etwas anzuhängen gibt — eine
            // leere Checkbox erklärt sich nicht und weckt falsche Erwartungen.
            if (logRing.isNotEmpty) ...[
              CheckboxListTile(
                value: _attachLog,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _attachLog = value ?? false),
                title: const Text('Fehlerprotokoll anhängen'),
                subtitle: const Text(
                  'Technische Meldungen der App. Geht mit in den '
                  'öffentlichen Eintrag.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // Vorschau statt Vertrauensvorschuss: Wer etwas Öffentliches
              // mitschickt, soll vorher gesehen haben, was drinsteht.
              if (_attachLog)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(AppSpacing.s),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.s),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      logRing.tail(),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.s),
            Text(
              'Hinweis: Der Text landet öffentlich im GitHub-Projekt der App – '
              'bitte keine persönlichen Daten hineinschreiben.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Senden'),
        ),
      ],
    );
  }
}
