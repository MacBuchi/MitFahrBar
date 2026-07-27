/// identity_dialog.dart – „Wer bist du?" auf diesem Gerät (#121).
///
/// **Kein Login, sondern eine Einstellung dieses Geräts** — die Begründung
/// steht bei `data/device_identity.dart`. Jeder kann jeden wählen und die
/// Auswahl jederzeit ändern; sie schützt vor Vertippern, nicht vor Menschen.
///
/// Ein Bild für beide Wege: die Startabfrage (mit „Später") und das Ändern
/// über das Menü (ohne). Zwei Dialoge mit derselben Liste wären zwei Stellen,
/// die auseinanderlaufen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/person.dart';

/// Zeigt die Auswahl. [atStart] rahmt sie als einmalige Frage beim ersten
/// Start und bietet „Später" an.
Future<void> showIdentityDialog(BuildContext context, {bool atStart = false}) =>
    showDialog<void>(
      context: context,
      // Die Startabfrage lässt sich nicht per Tipp daneben wegwischen: Sonst
      // gälte sie als beantwortet, ohne dass jemand etwas entschieden hätte.
      barrierDismissible: !atStart,
      builder: (_) => _IdentityDialog(atStart: atStart),
    );

class _IdentityDialog extends ConsumerWidget {
  const _IdentityDialog({required this.atStart});

  final bool atStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persons = ref.watch(personsProvider).value ?? const <Person>[];
    final active = [
      for (final person in persons)
        if (person.active) person,
    ];
    final current = ref.watch(deviceIdentityProvider).value?.personId;

    Future<void> pick(String? id) async {
      await ref.read(deviceIdentityProvider.notifier).choose(id);
      if (context.mounted) Navigator.of(context).pop();
    }

    return AlertDialog(
      title: Text(atStart ? 'Wer bist du?' : 'Ich bin'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: Text(
              'Damit weiß dieses Gerät, wen es meint — für '
              'Benachrichtigungen und damit du nicht aus Versehen bei '
              'jemand anderem einträgst. Du kannst das jederzeit im Menü '
              'ändern.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: RadioGroup<String>(
                groupValue: current,
                onChanged: (value) => pick(value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final person in active)
                      RadioListTile<String>(
                        value: person.id,
                        title: Text(person.name),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (atStart)
          TextButton(
            // „Später" zählt als beantwortet: Die Frage kommt nicht bei
            // jedem Start wieder. Erinnert wird über das Banner auf der
            // Übersicht — an genau einer Stelle.
            onPressed: () => pick(null),
            child: const Text('Später'),
          )
        else ...[
          if (current != null)
            TextButton(
              onPressed: () => pick(null),
              child: const Text('Niemand'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ],
    );
  }
}
