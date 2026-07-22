/// dashboard_screen.dart – „Wer ist dran" + Mini-Statistik.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/balance_label.dart';
import '../../core/drive_mood.dart';
import '../../core/fairness.dart';
import '../../core/supabase_config.dart';
import '../../core/tokens.dart';
import '../../core/update_check.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../core/widgets/mood_face.dart';
import '../../core/widgets/ride_buddy_mark.dart';
import '../banners/app_banners.dart';
import '../export/export_action.dart';
import '../invite/invite_dialog.dart';
import 'dashboard_charts.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ranking = ref.watch(activeRankingProvider);
    final persons = ref.watch(personsProvider);
    final group = ref.watch(myGroupProvider).value;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.m),
          child: Center(child: RideBuddyMark(size: 34)),
        ),
        leadingWidth: 34 + AppSpacing.m * 2,
        title: Text(group?.name ?? 'RideBuddy'),
        actions: [
          if (group?.isAdmin ?? false)
            IconButton(
              tooltip: 'Gruppen-Freigaben',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/admin'),
            ),
          // Der Lizenz-Eintrag hängt bewusst NICHT an `isConfigured`: Die
          // SIL OFL der Schriften gilt auch im Demo-Modus.
          PopupMenuButton<String>(
            tooltip: 'Zugang',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) {
              if (value == 'persons') {
                context.push('/persons');
              } else if (value == 'invite') {
                final g = group;
                if (g != null) unawaited(showInviteDialog(context, g));
              } else if (value == 'export') {
                // Wie beim Bearbeiten in der Historie bewusst nicht
                // abgewartet: Der Export meldet sich selbst per SnackBar,
                // und ein await hielte das Menü bis dahin offen.
                unawaited(exportTripsCsv(context, ref));
              } else if (value == 'import') {
                unawaited(context.push('/import'));
              } else if (value == 'feedback') {
                showFeedbackDialog(context);
              } else if (value == 'help') {
                unawaited(context.push('/help'));
              } else if (value == 'licenses') {
                showLicensePage(
                  context: context,
                  applicationName: 'RideBuddy',
                  applicationVersion: ref.read(currentVersionProvider).value,
                  applicationLegalese: '© 2026 Marcus Bucher · MIT-Lizenz',
                );
              } else if (value == 'logout') {
                ref.read(authRepositoryProvider).signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'persons',
                child: ListTile(
                  leading: Icon(Icons.group_outlined),
                  title: Text('Personen verwalten'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Einladen gibt es nur mit echtem Backend: Im Demo-Modus gibt
              // es keinen Zugang, den man weitergeben könnte.
              if (SupabaseConfig.isConfigured && group != null)
                const PopupMenuItem(
                  value: 'invite',
                  child: ListTile(
                    leading: Icon(Icons.person_add_alt),
                    title: Text('Jemanden einladen'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              // Nicht an `isConfigured` gehängt: Im Demo-Modus zeigt der
              // Export, wie die Import-Vorlage aussieht.
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Fahrten exportieren (CSV)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_outlined),
                  title: Text('Fahrten importieren (CSV)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // „Passwort ändern" gibt es hier bewusst nicht mehr: Das
              // Gruppenpasswort setzt seit Issue #55 nur noch das
              // Verwalter-Konto (Konsole) neu. So sperrt kein Mitglied
              // versehentlich alle aus — und wenn doch etwas schiefgeht,
              // holt der Verwalter den Zugang selbst zurück.
              if (SupabaseConfig.isConfigured)
                const PopupMenuItem(
                  value: 'feedback',
                  child: ListTile(
                    leading: Icon(Icons.lightbulb_outline),
                    title: Text('Wunsch oder Fehler melden'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'help',
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('So funktioniert RideBuddy'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'licenses',
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('Open-Source-Lizenzen'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (SupabaseConfig.isConfigured)
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Abmelden'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/trip/new'),
        icon: const Icon(Icons.add),
        label: const Text('Fahrt eintragen'),
      ),
      body: switch ((ranking, persons)) {
        (AsyncData(value: final ranked), AsyncData(value: final personList))
            when ranked.isNotEmpty =>
          _Content(ranked: ranked, persons: personList),
        (AsyncData(), AsyncData()) => const Center(
          child: Text('Noch keine Personen angelegt.'),
        ),
        (AsyncError(:final error), _) => Center(
          child: Text('Fehler beim Laden: $error'),
        ),
        (_, AsyncError(:final error)) => Center(
          child: Text('Fehler beim Laden: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.ranked, required this.persons});

  final List<RankedCandidate> ranked;
  final List<Person> persons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final p in persons) p.id: p};
    final points = NumberFormat('#,##0.#', 'de');
    final percent = NumberFormat.percentPattern('de');
    final extremes = findQuoteExtremes(
      [for (final c in ranked) c.personId],
      {for (final c in ranked) c.personId: c.stats},
    );
    // Bezugsgröße der Gesichter: die Spannweite genau dieser Liste, nicht
    // feste Prozentwerte (siehe core/drive_mood.dart).
    final shareRange = DriveShareRange.of([
      for (final c in ranked) c.stats.driveShare,
    ]);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        const AppBanners(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.m,
            AppSpacing.m,
            AppSpacing.m,
            AppSpacing.xs,
          ),
          child: Text(
            'Wer ist dran?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final (index, candidate) in ranked.indexed)
                ListTile(
                  leading: _RankBadge(rank: index + 1),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          byId[candidate.personId]?.name ?? candidate.personId,
                          style: index == 0
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _DriveMoodFace(
                        share: candidate.stats.driveShare,
                        range: shareRange,
                      ),
                      if (candidate.personId == extremes.fullestId)
                        const _QuoteBadge(label: 'Volle Kischt'),
                      if (candidate.personId == extremes.emptiestId)
                        const _QuoteBadge(label: 'Fast alloi'),
                    ],
                  ),
                  subtitle: Text(
                    '${balanceLabel(candidate.stats.points, points)}'
                    ' · fährt ${percent.format(candidate.stats.driveShare)}',
                  ),
                  trailing: index == 0
                      ? const Icon(
                          Icons.directions_car,
                          color: AppColors.driver,
                        )
                      : null,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        GroupAchievementsCard(persons: persons),
        const MonthlyTripsCard(),
        ParticipationMixCard(persons: persons),
      ],
    );
  }
}

/// Das Gesicht zur Zeile. Die Enden der Skala gehören der Quote (wer nimmt
/// die meisten mit, wer fährt fast allein) und sagen damit dasselbe wie die
/// Titel daneben; dazwischen zeigt es den Fahranteil, der als Prozentwert
/// zusätzlich in der Zeile steht.
class _DriveMoodFace extends StatelessWidget {
  const _DriveMoodFace({required this.share, required this.range});

  final double share;
  final DriveShareRange range;

  @override
  Widget build(BuildContext context) {
    final mood = driveMoodOf(share, range);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s),
      child: MoodFace(
        mood: mood,
        size: 22,
        semanticLabel: driveMoodLabel(mood, share),
      ),
    );
  }
}

class _QuoteBadge extends StatelessWidget {
  const _QuoteBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs / 2,
        ),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.s),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = rank <= 2;
    return CircleAvatar(
      radius: 16,
      backgroundColor: highlighted
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      foregroundColor: highlighted ? scheme.onPrimary : scheme.onSurfaceVariant,
      child: Text('$rank'),
    );
  }
}
