/// chart_card.dart – Gemeinsamer Rahmen aller Diagramm-Karten.
///
/// Bis zur Statistik-Seite lebte er privat in `dashboard_charts.dart`; jetzt
/// teilen sich Übersicht und Statistik denselben Rahmen — Überschrift,
/// optionale Erläuterung, Inhalt. Zwei Kopien drifteten beim ersten
/// Padding-Feinschliff auseinander.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle case final String text) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.m),
            child,
          ],
        ),
      ),
    );
  }
}
