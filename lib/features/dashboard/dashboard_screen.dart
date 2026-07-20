/// dashboard_screen.dart – „Wer ist dran" + Mini-Statistik.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/fairness.dart';
import '../../core/supabase_config.dart';
import '../../core/tokens.dart';
import '../../core/update_check.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../core/widgets/ride_buddy_mark.dart';
import '../account/change_password_dialog.dart';
import '../banners/app_banners.dart';
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
              } else if (value == 'password') {
                showChangePasswordDialog(context);
              } else if (value == 'feedback') {
                showFeedbackDialog(context);
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
              if (SupabaseConfig.isConfigured) ...const [
                PopupMenuItem(
                  value: 'password',
                  child: ListTile(
                    leading: Icon(Icons.key_outlined),
                    title: Text('Passwort ändern'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'feedback',
                  child: ListTile(
                    leading: Icon(Icons.lightbulb_outline),
                    title: Text('Wunsch oder Fehler melden'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
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
                  title: Text(
                    byId[candidate.personId]?.name ?? candidate.personId,
                    style: index == 0
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  subtitle: Text(
                    '${points.format(candidate.stats.points)} Punkte · '
                    'Fahranteil ${percent.format(candidate.stats.driveShare)}',
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
