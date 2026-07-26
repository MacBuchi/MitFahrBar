/// update_required_screen.dart – Schirm für einen zu alten Client.
///
/// Gegenstück zum wegklickbaren Update-Banner: Hier gibt es nichts
/// wegzuklicken, weil die App gegen diese Datenbank nicht mehr richtig
/// arbeiten kann (Issue #19).
///
/// Ob überhaupt gesperrt wird, entscheidet `updateRequiredProvider` in
/// `data/providers.dart` — dort stehen die drei Sicherungen, die verhindern,
/// dass dieser Schirm jemanden dauerhaft aussperrt. Die vierte steht hier:
/// **Von diesem Schirm muss ein Weg wegführen, der nichts voraussetzt.**
/// Deshalb gibt es zwei Knöpfe. Der obere öffnet den gewohnten Dialog (ein
/// Ablauf für Banner und Sperre, zwei wären zwei Fehlerquellen); der untere
/// geht direkt in den Browser — ohne Dialog, ohne Navigator, ohne Overlay.
///
/// Der Grund ist ein realer Ausfall (26.07.2026, Pixel 7): Der Schirm ersetzt
/// im `builder` der MaterialApp den Router-Navigator, es gab also keinen —
/// `showDialog` warf, Flutter schluckte es, der Knopf tat nichts, und es half
/// nur Deinstallieren und Neuinstallieren von Hand. Die Ursache ist in
/// `app.dart` behoben; dieser zweite Weg ist die Zusage, dass ein Fehler
/// derselben Art nicht wieder alles blockiert.
library;

import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../core/update_check.dart';
import 'app_banners.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  /// Kein Browser hat reagiert. Dann bleibt nur die Adresse zum Abtippen —
  /// eine SnackBar käme hier nicht in Frage, die bräuchte wieder einen
  /// ScaffoldMessenger über dem Schirm.
  bool _browserFailed = false;

  Future<void> _openInBrowser() async {
    final launched = await openUpdateInBrowser(widget.info);
    if (!launched && mounted) setState(() => _browserFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
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
                  if (updateIsDownload) ...[
                    const SizedBox(height: AppSpacing.s),
                    TextButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('Stattdessen im Browser laden'),
                    ),
                  ],
                  if (_browserFailed) ...[
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Es hat sich kein Browser gemeldet. Die neue Version '
                      'liegt hier:',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(
                      info.apkUrl ?? info.releaseUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
