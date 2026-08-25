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
import '../../core/widgets/mitfahrbar_mark.dart';
import '../about/about_dialog.dart';
import '../banners/app_banners.dart';
import '../export/export_action.dart';
import '../identity/identity_dialog.dart';
import '../invite/invite_dialog.dart';
import 'dashboard_charts.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Die Startabfrage kommt einmal je App-Lauf, nie zweimal übereinander.
  bool _asking = false;

  /// Fragt beim ersten Start, wer hier sitzt (#121).
  ///
  /// Bewusst **hier** und nicht im `builder` der MaterialApp: Dort liegen
  /// Splash und Sperr-Schirm, und ein `showDialog` ohne eigenen Navigator ist
  /// genau der Fehler, der 0.37.0 den toten Update-Knopf beschert hat. Die
  /// Übersicht liegt im Router-Navigator und existiert erst nach dem Login mit
  /// geladenen Personen — also genau dann, wenn die Frage beantwortbar ist.
  void _maybeAsk(List<Person> persons) {
    if (_asking) return;
    if (persons.every((p) => !p.active)) return;
    final identity = ref.read(deviceIdentityProvider).value;
    if (identity == null || identity.asked) return;

    _asking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(showIdentityDialog(context, atStart: true));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ranking = ref.watch(activeRankingProvider);
    final persons = ref.watch(personsProvider);
    final group = ref.watch(myGroupProvider).value;
    final me = ref.watch(myPersonProvider);
    // Ist die Zuordnung abgeschaltet (Tests), verhält sich das Menü exakt wie
    // vorher: kein eigener Eintrag, und „Benachrichtigungen" bleibt offen.
    // Sonst hinge an einem ausgeschalteten Feature trotzdem eine Sperre.
    final identityOn = ref.watch(identityEnabledProvider);
    final hasIdentity = !identityOn || me != null;

    if (persons.value case final list?) _maybeAsk(list);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: AppSpacing.m),
          child: Center(child: MitFahrBarMark(size: 34)),
        ),
        leadingWidth: 34 + AppSpacing.m * 2,
        title: Text(group?.name ?? 'MitFahrBar'),
        actions: [
          // Der Lizenz-Eintrag hängt bewusst NICHT an `isConfigured`: Die
          // SIL OFL der Schriften gilt auch im Demo-Modus.
          PopupMenuButton<String>(
            tooltip: 'Zugang',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) {
              if (value == 'identity') {
                unawaited(showIdentityDialog(context));
              } else if (value == 'persons') {
                context.push('/persons');
              } else if (value == 'settings') {
                unawaited(context.push('/settings'));
              } else if (value == 'notifications') {
                unawaited(context.push('/notifications'));
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
              } else if (value == 'about') {
                showAboutMitFahrBarDialog(context);
              } else if (value == 'licenses') {
                showLicensePage(
                  context: context,
                  applicationName: 'MitFahrBar',
                  applicationVersion: ref.read(currentVersionProvider).value,
                  applicationLegalese: '© 2026 Marcus Bucher · MIT-Lizenz',
                );
              } else if (value == 'logout') {
                ref.read(authRepositoryProvider).signOut();
              }
            },
            itemBuilder: (context) => [
              // Ganz oben: Wer hier sitzt, entscheidet, was die übrigen
              // Einträge können. Der Stand steht rechts statt als Untertitel —
              // dieses Menü ist lang, und eine zweite Zeile schiebt die
              // unteren Einträge vom Bildschirm.
              if (identityOn)
                PopupMenuItem(
                  value: 'identity',
                  child: ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Ich bin'),
                    trailing: Text(me?.name ?? 'niemand'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'persons',
                child: ListTile(
                  leading: Icon(Icons.group_outlined),
                  title: Text('Personen verwalten'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.tune),
                  title: Text('Parameter'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Wie „Einladen" an ein echtes Backend gehängt: Ohne Zugang
              // gibt es kein Gerät, dem man etwas zustellen könnte.
              //
              // Ohne gewählte Person ausgegraut statt versteckt — versteckt
              // bliebe unerklärt, warum der Punkt fehlt. Umgekehrt bleibt er
              // dort ganz weg, wo die Plattform gar kein Push kann (iOS): Ein
              // dauerhaft toter Eintrag wäre schlechter als keiner.
              // `PopupMenuItem.enabled` sperrt, `ListTile.enabled` graut —
              // es braucht beide.
              if (SupabaseConfig.isConfigured)
                PopupMenuItem(
                  value: 'notifications',
                  enabled: hasIdentity,
                  child: ListTile(
                    enabled: hasIdentity,
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text('Benachrichtigungen'),
                    subtitle: hasIdentity
                        ? null
                        : const Text('Erst festlegen, wer du bist'),
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
                  title: Text('So funktioniert MitFahrBar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Über MitFahrBar'),
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
    // feste Prozentwerte (siehe core/drive_mood.dart). Gezeigt wird der um
    // den Punktestand ausgeglichene Anteil (Issue #270) — Spannweite,
    // Gesicht und Prozentzahl daneben müssen aus derselben Quelle kommen,
    // sonst zeigt das Gesicht auf eine andere Zahl als die Zeile.
    final shareRange = DriveShareRange.of([
      for (final c in ranked) c.stats.settledDriveShare,
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
                        share: candidate.stats.settledDriveShare,
                        range: shareRange,
                      ),
                      if (candidate.personId == extremes.fullestId)
                        const _QuoteBadge(label: 'Volle Kischd'),
                      if (candidate.personId == extremes.emptiestId)
                        const _QuoteBadge(label: 'Faschd alloi'),
                    ],
                  ),
                  subtitle: Text(
                    '${balanceLabel(candidate.stats.points, points)}'
                    ' · fährt ${percent.format(candidate.stats.settledDriveShare)}',
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
        SavingsCard(persons: persons),
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
