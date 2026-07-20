/// pending_screen.dart – Gruppe wartet auf Freigabe (oder wurde abgelehnt).
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
    final rejected = status == GroupStatus.rejected;
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
                  rejected ? Icons.block : Icons.hourglass_top_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  rejected ? 'Anfrage abgelehnt' : 'Warte auf Freigabe',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  rejected
                      ? 'Diese Gruppe wurde nicht freigegeben. Bei Fragen '
                            'wende dich an den Betreiber.'
                      : 'Deine Gruppe wurde angefragt und wird geprüft. '
                            'Sobald sie freigegeben ist, erscheint hier die App '
                            '– einfach später erneut anmelden.',
                  textAlign: TextAlign.center,
                ),
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
