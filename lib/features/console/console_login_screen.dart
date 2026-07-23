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

/// Drei Zustände statt zwei: „Passwort vergessen" ist ein eigener Modus,
/// der nur die E-Mail abfragt — ein sichtbares Passwortfeld daneben
/// verleitet sonst dazu, dort das (vergessene) Passwort einzutippen.
enum _Mode { signIn, register, forgot }

class ConsoleLoginScreen extends ConsumerStatefulWidget {
  const ConsoleLoginScreen({super.key});

  @override
  ConsumerState<ConsoleLoginScreen> createState() => _ConsoleLoginScreenState();
}

class _ConsoleLoginScreenState extends ConsumerState<ConsoleLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _switchMode(_Mode mode) => setState(() {
    _mode = mode;
    _notice = null;
  });

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
    if (_mode == _Mode.register && password != _repeat.text) {
      setState(() => _notice = 'Die Passwörter stimmen nicht überein.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (_mode == _Mode.register) {
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
          () => _notice = _mode == _Mode.register
              ? 'Registrieren hat nicht geklappt. Gibt es das Konto schon?'
              : 'Anmeldung fehlgeschlagen – E-Mail oder Passwort falsch.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _notice = 'Bitte eine gültige E-Mail-Adresse angeben.');
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
    final forgot = _mode == _Mode.forgot;
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
                      forgot
                          ? 'Passwort vergessen? Kein Problem: RideBuddy '
                                'schickt dir einen Link zum Neu-Setzen an '
                                'deine E-Mail-Adresse.'
                          : 'Für die Person, die die Gruppe verwaltet: Mit '
                                'einem eigenen E-Mail-Konto lässt sich das '
                                'Gruppenpasswort neu setzen oder die Gruppe '
                                'löschen. Die Mitglieder brauchen davon '
                                'nichts — und sehen deine E-Mail nie.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    if (!forgot) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Anmelden')),
                          ButtonSegment(
                            value: true,
                            label: Text('Registrieren'),
                          ),
                        ],
                        selected: {_mode == _Mode.register},
                        onSelectionChanged: (s) => _switchMode(
                          s.first ? _Mode.register : _Mode.signIn,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.m),
                    ],
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'E-Mail',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: forgot
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) =>
                          forgot && !_busy ? _sendReset() : null,
                    ),
                    if (!forgot) ...[
                      const SizedBox(height: AppSpacing.m),
                      TextField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'Passwort',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        autofillHints: [
                          if (_mode == _Mode.register)
                            AutofillHints.newPassword
                          else
                            AutofillHints.password,
                        ],
                        textInputAction: _mode == _Mode.register
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) =>
                            _mode == _Mode.signIn && !_busy ? _submit() : null,
                      ),
                    ],
                    if (_mode == _Mode.register) ...[
                      const SizedBox(height: AppSpacing.m),
                      TextField(
                        controller: _repeat,
                        decoration: const InputDecoration(
                          labelText: 'Passwort wiederholen',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _submit(),
                      ),
                    ],
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
                      onPressed: _busy ? null : (forgot ? _sendReset : _submit),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(switch (_mode) {
                              _Mode.signIn => 'Anmelden',
                              _Mode.register => 'Registrieren',
                              _Mode.forgot => 'Reset-Link senden',
                            }),
                    ),
                    if (forgot)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _switchMode(_Mode.signIn),
                        child: const Text('Zurück zur Anmeldung'),
                      )
                    else
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _switchMode(_Mode.forgot),
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
