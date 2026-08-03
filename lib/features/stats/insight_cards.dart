/// insight_cards.dart – „Überraschende Insights" über der Statistik.
///
/// Kleine Verlaufs-Karten, wöchentlich wechselnd (deterministisch über die
/// ISO-Woche, `rotateInsights`) — jede erzählt genau eine Zahl als
/// Geschichte. Die Töne kommen aus `AppInsightTones` und sind gemessen;
/// je Karte EIN Akzent (Regel des Design-Sets).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/providers.dart';

class InsightRow extends ConsumerWidget {
  const InsightRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(statsInsightsProvider);
    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final (index, insight) in insights.indexed)
          _InsightCard(
            title: insight.title,
            value: insight.value,
            tone: AppInsightTones.byIndex(index),
          ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.value,
    required this.tone,
  });

  final String title;
  final String value;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      // Dieselben Ränder wie die Cards der Seite, damit die Kanten fluchten.
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.l,
        vertical: AppSpacing.m + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: tone.gradient,
        color: tone.gradient == null ? tone.surface : null,
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: tone.foreground,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
