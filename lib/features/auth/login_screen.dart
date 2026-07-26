/// login_screen.dart – Gruppen-Login: Gruppenname (Handle) + Passwort.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tokens.dart';
import '../../core/widgets/password_field.dart';
import '../../core/widgets/mitfahrbar_mark.dart';
import '../../data/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _handle = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _handle.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_handle.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(_handle.text.trim(), _password.text);
      // Signalisiert dem Passwort-Manager, die Zugangsdaten zu speichern.
      TextInput.finishAutofillContext();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Anmeldung fehlgeschlagen – Name oder Passwort falsch.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: AutofillGroup(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: MitFahrBarMark(size: 120)),
                    // Die Straße unter den Rädern: Die Marke hat im
                    // 120×100-Raster 8 % Luft unter den Rädern (~8 px bei
                    // Größe 120) — der negative Versatz stellt das Auto
                    // auf die Linie statt darüber schweben zu lassen.
                    Center(
                      child: Transform.translate(
                        offset: const Offset(0, -6),
                        child: const RoadLine(width: 146),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    const Center(child: MitFahrBarWordmark(fontSize: 34)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Die faire App für eure Fahrgemeinschaft',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _handle,
                      decoration: const InputDecoration(
                        labelText: 'Gruppenname',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    PasswordField(
                      controller: _password,
                      labelText: 'Passwort',
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _signIn(),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Anmelden'),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    // Dezent, aber der einzige Weg zu einer neuen Gruppe:
                    // Angelegt werden sie seit #106 in der Konsole, von einem
                    // Verwalter-Konto mit echter E-Mail-Adresse. Für alle
                    // anderen Mitglieder bleibt dieser Knopf ohne Bedeutung —
                    // sie melden sich oben mit dem geteilten Zugang an.
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => context.push('/console/login'),
                      child: const Text('Verwalter-Konsole'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
