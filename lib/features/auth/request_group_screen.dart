/// request_group_screen.dart – Neue Gruppe anfragen (Freigabe durch Admin).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/group_login.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';

class RequestGroupScreen extends ConsumerStatefulWidget {
  const RequestGroupScreen({super.key});

  @override
  ConsumerState<RequestGroupScreen> createState() => _RequestGroupScreenState();
}

class _RequestGroupScreenState extends ConsumerState<RequestGroupScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Bitte einen Gruppennamen angeben.';
    if (normalizeHandle(_handle.text).length < 3) {
      return 'Der Anmeldename braucht mindestens 3 Zeichen (a–z, 0–9).';
    }
    if (_password.text.length < 8) {
      return 'Das Passwort sollte mindestens 8 Zeichen haben.';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .requestGroup(
            handle: normalizeHandle(_handle.text),
            password: _password.text,
            groupName: _name.text.trim(),
          );
      // Signalisiert dem Passwort-Manager, die Zugangsdaten zu speichern.
      TextInput.finishAutofillContext();
      // Damit die Anfrage nur eine Anfrage bleibt: sofort wieder ausloggen.
      await ref.read(authRepositoryProvider).signOut();
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anfrage fehlgeschlagen: Name evtl. schon vergeben.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gruppe anfragen')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: _done ? _confirmation(context) : _form(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _confirmation(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(
        Icons.mark_email_read_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: AppSpacing.m),
      Text(
        'Anfrage gestellt',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.s),
      const Text(
        'Deine Gruppe wurde angefragt und wird geprüft. Sobald sie '
        'freigegeben ist, kannst du dich mit Gruppenname und Passwort '
        'anmelden.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.l),
      FilledButton(
        onPressed: () => context.go('/login'),
        child: const Text('Zurück zur Anmeldung'),
      ),
    ],
  );

  Widget _form(BuildContext context) => AutofillGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Lege eine neue Fahrgemeinschaft an. Die Anfrage wird geprüft und '
          'nach Freigabe könnt ihr euch mit einem gemeinsamen Zugang '
          'anmelden.',
        ),
        const SizedBox(height: AppSpacing.l),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Gruppenname (Anzeige)',
            hintText: 'z. B. Pendler Musterstadt',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _handle,
          decoration: const InputDecoration(
            labelText: 'Anmeldename (kurz, a–z/0–9)',
            hintText: 'z. B. pendler-musterstadt',
            border: OutlineInputBorder(),
          ),
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _password,
          decoration: const InputDecoration(
            labelText: 'Gemeinsames Passwort',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Anfrage senden'),
        ),
      ],
    ),
  );
}
