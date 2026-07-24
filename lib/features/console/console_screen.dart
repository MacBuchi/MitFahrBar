/// console_screen.dart – Die Verwalter-Konsole selbst (Issue #55).
///
/// Bewusst karg: verknüpfen, Gruppenpasswort neu setzen, eigenes
/// Admin-Passwort ändern, Gruppe löschen. Mehr kann und soll das
/// Verwalter-Konto nicht — Gruppendaten sieht es nie (anderer uid,
/// RLS blockt). Kommt die Sitzung über einen Passwort-Reset-Link herein,
/// öffnet sich der Ändern-Dialog von selbst.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/widgets/password_field.dart';
import '../../data/admin_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/providers.dart';

class ConsoleScreen extends ConsumerStatefulWidget {
  const ConsoleScreen({super.key});

  @override
  ConsumerState<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends ConsumerState<ConsoleScreen> {
  @override
  Widget build(BuildContext context) {
    // Reset-Link aus der Mail: Supabase meldet die Sitzung als
    // „passwordRecovery" — dann direkt den Ändern-Dialog anbieten, statt
    // die Nutzerin raten zu lassen, wo es weitergeht.
    ref.listen(authStateProvider, (previous, next) {
      final event = next.value;
      if ('$event'.contains('passwordRecovery')) {
        unawaited(_changeAdminPassword(context));
      }
    });

    final group = ref.watch(adminGroupProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verwalter-Konsole'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: switch (group) {
        AsyncData(value: final g) => _Body(group: g),
        AsyncError() => const Center(
          child: Text('Fehler beim Laden der Verknüpfung.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Future<void> _changeAdminPassword(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const _AdminPasswordDialog(),
  );
}

class _Body extends ConsumerWidget {
  const _Body({required this.group});

  final AdminGroup? group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (group == null) ...[
                  const _ClaimCard(),
                  const _ChangeEmailTile(),
                ] else
                  _ManageCards(group: group!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Noch keine Gruppe verknüpft: Beweis ist das Gruppen-Login. Nur möglich,
/// solange die Gruppe keinen Verwalter hat — danach rastet es ein.
class _ClaimCard extends ConsumerStatefulWidget {
  const _ClaimCard();

  @override
  ConsumerState<_ClaimCard> createState() => _ClaimCardState();
}

class _ClaimCardState extends ConsumerState<_ClaimCard> {
  final _handle = TextEditingController();
  final _groupPassword = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    _groupPassword.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    final handle = _handle.text.trim();
    // Leere Eingaben gar nicht erst zum Server schicken — die Sichtprüfung
    // zeigte sonst eine Verknüpfung mit leerem Namen im (Demo-)Fake.
    if (handle.isEmpty || _groupPassword.text.isEmpty) {
      setState(
        () => _error = 'Bitte Gruppenname und Gruppenpasswort eintragen.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .claimGroup(handle, _groupPassword.text);
      ref.invalidate(adminGroupProvider);
    } on WrongGroupCredentials {
      setState(() => _error = 'Gruppenname oder Gruppenpasswort falsch.');
    } on GroupAlreadyClaimed {
      setState(
        () => _error =
            'Diese Gruppe hat schon ein Verwalter-Konto — oder dieses '
            'Konto verwaltet bereits eine Gruppe.',
      );
    } catch (_) {
      setState(() => _error = 'Verknüpfen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gruppe verknüpfen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s),
            const Text(
              'Melde dieses Konto als Verwalter deiner Gruppe an. Als '
              'Nachweis dienen einmalig Gruppenname und Gruppenpasswort. '
              'Je Gruppe gibt es genau ein Verwalter-Konto — wer zuerst '
              'verknüpft, verwaltet.',
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _handle,
              decoration: const InputDecoration(
                labelText: 'Gruppenname',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.m),
            PasswordField(
              controller: _groupPassword,
              labelText: 'Gruppenpasswort',
              onSubmitted: (_) => _busy ? null : _claim(),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            FilledButton(
              onPressed: _busy ? null : _claim,
              child: const Text('Verknüpfen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageCards extends ConsumerWidget {
  const _ManageCards({required this.group});

  final AdminGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(group.name),
            subtitle: Text('Verwaltet: ${group.handle}'),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gruppenpasswort neu setzen',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.s),
                const Text(
                  'Setzt das geteilte Passwort der Gruppe neu — z. B. wenn '
                  'es verloren ging. Danach musst du es allen Mitgliedern '
                  'neu geben.',
                ),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => const _GroupPasswordDialog(),
                    ),
                    child: const Text('Neu setzen'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Eigenes Admin-Passwort ändern'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => const _AdminPasswordDialog(),
            ),
          ),
        ),
        const _ChangeEmailTile(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verknüpfung lösen', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s),
                const Text(
                  'Gibt die Gruppe für ein anderes Verwalter-Konto frei — '
                  'die Übergabe. Fahrten und Einstellungen bleiben '
                  'unberührt, dieses Konto bleibt bestehen. Wer übernimmt, '
                  'verknüpft sich danach mit dem Gruppen-Login.',
                ),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => const _ReleaseGroupDialog(),
                    ),
                    child: const Text('Verknüpfung lösen …'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gruppe löschen',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  'Löscht Gruppe, alle Fahrten und dieses Verwalter-Konto '
                  'endgültig — das lässt sich nicht rückgängig machen. '
                  'Die einzige Kopie danach ist ein vorher gemachter '
                  'CSV-Export aus der App.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                const SizedBox(height: AppSpacing.s),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) =>
                          _DeleteGroupDialog(handle: group.handle),
                    ),
                    child: const Text('Gruppe löschen …'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Neues geteiltes Gruppenpasswort (die Rettungsleine).
class _GroupPasswordDialog extends ConsumerStatefulWidget {
  const _GroupPasswordDialog();

  @override
  ConsumerState<_GroupPasswordDialog> createState() =>
      _GroupPasswordDialogState();
}

class _GroupPasswordDialogState extends ConsumerState<_GroupPasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Mindestens 8 Zeichen.');
      return;
    }
    if (_password.text != _repeat.text) {
      setState(() => _error = 'Die Eingaben stimmen nicht überein.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .resetGroupPassword(_password.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gruppenpasswort neu gesetzt. Bitte allen Mitgliedern geben.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Neu setzen fehlgeschlagen.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gruppenpasswort neu setzen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PasswordField(
            controller: _password,
            labelText: 'Neues Gruppenpasswort',
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.s),
          PasswordField(
            controller: _repeat,
            labelText: 'Wiederholen',
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Neu setzen'),
        ),
      ],
    );
  }
}

/// Eigenes Admin-Passwort ändern — auch das Ziel des Reset-Links.
class _AdminPasswordDialog extends ConsumerStatefulWidget {
  const _AdminPasswordDialog();

  @override
  ConsumerState<_AdminPasswordDialog> createState() =>
      _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends ConsumerState<_AdminPasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Mindestens 8 Zeichen.');
      return;
    }
    if (_password.text != _repeat.text) {
      setState(() => _error = 'Die Eingaben stimmen nicht überein.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(_password.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin-Passwort geändert.')));
    } catch (_) {
      if (mounted) setState(() => _error = 'Ändern fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Admin-Passwort ändern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PasswordField(
            controller: _password,
            labelText: 'Neues Passwort',
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.s),
          PasswordField(
            controller: _repeat,
            labelText: 'Wiederholen',
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Ändern'),
        ),
      ],
    );
  }
}

/// Das Löschen: Sudo-Muster (eigenes Admin-Passwort erneut) plus getippter
/// Gruppenname. Beides prüft der **Server**, nicht dieser Dialog.
class _DeleteGroupDialog extends ConsumerStatefulWidget {
  const _DeleteGroupDialog({required this.handle});

  final String handle;

  @override
  ConsumerState<_DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends ConsumerState<_DeleteGroupDialog> {
  final _adminPassword = TextEditingController();
  final _handleConfirmation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _adminPassword.dispose();
    _handleConfirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .deleteGroup(
            adminPassword: _adminPassword.text,
            handleConfirmation: _handleConfirmation.text.trim(),
          );
      // Konto und Gruppe existieren nicht mehr: Dialog schließen, dann die
      // tote Sitzung beenden — der Router führt zurück zum Login. Die
      // Reihenfolge zählt: Ein Routenwechsel schließt schwebende Dialoge
      // nicht von allein.
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(authRepositoryProvider).signOut();
    } on WrongAdminPassword {
      setState(() => _error = 'Das Admin-Passwort stimmt nicht.');
    } on HandleMismatch {
      setState(
        () => _error =
            'Der Gruppenname stimmt nicht mit „${widget.handle}" '
            'überein.',
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Löschen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Gruppe endgültig löschen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alle Fahrten, Personen und Einstellungen von '
            '„${widget.handle}" werden gelöscht — und dieses '
            'Verwalter-Konto gleich mit. Es gibt kein Zurück.',
          ),
          const SizedBox(height: AppSpacing.m),
          PasswordField(
            controller: _adminPassword,
            labelText: 'Dein Admin-Passwort',
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.s),
          TextField(
            controller: _handleConfirmation,
            decoration: InputDecoration(
              labelText: 'Zur Bestätigung: ${widget.handle}',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _submit,
          child: const Text('Endgültig löschen'),
        ),
      ],
    );
  }
}

/// „E-Mail-Adresse ändern" — in beiden Zuständen erreichbar: Die Adresse
/// gehört zum Konto, nicht zur Verknüpfung.
class _ChangeEmailTile extends StatelessWidget {
  const _ChangeEmailTile();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.alternate_email),
        title: const Text('E-Mail-Adresse ändern'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => const _ChangeEmailDialog(),
        ),
      ),
    );
  }
}

/// Neue E-Mail-Adresse — Supabase-Standard „secure email change":
/// Bestätigungs-Links an die alte UND die neue Adresse, erst dann gilt sie.
class _ChangeEmailDialog extends ConsumerStatefulWidget {
  const _ChangeEmailDialog();

  @override
  ConsumerState<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends ConsumerState<_ChangeEmailDialog> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Bitte eine gültige E-Mail-Adresse angeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changeAdminEmail(email);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bestätigungs-Links sind an die alte und die neue Adresse '
            'unterwegs. Erst wenn beide angetippt sind, gilt die neue.',
          ),
        ),
      );
    } on EmailTakenException {
      if (mounted) {
        setState(() => _error = 'Diese Adresse hat schon ein Konto.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Ändern fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('E-Mail-Adresse ändern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Zur Sicherheit gehen Bestätigungs-Links an die alte UND die '
            'neue Adresse — erst wenn beide angetippt sind, gilt die neue.',
          ),
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Neue E-Mail-Adresse',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Ändern'),
        ),
      ],
    );
  }
}

/// Die Übergabe: Verknüpfung lösen mit Sudo-Bestätigung. Absichtlich kein
/// getippter Handle wie beim Löschen — der Schritt ist umkehrbar (neu
/// verknüpfen), das eigene Admin-Passwort reicht als Beweis.
class _ReleaseGroupDialog extends ConsumerStatefulWidget {
  const _ReleaseGroupDialog();

  @override
  ConsumerState<_ReleaseGroupDialog> createState() =>
      _ReleaseGroupDialogState();
}

class _ReleaseGroupDialogState extends ConsumerState<_ReleaseGroupDialog> {
  final _adminPassword = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).releaseGroup(_adminPassword.text);
      if (!mounted) return;
      Navigator.pop(context);
      ref.invalidate(adminGroupProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verknüpfung gelöst — das nächste Konto kann sich mit dem '
            'Gruppen-Login verknüpfen.',
          ),
        ),
      );
    } on WrongAdminPassword {
      setState(() => _error = 'Das Admin-Passwort stimmt nicht.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Lösen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verknüpfung lösen?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Danach kann sich das nächste Verwalter-Konto mit Gruppenname '
            'und Gruppenpasswort verknüpfen — wer zuerst verknüpft, '
            'verwaltet. Zur Bestätigung dein Admin-Passwort:',
          ),
          const SizedBox(height: AppSpacing.m),
          PasswordField(
            controller: _adminPassword,
            labelText: 'Dein Admin-Passwort',
            autofocus: true,
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : _submit,
          child: const Text('Lösen'),
        ),
      ],
    );
  }
}
