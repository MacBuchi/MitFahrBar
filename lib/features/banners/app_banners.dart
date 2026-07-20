/// app_banners.dart – Hinweisleisten über der Übersicht:
/// neue App-Version und Feedback (Wunsch/Fehler).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/log.dart';
import '../../core/reload_app.dart';
import '../../core/tokens.dart';
import '../../core/update_check.dart';
import '../../data/feedback_repository.dart';
import '../../data/providers.dart';

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
        if (update != null && !updateDismissed)
          _Banner(
            icon: Icons.system_update,
            text: 'Version ${update.latestVersion} ist verfügbar',
            background: Theme.of(context).colorScheme.primaryContainer,
            foreground: Theme.of(context).colorScheme.onPrimaryContainer,
            onTap: () => showUpdateDialog(context, update),
            onDismiss: () =>
                ref.read(updateBannerDismissedProvider.notifier).state = true,
          ),
        if (!feedbackDismissed)
          _Banner(
            icon: Icons.lightbulb_outline,
            text: 'Wunsch oder Fehler melden',
            background: Theme.of(context).colorScheme.secondaryContainer,
            foreground: Theme.of(context).colorScheme.onSecondaryContainer,
            onTap: () => showFeedbackDialog(context),
            onDismiss: () =>
                ref.read(feedbackBannerDismissedProvider.notifier).state = true,
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
    required this.onTap,
    required this.onDismiss,
  });

  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        0,
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.m),
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
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(text, style: TextStyle(color: foreground)),
                ),
                IconButton(
                  tooltip: 'Ausblenden',
                  icon: Icon(Icons.close, size: 18, color: foreground),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                ),
              ],
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
            destinationFilename: 'ridebuddy-update.apk',
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
    final target = widget.info.apkUrl ?? widget.info.releaseUrl;
    final launched = await launchUrl(
      Uri.parse(target),
      mode: LaunchMode.externalApplication,
    );
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
                'Download fertig – Android fragt jetzt, ob RideBuddy '
                'aktualisiert werden soll. Einfach bestätigen.',
              ),
              _UpdatePhase.error => const Text(
                'Der Direkt-Download hat nicht geklappt. Du kannst das Update '
                'stattdessen über den Browser laden – nach dem Herunterladen '
                'in der Benachrichtigung auf die Datei tippen.',
              ),
            },
            if (_phase == _UpdatePhase.idle &&
                (info.releaseNotes?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: AppSpacing.m),
              Text(
                'Was ist neu:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                info.releaseNotes!.trim(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
