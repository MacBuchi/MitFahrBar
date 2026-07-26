/// console_screen.dart – Die Verwalter-Konsole selbst (Issue #55, #106).
///
/// Bewusst karg: Gruppen anlegen, übernehmen, Gruppenpasswort neu setzen,
/// Verknüpfung lösen, Gruppe löschen — dazu das eigene Konto (Passwort,
/// E-Mail). Mehr kann und soll das Verwalter-Konto nicht: Gruppendaten sieht
/// es nie (anderer uid, RLS blockt).
///
/// Ein Konto trägt bis zu [groupCap] Gruppen, deshalb ist der Screen eine
/// **Liste**. Jede Karte nennt ihre Gruppe, und jede Aktion bekommt die
/// `groupId` mit — der Server prüft zusätzlich, dass sie diesem Konto gehört.
///
/// Die Aktionen stehen absichtlich **offen** in der Karte und nicht in einem
/// Aufklapp-Element: Die Labels „Verknüpfung lösen …" und „Gruppe löschen …"
/// sind der Anker für die Flow-Tests — in einem `ExpansionTile` wären sie
/// erst nach einem Tipp im Widget-Baum. (Der Browser-E2E greift dagegen das
/// ListTile „Verwaltet: …": Flutter-Web exponiert diese Knöpfe nicht im
/// Semantics-Baum.)
///
/// „Passwort vergessen" endet NICHT hier: Das läuft seit dem Code-Weg
/// vollständig auf dem Konsolen-Login ab (Issue #102). Der Dialog unten ist
/// nur noch die bewusste Änderung im angemeldeten Zustand.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/group_login.dart';
import '../../core/tokens.dart';
import '../../core/widgets/password_field.dart';
import '../../data/admin_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/providers.dart';

class ConsoleScreen extends ConsumerWidget {
  const ConsoleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(adminGroupsProvider);
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
      body: switch (groups) {
        AsyncData(value: final list) => _Body(groups: list),
        AsyncError() => const Center(
          child: Text('Fehler beim Laden der Gruppen.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.groups});

  final List<AdminGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = groups.length >= groupCap;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Deine Gruppen', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  groups.isEmpty
                      ? 'Noch keine — lege deine erste an.'
                      : '${groups.length} von $groupCap verwaltet.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.m),
                for (final group in groups) _GroupCard(group: group),
                const SizedBox(height: AppSpacing.s),
                if (full)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      child: Text(
                        'Dieses Konto verwaltet die höchstmöglichen '
                        '$groupCap Gruppen. Löse eine Verknüpfung, um eine '
                        'weitere anzulegen.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else ...[
                  const _CreateGroupCard(),
                  const _ClaimCard(),
                ],
                const SizedBox(height: AppSpacing.m),
                Text('Dein Konto', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eine verwaltete Gruppe mit ihren drei Aktionen.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final AdminGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(group.name),
            subtitle: Text('Verwaltet: ${group.handle}'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.s,
              children: [
                FilledButton.tonal(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => _GroupPasswordDialog(group: group),
                  ),
                  child: const Text('Gruppenpasswort neu setzen'),
                ),
                FilledButton.tonal(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => _ReleaseGroupDialog(group: group),
                  ),
                  child: const Text('Verknüpfung lösen …'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => _DeleteGroupDialog(group: group),
                  ),
                  child: const Text('Gruppe löschen …'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Neue Gruppe anlegen — sofort nutzbar, ohne Freigabe.
///
/// Das Gruppenpasswort wird **zweimal** eingetippt (Issue #107): Es ist ein
/// geteiltes Passwort ohne „vergessen"-Weg. Ein Tippfehler erzeugte sonst
/// eine Gruppe, in die niemand hineinkommt — auch die Person nicht, die sie
/// angelegt hat, denn sie weiß nicht, was sie wirklich getippt hat. Verglichen
/// wird beim Absenden, nicht bei jedem Tastendruck: Eine Warnung, während man
/// das zweite Feld noch füllt, ist nur Lärm.
class _CreateGroupCard extends ConsumerStatefulWidget {
  const _CreateGroupCard();

  @override
  ConsumerState<_CreateGroupCard> createState() => _CreateGroupCardState();
}

class _CreateGroupCardState extends ConsumerState<_CreateGroupCard> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final handle = normalizeHandle(_handle.text);
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Namen für die Gruppe angeben.');
      return;
    }
    if (handle.length < 3) {
      setState(() => _error = 'Der Anmeldename braucht mindestens 3 Zeichen.');
      return;
    }
    if (_password.text.length < 8) {
      setState(
        () => _error =
            'Das Gruppenpasswort braucht mindestens 8 '
            'Zeichen.',
      );
      return;
    }
    if (_password.text != _repeat.text) {
      setState(() => _error = 'Die Eingaben stimmen nicht überein.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .createGroup(
            handle: handle,
            password: _password.text,
            groupName: name,
          );
      // Dem Passwortmanager sagen, dass die Eingabe fertig ist — sonst bietet
      // er das Speichern nicht an.
      TextInput.finishAutofillContext();
      if (!mounted) return;
      _name.clear();
      _handle.clear();
      _password.clear();
      _repeat.clear();
      ref.invalidate(adminGroupsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gruppe angelegt. Gib Anmeldename und Gruppenpasswort allen '
            'Mitgliedern.',
          ),
        ),
      );
    } on HandleTakenException {
      setState(() => _error = 'Dieser Anmeldename ist schon vergeben.');
    } on GroupLimitReached {
      setState(
        () => _error = 'Dieses Konto verwaltet bereits $groupCap Gruppen.',
      );
    } catch (_) {
      // Bewusst ohne den Fehlertext: Er könnte das Passwort tragen, und was
      // in der Oberfläche steht, landet über eine Rückmeldung im Log.
      setState(() => _error = 'Anlegen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Neue Gruppe anlegen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.s),
              const Text(
                'Die Gruppe ist sofort nutzbar. Alle Mitglieder teilen sich '
                'einen Zugang: Anmeldename und Gruppenpasswort gibst du '
                'weiter — dieses Verwalter-Konto bleibt bei dir.',
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name der Gruppe',
                  helperText: 'Zum Beispiel: Fahrgemeinschaft Nordstadt',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.m),
              TextField(
                controller: _handle,
                decoration: const InputDecoration(
                  labelText: 'Anmeldename',
                  helperText:
                      'Damit melden sich alle an — kurz und klein '
                      'geschrieben.',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.m),
              PasswordField(
                controller: _password,
                labelText: 'Gruppenpasswort',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.m),
              PasswordField(
                controller: _repeat,
                labelText: 'Gruppenpasswort wiederholen',
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _busy ? null : _submit(),
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
                onPressed: _busy ? null : _submit,
                child: const Text('Gruppe anlegen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine **bestehende** Gruppe übernehmen: Beweis ist das Gruppen-Login. Nur
/// möglich, solange die Gruppe keinen Verwalter hat — danach rastet es ein.
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
        () => _error = 'Bitte Anmeldename und Gruppenpasswort eintragen.',
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
      if (!mounted) return;
      _handle.clear();
      _groupPassword.clear();
      ref.invalidate(adminGroupsProvider);
    } on WrongGroupCredentials {
      setState(() => _error = 'Anmeldename oder Gruppenpasswort falsch.');
    } on GroupAlreadyClaimed {
      setState(() => _error = 'Diese Gruppe hat schon ein Verwalter-Konto.');
    } on GroupLimitReached {
      setState(
        () => _error = 'Dieses Konto verwaltet bereits $groupCap Gruppen.',
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
              'Gibt es die Gruppe schon und hat sie noch keinen Verwalter? '
              'Dann übernimm sie hier. Als Nachweis dienen einmalig '
              'Anmeldename und Gruppenpasswort — wer zuerst verknüpft, '
              'verwaltet.',
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _handle,
              decoration: const InputDecoration(
                labelText: 'Anmeldename der Gruppe',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.m),
            // Absichtlich nicht „Gruppenpasswort": Dieses Formular steht neben
            // dem Anlegen, und zwei gleich benannte Felder auf einem Screen
            // sind für Bedienung und Tests gleichermaßen mehrdeutig.
            PasswordField(
              controller: _groupPassword,
              labelText: 'Passwort der Gruppe',
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

/// Neues geteiltes Gruppenpasswort (die Rettungsleine).
class _GroupPasswordDialog extends ConsumerStatefulWidget {
  const _GroupPasswordDialog({required this.group});

  final AdminGroup group;

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
          .resetGroupPassword(
            groupId: widget.group.id,
            newPassword: _password.text,
          );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Für „${widget.group.handle}".'),
          const SizedBox(height: AppSpacing.m),
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

/// Eigenes Admin-Passwort ändern, während man angemeldet ist. Das
/// Zurücksetzen eines vergessenen Passworts läuft NICHT hier, sondern über
/// den Code aus der Mail auf dem Konsolen-Login.
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
/// Anmeldename. Beides prüft der **Server**, nicht dieser Dialog.
class _DeleteGroupDialog extends ConsumerStatefulWidget {
  const _DeleteGroupDialog({required this.group});

  final AdminGroup group;

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
            groupId: widget.group.id,
            adminPassword: _adminPassword.text,
            handleConfirmation: _handleConfirmation.text.trim(),
          );
      // Die Gruppe ist weg, dieses Konto lebt weiter (es trägt womöglich
      // andere Gruppen). Also nur den Dialog schließen und die Liste neu
      // laden — früher endete der Weg hier im Abmelden.
      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(adminGroupsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('„${widget.group.handle}" ist gelöscht.')),
      );
    } on WrongAdminPassword {
      setState(() => _error = 'Das Admin-Passwort stimmt nicht.');
    } on HandleMismatch {
      setState(
        () => _error =
            'Der Anmeldename stimmt nicht mit „${widget.group.handle}" '
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
            '„${widget.group.handle}" werden gelöscht. Es gibt kein Zurück — '
            'die einzige Kopie ist ein vorher gemachter CSV-Export aus der '
            'App. Dein Verwalter-Konto bleibt bestehen.',
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
              labelText: 'Zur Bestätigung: ${widget.group.handle}',
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

/// „E-Mail-Adresse ändern" — die Adresse gehört zum Konto, nicht zu einer
/// Gruppe.
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
  const _ReleaseGroupDialog({required this.group});

  final AdminGroup group;

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
      await ref
          .read(adminRepositoryProvider)
          .releaseGroup(
            groupId: widget.group.id,
            adminPassword: _adminPassword.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ref.invalidate(adminGroupsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verknüpfung gelöst — bis jemand übernimmt, hat die Gruppe '
            'keinen Verwalter.',
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
          Text(
            'Danach kann sich das nächste Verwalter-Konto mit Anmeldename '
            'und Gruppenpasswort von „${widget.group.handle}" verknüpfen — '
            'wer zuerst verknüpft, verwaltet. Bis dahin hat die Gruppe '
            'keinen Verwalter; die Fahrgemeinschaft selbst läuft weiter. '
            'Zur Bestätigung dein Admin-Passwort:',
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
