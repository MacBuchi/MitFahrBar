/// pending_screen.dart – Gruppe ist angemeldet, aber nicht aktiv.
///
/// Das Gate für alles außer `active`. Seit #108 gibt es keine Freigabe mehr,
/// also auch kein „warten" — die drei Zustände hier sind die, die es wirklich
/// gibt:
///
/// * `pending` — nie in Gebrauch genommen. Ein direktes `auth.signUp` gegen
///   die Gruppen-Domain ist nicht abstellbar (die Verwalter-Registrierung
///   braucht offenes Signup); so ein Zugang landet hier und bleibt inert.
/// * `rejected` — Altbestand aus der Freigabe-Zeit, ein ausgesprochenes Nein.
/// * `archived` — stillgelegt, verlustfrei und umkehrbar. **Und der
///   Auffangzustand für jeden Status, den diese Fassung nicht kennt**
///   ([Group.statusFrom]): Genau dieser Zweig ist der Grund, warum der Server
///   künftig einen neuen Zustand einführen kann, ohne dass ein
///   veröffentlichter Client dafür ein Release braucht.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/group.dart';

class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key, required this.status});

  final GroupStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title, body) = switch (status) {
      GroupStatus.rejected => (
        Icons.block,
        'Zugang abgelehnt',
        'Diese Gruppe wurde nicht freigegeben. Bei Fragen wende dich an den '
            'Verwalter der Gruppe.',
      ),
      GroupStatus.archived => (
        Icons.inventory_2_outlined,
        'Gruppe stillgelegt',
        'Diese Fahrgemeinschaft ist stillgelegt. Die Fahrten sind nicht '
            'gelöscht — wer sie wieder in Gebrauch nehmen möchte, wendet sich '
            'an den Verwalter der Gruppe (Verwalter-Konsole).',
      ),
      // `active` kommt hier nie an (das Gate im AppShell fängt es ab), also
      // steht der pending-Text für beide verbleibenden Fälle.
      _ => (
        Icons.hourglass_top_outlined,
        'Nicht in Gebrauch',
        'Dieser Zugang wurde angelegt, aber nie als Fahrgemeinschaft '
            'eingerichtet. Neue Gruppen entstehen in der Verwalter-Konsole — '
            'dort legt man sie mit einem eigenen Konto an und kann sie sofort '
            'nutzen.',
      ),
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(body, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.l),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(myGroupProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Erneut prüfen'),
                ),
                const SizedBox(height: AppSpacing.s),
                TextButton(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
