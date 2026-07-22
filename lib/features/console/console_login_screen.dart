/// console_login_screen.dart – Zugang zur Verwalter-Konsole.
///
/// Das Verwalter-Konto ist ein echtes E-Mail-Konto — deshalb funktionieren
/// hier die Supabase-Standardflüsse: Registrieren mit Bestätigungs-Mail und
/// „Passwort vergessen" per Reset-Link. Kein Betreiber nötig. Die
/// Gruppen-Mitglieder bekommen von alledem nichts mit; ihr Login bleibt
/// Handle + geteiltes Passwort.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tokens.dart';
import '../../core/widgets/ride_buddy_mark.dart';
import '../../data/providers.dart';

class ConsoleLoginScreen extends ConsumerStatefulWidget {
  const ConsoleLoginScreen({super.key});

  @override
  ConsumerState<ConsoleLoginScreen> createState() => _ConsoleLoginScreenState();
}

class _ConsoleLoginScreenState extends ConsumerState<ConsoleLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _notice = 'Bitte eine gültige E-Mail-Adresse angeben.');
      return;
    }
    if (password.length < 8) {
      setState(() => _notice = 'Das Passwort braucht mindestens 8 Zeichen.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (_register) {
        await auth.signUpAdmin(email, password);
        if (!mounted) return;
        setState(
          () => _notice =
              'Fast geschafft: Bitte den Bestätigungs-Link aus der '
              'E-Mail antippen, danach hier anmelden.',
        );
      } else {
        await auth.signInAdmin(email, password);
        // Der Router-Redirect übernimmt und führt in die Konsole.
      }
    } catch (_) {
      // Bewusst ohne Fehlertext: Er könnte verraten, ob die Adresse ein
      // Konto hat — und gehört ohnehin nie in logRing.
      if (mounted) {
        setState(
          () => _notice = _register
              ? 'Registrieren hat nicht geklappt. Gibt es das Konto schon?'
              : 'Anmeldung fehlgeschlagen – E-Mail oder Passwort falsch.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(
        () => _notice = 'Für den Reset-Link oben die E-Mail-Adresse eintragen.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendAdminPasswordReset(email);
    } catch (_) {
      // Absichtlich gleiche Meldung wie im Erfolgsfall (kein Konto-Orakel).
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice =
              'Wenn es zu dieser Adresse ein Konto gibt, ist ein '
              'Reset-Link unterwegs.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Verwalter-Konsole')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: RideBuddyMark(size: 72)),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      'Für die Person, die die Gruppe verwaltet: Mit einem '
                      'eigenen E-Mail-Konto lässt sich das Gruppenpasswort '
                      'neu setzen oder die Gruppe löschen. Die Mitglieder '
                      'brauchen davon nichts — und sehen deine E-Mail nie.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Anmelden')),
                        ButtonSegment(value: true, label: Text('Registrieren')),
                      ],
                      selected: {_register},
                      onSelectionChanged: (s) =>
                          setState(() => _register = s.first),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(
                        labelText: 'Passwort',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                    if (_notice case final notice?) ...[
                      const SizedBox(height: AppSpacing.m),
                      Text(
                        notice,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.l),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Registrieren' : 'Anmelden'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _forgotPassword,
                      child: const Text('Passwort vergessen?'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => context.go('/login'),
                      child: const Text('Zurück zum Gruppen-Login'),
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
