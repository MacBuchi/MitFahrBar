/// notes_screen.dart – Anmerkungen zu einem Plantag (Issue #127, deckt #120
/// mit ab).
///
/// „Komme erst um 9." Das ist der ganze Zweck — und **kein Chat**:
/// KONZEPT.md §1 („Kommunikation bleibt in WhatsApp") gilt weiter, es gibt
/// keine Threads, keine Antworten, keinen Gelesen-Status. Zugestellt wird
/// über den bestehenden Versand-Job, der träge ist (Issue #115); wer etwas
/// JETZT sagen muss, greift zum Telefon. Der Hilfe-Screen sagt das auch.
///
/// **Der Verfasser ist ein Feld, keine Sperre.** Gibt es eine Geräte-Person
/// (#121), ist sie vorbelegt; gibt es keine, wählt man sie hier. Eine
/// Schreibsperre an [myPersonProvider] wäre gleich doppelt falsch gewesen:
/// Sie hielte die Geräte-Zuordnung für eine Zugriffskontrolle (die sie
/// ausdrücklich nicht ist), und sie stellte den Schirm im Demo-Modus tot —
/// dort ist `identityEnabledProvider` aus, also gibt es dort **nie** eine
/// Geräte-Person.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/push_digest.dart';
import '../../core/tokens.dart';
import '../../data/providers.dart';
import '../../models/person.dart';
import '../../models/plan_note.dart';

class NotesScreen extends ConsumerWidget {
  const NotesScreen({required this.date, super.key});

  /// `null`, wenn die Adresse ein unbrauchbares Datum trug — auf Web ist
  /// `/notes/:date` eine echte, tippbare Adresse.
  final DateTime? date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = date;
    if (day == null) {
      // Hierher kommt man nur über eine von Hand getippte oder verunglückte
      // Adresse — also gerade ohne Zurück-Eintrag. Der Weg heraus muss
      // deshalb im Schirm selbst stehen.
      return Scaffold(
        appBar: AppBar(title: const Text('Anmerkungen')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Dieser Tag ist nicht lesbar.'),
              const SizedBox(height: AppSpacing.m),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Zur Übersicht'),
              ),
            ],
          ),
        ),
      );
    }

    final notes = ref.watch(dayNotesProvider(day));
    final persons = ref.watch(personsProvider).value ?? const <Person>[];
    final byId = {for (final person in persons) person.id: person};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anmerkungen'),
        // Vom Schirm muss ein Weg wegführen — auch wenn niemand ihn
        // aufgestapelt hat. `/notes/:date` ist auf Web eine echte Adresse:
        // Wer sie geteilt bekommt oder die Seite neu lädt, hat keinen
        // Zurück-Eintrag, und der automatische Knopf bleibt weg. Ohne diese
        // Zeile säße man fest (gefunden im Browser, nicht im Test —
        // dieselbe Klasse wie der tote Update-Knopf aus 0.37.0).
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'Zur Übersicht',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => context.go('/'),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.m,
              bottom: AppSpacing.s,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                dayLabel(day, ref.watch(nowProvider)()),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (notes) {
              AsyncData(:final value) when value.isEmpty => const _Empty(),
              AsyncData(:final value) => ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                itemCount: value.length,
                itemBuilder: (context, i) =>
                    _NoteTile(note: value[i], author: byId[value[i].personId]),
              ),
              AsyncError() => const Center(
                child: Text('Anmerkungen konnten nicht geladen werden.'),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          _Composer(date: day),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Derselbe Akzent, den der Zähler am Banner trägt — damit sichtbar
          // zusammengehört, was zusammengehört.
          Icon(
            Icons.chat_bubble_outline,
            size: 32,
            color: AppAccents.notes(Theme.of(context).brightness),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Noch keine Anmerkung.\nZum Beispiel: „Komme erst um 9."',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _NoteTile extends ConsumerWidget {
  const _NoteTile({required this.note, required this.author});

  final PlanNote note;
  final Person? author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Löschen darf jeder — wie im Planer jeder für jeden einträgt. Das ist
    // Vertipper-Schutz, keine Zugriffskontrolle: Eine Gruppe teilt sich einen
    // Login, und die Geräte-Zuordnung ist kein Nachweis.
    Future<void> remove() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(carpoolRepositoryProvider).deleteNote(note.id);
        ref.invalidate(dayNotesProvider(note.date));
        ref.invalidate(weekNotesProvider);
      } catch (_) {
        // Bewusst ohne den Fehlertext: Er könnte die Anmerkung enthalten,
        // und Fehlermeldungen landen schnell im Log — dieselbe Regel wie
        // beim Einladungstext.
        messenger.showSnackBar(
          const SnackBar(content: Text('Löschen fehlgeschlagen.')),
        );
      }
    }

    return ListTile(
      title: Text(note.body),
      subtitle: Text(
        '${author?.name ?? 'Jemand'} · ${_time(note.createdAt)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: IconButton(
        tooltip: 'Anmerkung löschen',
        icon: const Icon(Icons.close, size: 20),
        onPressed: remove,
      ),
    );
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.date});

  final DateTime date;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Von Hand gewählter Verfasser. `null` heißt „nimm die Geräte-Person" —
  /// steht auch dort niemand, muss erst gewählt werden.
  String? _authorId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(String authorId) async {
    final body = _controller.text.trim();
    // Spiegelt den Check der Datenbank (`char_length(btrim(body)) between 1
    // and 500`). Ohne die Spiegelung sähe die Nutzerin einen rohen
    // Postgres-Fehler.
    if (body.isEmpty) {
      setState(() => _error = 'Bitte schreib etwas.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref
          .read(carpoolRepositoryProvider)
          .addNote(widget.date, authorId, body);
      ref.invalidate(dayNotesProvider(widget.date));
      ref.invalidate(weekNotesProvider);
      if (!mounted) return;
      _controller.clear();
    } catch (_) {
      // Ohne Fehlertext, siehe _NoteTile.
      if (!mounted) return;
      setState(() => _error = 'Senden fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final persons = ref.watch(personsProvider).value ?? const <Person>[];
    final active = [
      for (final person in persons)
        if (person.active) person,
    ];
    // Die Geräte-Zuordnung belegt vor — mehr nicht. Wer sie nicht gesetzt hat
    // (Browser, Demo-Modus, „Später" getippt), wählt hier.
    final me = ref.watch(myPersonProvider);
    final authorId = _authorId ?? me?.id;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButton<String>(
                      value: active.any((p) => p.id == authorId)
                          ? authorId
                          : null,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      hint: const Text('Wer schreibt?'),
                      items: [
                        for (final person in active)
                          DropdownMenuItem(
                            value: person.id,
                            child: Text(person.name),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _authorId = value),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy,
                      maxLength: 500,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Anmerkung für diesen Tag',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  IconButton.filled(
                    tooltip: 'Anmerkung senden',
                    onPressed: _busy || authorId == null
                        ? null
                        : () => _send(authorId),
                    // Nur die Farben des bereiten Zustands: `styleFrom` löst
                    // ohne `disabledBackgroundColor` im gesperrten Zustand
                    // auf `null` auf und fällt damit auf den gedämpften
                    // Standard des Themes zurück — nachgemessen im Browser
                    // (#707578 dunkel, #AEB3B6 hell).
                    style: IconButton.styleFrom(
                      backgroundColor: AppAccents.notes(
                        Theme.of(context).brightness,
                      ),
                      foregroundColor: AppAccents.notesInk(
                        Theme.of(context).brightness,
                      ),
                    ),
                    icon: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
