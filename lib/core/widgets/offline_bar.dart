/// offline_bar.dart – „Offline · Stand heute 07:12" über dem Inhalt (#169).
///
/// Der Zeitpunkt ist der eigentliche Inhalt dieser Leiste, nicht das Wort
/// „Offline". Ohne ihn hielte man einen alten Plan für den aktuellen und
/// führe am Ende zur falschen Zeit los; mit ihm kann jede selbst entscheiden,
/// ob der Stand für ihre Frage reicht.
///
/// Sie hört an [OfflineStatus] und nicht an einem Provider: Die Meldung
/// entsteht, **während** ein Provider lädt — ein Provider-Schreib in diesem
/// Moment stieße eine Invalidierung mitten in der Build-Phase an.
///
/// **Sie erscheint mit kurzem Verzug** ([graceWindow], seit v0.79.0). Seit
/// die App aus dem Zwischenspeicher heraus öffnet (#232), beginnt **jeder**
/// Start im Zustand „aus dem Speicher" — auch der mit bestem Empfang, für die
/// zwei Zehntelsekunden, bis der Server antwortet. Ohne den Verzug zuckte die
/// Leiste bei jedem Öffnen kurz auf und wäre genau dann nicht mehr ernst zu
/// nehmen, wenn sie stimmt.
///
/// Der Verzug wartet **nicht** auf das Scheitern der Anfrage: Im Funkloch
/// gibt die erst nach zehn bis sechzig Sekunden auf, und so lange darf
/// niemand einen alten Plan für den aktuellen halten. Zwei Sekunden sind der
/// Handel zwischen beidem.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/caching_repository.dart';
import '../../data/providers.dart';
import '../tokens.dart';

class OfflineBar extends ConsumerStatefulWidget {
  const OfflineBar({super.key});

  @override
  ConsumerState<OfflineBar> createState() => _OfflineBarState();
}

/// Wie lange „aus dem Speicher" anhalten muss, bevor die Leiste es sagt.
const graceWindow = Duration(seconds: 2);

class _OfflineBarState extends ConsumerState<OfflineBar> {
  OfflineStatus? _status;

  /// Der Zeitpunkt, den die Leiste **zeigt** — `null` heißt: keine Leiste.
  /// Bewusst getrennt vom gemeldeten Zustand, denn zwischen beiden liegt
  /// [graceWindow].
  DateTime? _shown;
  Timer? _grace;

  void _onChanged() {
    if (!mounted) return;
    final reported = _status?.notifier.value;
    if (reported == null) {
      // Frisch vom Server: Die Leiste geht sofort weg, auch wenn sie noch
      // gar nicht da war.
      _grace?.cancel();
      _grace = null;
      if (_shown != null) setState(() => _shown = null);
      return;
    }
    // Steht sie schon, folgt sie dem gemeldeten Zeitpunkt ohne Verzug —
    // gewartet wird nur auf das erste Erscheinen.
    if (_shown != null) {
      setState(() => _shown = reported);
      return;
    }
    _grace ??= Timer(graceWindow, () {
      _grace = null;
      final still = _status?.notifier.value;
      if (still != null && mounted) setState(() => _shown = still);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final status = ref.read(offlineStatusProvider);
    if (identical(status, _status)) return;
    _status?.notifier.removeListener(_onChanged);
    _status = status..notifier.addListener(_onChanged);
    // Der Zustand kann schon vor dem ersten Aufbau gemeldet worden sein —
    // die Lesezugriffe laufen, bevor irgendein Schirm steht.
    _onChanged();
  }

  @override
  void dispose() {
    _grace?.cancel();
    _status?.notifier.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storedAt = _shown;
    if (storedAt == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  'Offline · Stand ${describeStamp(storedAt, ref.read(nowProvider)())}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „heute 07:12", „gestern 18:40", sonst „04.08. 18:40".
///
/// Bewusst ohne „vor 3 Stunden": Eine Spanne muss man erst in eine Uhrzeit
/// zurückrechnen, um zu wissen, ob der Stand vor oder nach der Abfahrt lag —
/// und genau das ist die Frage, die hier zählt. Das Datum kommt ab
/// vorgestern dazu, sonst liest sich ein zwei Tage alter Stand wie ein
/// heutiger.
String describeStamp(DateTime storedAt, DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(storedAt.hour)}:${two(storedAt.minute)}';
  final day = DateTime(storedAt.year, storedAt.month, storedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'heute $clock';
  if (days == 1) return 'gestern $clock';
  return '${two(storedAt.day)}.${two(storedAt.month)}. $clock';
}
