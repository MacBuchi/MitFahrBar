/// admin_screen.dart – Freigabe neuer Gruppen (nur für Admin-Gruppen).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/group.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gruppen-Freigaben'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(pendingGroupsProvider),
          ),
        ],
      ),
      body: switch (pending) {
        AsyncData(value: final groups) when groups.isEmpty => const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.l),
              child: Text('Keine offenen Anfragen.'),
            ),
          ),
        AsyncData(value: final groups) => ListView(
            children: [
              for (final group in groups)
                _RequestTile(group: group),
            ],
          ),
        AsyncError(:final error) =>
          Center(child: Text('Fehler beim Laden: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.group});

  final Group group;

  Future<void> _set(WidgetRef ref, GroupStatus status) async {
    await ref.read(groupRepositoryProvider).setStatus(group.id, status);
    ref.invalidate(pendingGroupsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = group.createdAt == null
        ? ''
        : DateFormat('dd.MM.yyyy', 'de').format(group.createdAt!);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name,
                style: Theme.of(context).textTheme.titleMedium),
            Text('Anmeldename: ${group.handle}'
                '${date.isEmpty ? '' : ' · angefragt $date'}'),
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _set(ref, GroupStatus.rejected),
                  child: const Text('Ablehnen'),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  onPressed: () => _set(ref, GroupStatus.active),
                  child: const Text('Freigeben'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
