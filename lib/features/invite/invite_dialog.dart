/// invite_dialog.dart – Jemanden in die Gruppe einladen.
///
/// Eine Gruppe = ein Login. „Einladen" heißt hier deshalb zwangsläufig: den
/// gemeinsamen Zugang weitergeben. Die App kennt den Handle, das Passwort
/// aber nicht — nach dem Login liegt bei Supabase nur ein Sitzungs-Token.
/// Deshalb wird es hier abgefragt.
///
/// Drei Eigenschaften, die zusammen die bewusste Entscheidung tragen, das
/// Passwort mitzuschicken:
///
/// * **Freiwillig.** Bleibt das Feld leer, geht die Einladung ohne Passwort
///   raus und sagt das auch. Die sichere Variante ist einen Tastendruck weit.
/// * **Sichtbar.** Die fertige Nachricht steht im Dialog, bevor sie weggeht —
///   niemand teilt etwas, das er nicht gelesen hat.
/// * **Flüchtig.** Das Passwort wird nicht gespeichert und **nie geloggt**:
///   `logRing` kann per Rückmeldung in einem öffentlichen Issue landen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/invite_text.dart';
import '../../core/share_outcome.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/group.dart';

Future<void> showInviteDialog(BuildContext context, Group group) =>
    showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(group: group),
    );

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.group});

  final Group group;

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Die Vorschau muss beim Tippen mitwachsen, sonst teilt man am Ende
    // etwas anderes, als man gelesen hat.
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String get _text => buildInviteText(
    groupName: widget.group.name,
    handle: widget.group.handle,
    password: _password.text,
  );

  Future<void> _send() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final outcome = await ref.read(textSharerProvider)(
        _text,
        subject: 'MitFahrBar',
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome == ShareOutcome.copied
                ? 'Einladung in die Zwischenablage kopiert.'
                : 'Einladung geteilt.',
          ),
        ),
      );
    } catch (_) {
      // Bewusst ohne den Fehlertext: Er könnte die Nachricht und damit das
      // Passwort enthalten, und Fehlermeldungen landen schnell im Log.
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Teilen fehlgeschlagen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final withPassword = _password.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('Jemanden einladen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alle in der Gruppe teilen sich einen Zugang. Wer die Einladung '
              'bekommt, kann alles sehen und ändern.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _password,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Passwort (optional)',
                helperText: 'Leer lassen und selbst weitergeben ist sicherer.',
                helperMaxLines: 2,
              ),
            ),
            if (withPassword) ...[
              const SizedBox(height: AppSpacing.s),
              _PasswordWarning(),
            ],
            const SizedBox(height: AppSpacing.m),
            Text('Das geht raus:', style: theme.textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.s),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.s),
              ),
              child: SelectableText(_text, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: const Text('Teilen'),
        ),
      ],
    );
  }
}

/// Steht nur da, wenn wirklich ein Passwort im Text landet — eine Warnung,
/// die immer sichtbar ist, liest nach kurzer Zeit niemand mehr.
class _PasswordWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_open_outlined, size: 18, color: scheme.error),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            'Das Passwort steht dann dauerhaft im Chat-Verlauf und in dessen '
            'Sicherungen.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ),
      ],
    );
  }
}
