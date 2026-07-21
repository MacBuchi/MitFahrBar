/// update_required_screen.dart – Schirm für einen zu alten Client.
///
/// Gegenstück zum wegklickbaren Update-Banner: Hier gibt es nichts
/// wegzuklicken, weil die App gegen diese Datenbank nicht mehr richtig
/// arbeiten kann (Issue #19).
///
/// Ob überhaupt gesperrt wird, entscheidet `updateRequiredProvider` in
/// `data/providers.dart` — dort stehen auch die Sicherungen, die verhindern,
/// dass dieser Schirm jemanden dauerhaft aussperrt.
library;

import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../core/update_check.dart';
import 'app_banners.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            // Ohne Begrenzung läuft der Absatz im Browser über die volle
            // Fensterbreite und wird unlesbar.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    'Update erforderlich',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Diese App-Version ist zu alt für die aktuellen Daten. '
                    'Sie würde euch Fahrten und Punkte unvollständig anzeigen — '
                    'deshalb geht es erst nach dem Update weiter.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    'Version ${info.latestVersion} steht bereit.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  // Bewusst derselbe Ablauf wie im Banner: APK laden auf
                  // Android, neu laden im Web. Zwei Update-Wege wären zwei
                  // Fehlerquellen.
                  FilledButton.icon(
                    onPressed: () => showUpdateDialog(context, info),
                    icon: Icon(
                      updateIsDownload ? Icons.download : Icons.refresh,
                    ),
                    label: Text(
                      updateIsDownload ? 'Update installieren' : 'Neu laden',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
