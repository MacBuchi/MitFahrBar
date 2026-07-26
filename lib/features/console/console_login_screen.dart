/// console_login_screen.dart – Zugang zur Verwalter-Konsole.
///
/// Das Verwalter-Konto ist ein echtes E-Mail-Konto — deshalb funktionieren
/// hier die Supabase-Standardflüsse: Registrieren und „Passwort vergessen".
/// Kein Betreiber nötig. Die Gruppen-Mitglieder bekommen von alledem nichts
/// mit; ihr Login bleibt Handle + geteiltes Passwort.
///
/// Beide Mail-Wege laufen über den **Zahlencode** aus der Mail, nicht über
/// deren Link (Issue #102): Der Link ist an das Gerät gebunden, das ihn
/// angefordert hat (PKCE-Verifier im lokalen Speicher), und stirbt, wenn die
/// Mail woanders geöffnet wird — der Normalfall, wenn man in der App
/// anfordert und im Handy-Browser liest. Begründung an
/// `AuthRepository.sendAdminPasswordResetCode`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/tokens.dart';
import '../../core/widgets/password_field.dart';
import '../../core/widgets/mitfahrbar_mark.dart';
import '../../data/auth_repository.dart';
import '../../data/providers.dart';

/// Ein Modus je Maske. „Passwort vergessen" ist bewusst ein eigener Zustand,
/// der nur die E-Mail abfragt — ein sichtbares Passwortfeld daneben verleitet
/// dazu, dort das (vergessene) Passwort einzutippen. Auf [forgot] folgt
/// [code] (Code + neues Passwort), auf [register] folgt [confirm] (Code aus
/// der Registrierungs-Mail).
enum _Mode { signIn, register, confirm, forgot, code }

class ConsoleLoginScreen extends ConsumerStatefulWidget {
  const ConsoleLoginScreen({super.key});

  @override
  ConsumerState<ConsoleLoginScreen> createState() => _ConsoleLoginScreenState();
}

class _ConsoleLoginScreenState extends ConsumerState<ConsoleLoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Doppelt belegt: im Anmelde-/Registrieren-Modus das Passwort, im
  /// [_Mode.code]-Modus das neue. Ein Feldpaar statt zweier, weil beide
  /// Masken nie gleichzeitig sichtbar sind — die Beschriftung unterscheidet.
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _switchMode(_Mode mode) => setState(() {
    _mode = mode;
    _notice = null;
    _code.clear();
    _password.clear();
    _repeat.clear();
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
        setState(() {
          _mode = _Mode.confirm;
          _password.clear();
          _repeat.clear();
          _notice =
              'Fast geschafft: Wir haben einen Code an $email geschickt. '
              'Gib ihn hier ein, dann geht es direkt weiter.';
        });
      } else {
        await auth.signInAdmin(email, password);
        // Der Router-Redirect übernimmt und führt in die Konsole.
      }
    } on EmailNotConfirmedException {
      if (mounted) {
        setState(() {
          _mode = _Mode.confirm;
          _password.clear();
          _notice =
              'Dieses Konto ist noch nicht bestätigt. Gib den Code aus der '
              'Registrierungs-Mail ein — oder lass dir einen neuen schicken.';
        });
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

  Future<void> _resendConfirmation() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _notice = 'Bitte eine gültige E-Mail-Adresse angeben.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).resendAdminConfirmation(email);
    } catch (_) {
      // Gleiche Meldung wie im Erfolgsfall (kein Konto-Orakel) — auch wenn
      // GoTrue drosselt, weil gerade erst eine Mail rausging.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice =
              'Wenn es zu dieser Adresse ein unbestätigtes Konto gibt, '
              'ist ein neuer Code unterwegs.';
        });
      }
    }
  }

  /// Adresse mit dem Code aus der Registrierungs-Mail bestätigen. Die Sitzung
  /// kommt aus `verifyOTP` gleich mit, der Router führt in die Konsole.
  Future<void> _confirmEmail() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _notice = 'Bitte den Code aus der Mail eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmAdminEmailWithCode(email: _email.text.trim(), code: code);
    } on InvalidCodeException {
      if (mounted) {
        setState(
          () => _notice =
              'Der Code ist falsch oder abgelaufen — bitte einen neuen '
              'anfordern.',
        );
      }
    } catch (_) {
      // Ohne Fehlertext: Er könnte verraten, ob die Adresse ein Konto hat.
      if (mounted) setState(() => _notice = 'Bestätigen hat nicht geklappt.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fordert den Reset-Code an. Erfolg und Fehlschlag melden dasselbe und
  /// führen beide in die Code-Eingabe — ein Unterschied würde verraten, ob es
  /// zu der Adresse ein Konto gibt.
  Future<void> _sendResetCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _notice = 'Bitte eine gültige E-Mail-Adresse angeben.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendAdminPasswordResetCode(email);
    } catch (_) {
      // Absichtlich gleiche Meldung wie im Erfolgsfall (kein Konto-Orakel).
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _mode = _Mode.code;
          _notice =
              'Wenn es zu $email ein Konto gibt, ist ein Code unterwegs. '
              'Er gilt eine Stunde.';
        });
      }
    }
  }

  /// Code einlösen und neues Passwort setzen. Kein Erfolgs-Hinweis nötig: Das
  /// geänderte Passwort meldet die Sitzung an, der Router führt in die Konsole.
  Future<void> _resetPassword() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _notice = 'Bitte den Code aus der Mail eingeben.');
      return;
    }
    if (_password.text.length < 8) {
      setState(
        () => _notice = 'Das neue Passwort braucht mindestens 8 Zeichen.',
      );
      return;
    }
    if (_password.text != _repeat.text) {
      setState(() => _notice = 'Die Passwörter stimmen nicht überein.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resetAdminPasswordWithCode(
            email: _email.text.trim(),
            code: code,
            newPassword: _password.text,
          );
    } on InvalidCodeException {
      await _discardRecoverySession();
      if (mounted) {
        setState(
          () => _notice =
              'Der Code ist falsch oder abgelaufen — bitte einen neuen '
              'anfordern.',
        );
      }
    } on WeakPasswordException {
      await _discardRecoverySession();
      if (mounted) {
        setState(
          () => _notice =
              'Dieses Passwort ist zu unsicher — bitte ein anderes wählen.',
        );
      }
    } on SamePasswordException {
      await _discardRecoverySession();
      if (mounted) {
        setState(
          () => _notice =
              'Das ist das bisherige Passwort — bitte ein neues wählen.',
        );
      }
    } catch (_) {
      await _discardRecoverySession();
      // Bewusst ohne Fehlertext: Er trüge sonst das neue Passwort oder einen
      // Hinweis auf die Existenz des Kontos weiter.
      if (mounted) setState(() => _notice = 'Zurücksetzen fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Die Recovery-Sitzung aus `verifyOTP` darf nicht liegen bleiben, wenn das
  /// Ändern scheiterte — sonst steckt jemand halb angemeldet fest: eingeloggt,
  /// ohne sein Passwort zu kennen.
  Future<void> _discardRecoverySession() async {
    final auth = ref.read(authRepositoryProvider);
    if (!auth.loggedIn) return;
    try {
      await auth.signOut();
    } catch (_) {
      // Aufräumen darf den eigentlichen Fehler nicht überdecken.
    }
  }

  /// Der Knopf unten: je Modus eine Beschriftung und eine Aktion.
  String get _primaryLabel => switch (_mode) {
    _Mode.signIn => 'Anmelden',
    _Mode.register => 'Registrieren',
    _Mode.confirm => 'Adresse bestätigen',
    _Mode.forgot => 'Code anfordern',
    _Mode.code => 'Neues Passwort speichern',
  };

  Future<void> Function() get _primaryAction => switch (_mode) {
    _Mode.signIn || _Mode.register => _submit,
    _Mode.confirm => _confirmEmail,
    _Mode.forgot => _sendResetCode,
    _Mode.code => _resetPassword,
  };

  String get _intro => switch (_mode) {
    _Mode.forgot =>
      'Passwort vergessen? Kein Problem: MitFahrBar schickt dir einen Code '
          'an deine E-Mail-Adresse, mit dem du hier ein neues setzt.',
    _Mode.code =>
      'Trag den Code aus der Mail ein und wähle ein neues Passwort. Der '
          'Code gilt eine Stunde.',
    _Mode.confirm =>
      'Nur noch der Code aus der Mail — danach ist deine Adresse bestätigt '
          'und du bist drin.',
    _ =>
      'Für die Person, die die Gruppe verwaltet: Mit einem eigenen '
          'E-Mail-Konto lässt sich das Gruppenpasswort neu setzen oder die '
          'Gruppe löschen. Die Mitglieder brauchen davon nichts — und sehen '
          'deine E-Mail nie.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSwitcher = _mode == _Mode.signIn || _mode == _Mode.register;
    final showCode = _mode == _Mode.confirm || _mode == _Mode.code;
    final showPassword = _mode != _Mode.confirm && _mode != _Mode.forgot;
    final showRepeat = _mode == _Mode.register || _mode == _Mode.code;
    final newPassword = _mode == _Mode.code;
    // Der letzte sichtbare Eingabeschritt schließt mit „fertig" ab und löst
    // den Knopf aus — sonst hängt die Tastatur am Zeilenumbruch.
    final submitFromEmail = _mode == _Mode.forgot;
    final submitFromCode = _mode == _Mode.confirm;

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
                    const Center(child: MitFahrBarMark(size: 72)),
                    const SizedBox(height: AppSpacing.m),
                    Text(_intro, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.l),
                    if (showSwitcher) ...[
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
                      textInputAction: submitFromEmail
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) =>
                          submitFromEmail && !_busy ? _primaryAction() : null,
                    ),
                    if (showCode) ...[
                      const SizedBox(height: AppSpacing.m),
                      TextField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'Code aus der Mail',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        textInputAction: submitFromCode
                            ? TextInputAction.done
                            : TextInputAction.next,
                        onSubmitted: (_) =>
                            submitFromCode && !_busy ? _primaryAction() : null,
                      ),
                    ],
                    if (showPassword) ...[
                      const SizedBox(height: AppSpacing.m),
                      PasswordField(
                        controller: _password,
                        labelText: newPassword ? 'Neues Passwort' : 'Passwort',
                        autofillHints: [
                          if (_mode == _Mode.signIn)
                            AutofillHints.password
                          else
                            AutofillHints.newPassword,
                        ],
                        textInputAction: showRepeat
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: (_) =>
                            _mode == _Mode.signIn && !_busy ? _submit() : null,
                      ),
                    ],
                    if (showRepeat) ...[
                      const SizedBox(height: AppSpacing.m),
                      PasswordField(
                        controller: _repeat,
                        labelText: newPassword
                            ? 'Neues Passwort wiederholen'
                            : 'Passwort wiederholen',
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _primaryAction(),
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
                      onPressed: _busy ? null : _primaryAction,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_primaryLabel),
                    ),
                    if (_mode == _Mode.confirm)
                      TextButton(
                        onPressed: _busy ? null : _resendConfirmation,
                        child: const Text('Bestätigungs-Mail erneut senden'),
                      ),
                    if (showSwitcher)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _switchMode(_Mode.forgot),
                        child: const Text('Passwort vergessen?'),
                      )
                    else
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _switchMode(_Mode.signIn),
                        child: const Text('Zurück zur Anmeldung'),
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
