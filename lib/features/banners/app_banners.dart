/// app_banners.dart – Hinweisleisten über der Übersicht:
/// neue App-Version und Feedback (Wunsch/Fehler).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Version ${info.latestVersion} verfügbar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              updateIsDownload
                  ? 'Lade die neue Version herunter und installiere sie – '
                        'eure Daten bleiben erhalten.'
                  : 'Lade die Seite neu, dann läuft die neue Version.',
            ),
            if (info.releaseNotes?.trim().isNotEmpty ?? false) ...[
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Später'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            if (updateIsDownload) {
              launchUrl(
                Uri.parse(info.apkUrl ?? info.releaseUrl),
                mode: LaunchMode.externalApplication,
              );
            } else {
              reloadApp();
            }
          },
          icon: Icon(
            updateIsDownload ? Icons.download : Icons.refresh,
            size: 18,
          ),
          label: Text(updateIsDownload ? 'Herunterladen' : 'Neu laden'),
        ),
      ],
    ),
  );
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
      await ref
          .read(feedbackRepositoryProvider)
          .submit(
            _type,
            message,
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
