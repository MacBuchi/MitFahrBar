/// about_dialog.dart – „Über MitFahrBar": Version, „Was ist neu", Update.
///
/// Beantwortet die zwei Fragen, die sonst nirgends zu finden waren
/// (gemeldet 25.07.2026): Welche Version läuft hier — und was hat sich
/// mit ihr geändert? Bisher steckte die Version nur im Lizenz-Dialog,
/// und „Was ist neu" erschien nur, WENN gerade ein Update anstand.
///
/// Die Notes kommen vom GitHub-Release der laufenden Version — dieselbe
/// einzige Quelle wie im Update-Dialog (der Body ist der
/// CHANGELOG-Auszug). Offline oder im Demo-Modus fehlt der Abschnitt
/// einfach; ein Fehlerbalken wäre hier lauter als die Information wert ist.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/release_notes.dart';
import '../../core/tokens.dart';
import '../../core/update_check.dart';
import '../../core/widgets/mitfahrbar_mark.dart';
import '../banners/app_banners.dart';

Future<void> showAboutMitFahrBarDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AboutDialog());

class _AboutDialog extends ConsumerWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(currentVersionProvider).value;
    final update = ref.watch(updateInfoProvider).value;
    final notes = plainReleaseNotes(
      ref.watch(currentReleaseNotesProvider).value ?? '',
    );

    return AlertDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: MitFahrBarMark(size: 96)),
            const SizedBox(height: AppSpacing.s),
            const Center(child: MitFahrBarWordmark(fontSize: 24)),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: Text(
                version == null ? 'Version wird gelesen …' : 'Version $version',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (update != null) ...[
              const SizedBox(height: AppSpacing.m),
              FilledButton.tonalIcon(
                onPressed: () {
                  // Erst schließen, dann den Update-Dialog öffnen — über den
                  // Navigator-Kontext, der das Schließen überlebt; der
                  // eigene Kontext ist danach tot.
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  unawaited(showUpdateDialog(navigator.context, update));
                },
                icon: const Icon(Icons.system_update, size: 18),
                label: Text('Version ${update.latestVersion} ist verfügbar'),
              ),
            ],
            // Nur auf Android: Im Browser wird die App erst mit der
            // Beförderung ausgeliefert, ein Vorab-Kanal zeigte dort auf
            // nichts. Der Provider hält denselben Riegel — hier steht er
            // gegen einen Schalter, den man sonst umlegen könnte, ohne dass
            // je etwas passiert.
            if (updateIsDownload) ...[
              const SizedBox(height: AppSpacing.m),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: ref.watch(prereleaseChannelProvider).value ?? false,
                onChanged: (on) => unawaited(
                  ref.read(prereleaseChannelProvider.notifier).set(on),
                ),
                title: const Text('Vorabversionen erhalten'),
                subtitle: Text(
                  'Zeigt auch Versionen, die für die Gruppe noch nicht '
                  'freigegeben sind. Gilt nur für dieses Gerät.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              Text(
                'Was ist neu in dieser Version:',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(notes, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.l),
            // Pflichtangabe, nicht Höflichkeit: Beide Quellen stehen unter
            // Lizenzen, die eine Nennung verlangen — CC BY 4.0 bei den
            // Spritpreisen, ODbL bei OpenStreetMap. Sie gehört an die
            // Stelle, an der man nach Herkunft sucht, und nicht nur auf den
            // Screen, der die Daten gerade zeigt: Wer den nie öffnet, hat
            // die Nennung sonst nie gesehen.
            Text('Woher die Daten kommen', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Spritpreise: Tankerkönig-Spritpreis-API '
              '(creativecommons.tankerkoenig.de), CC BY 4.0 — Daten der '
              'Markttransparenzstelle für Kraftstoffe.\n'
              // Zwei Quellen, zwei Lizenzen: Die zurückliegenden Wochen
              // stammen aus dem historischen Archiv, und das steht NICHT
              // unter der CC BY 4.0 der Live-API.
              'Zurückliegende Wochen: Tankerkönig-Preisarchiv, '
              'CC BY-NC-SA 4.0.\n'
              'Ortssuche: OpenStreetMap (© OpenStreetMap-Mitwirkende, ODbL) '
              'über Nominatim.\n'
              'Fahrten, Punkte und Statistik entstehen ausschließlich aus '
              'euren eigenen Einträgen.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
