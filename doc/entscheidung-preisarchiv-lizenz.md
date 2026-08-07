# Designentscheidung: Wie die CC-BY-NC-SA-Lizenz des Preisarchivs eingehalten wird

**Status:** festgehalten am 2026-08-07 · **Kontext:** Issue #190 (aus
pilzbuddy #223 portiert) · **Beleg:** `test/price_archive_license_test.dart`

## Die Frage

Die Spritpreise kommen aus **zwei** Quellen mit **zwei verschiedenen**
Lizenzen (v0.53.0):

| Quelle | Was | Lizenz |
| --- | --- | --- |
| Tankerkönig-Spritpreis-**API** | laufende Wochen | CC BY 4.0 |
| Tankerkönig-**Preisarchiv** | zurückliegende Wochen (`tool/import_fuel_history.py`) | **CC BY-NC-SA 4.0** |

CLAUDE.md und README nennen die Einhaltung bisher in einem Satz:
„Nicht-kommerziell passt, SA greift nicht (die Wochenwerte bleiben in der
Gruppendatenbank), BY steht in README und ‚Über MitFahrBar'."

Das ist richtig — aber es ist eine **Behauptung über den Code**, und der
Code kann sich ändern, ohne dass jemand an diesen Satz denkt. Genau diese
Klasse von Zusage („gilt, solange niemand X ergänzt") hat das Projekt
anderswo schon einmal von der Absichtserklärung zum erzwungenen Riegel
befördert: `push_outbox` hat **null Policies** und `revoke all`, damit die
Ausnahme „der vorgeschlagene Fahrer steht im Klartext" nicht bloß
versprochen ist.

Dieses Dokument benennt, worauf jede der drei Lizenzbedingungen ruht, und
welcher Teil davon prüfbar ist.

## Die Entscheidung

### BY — Namensnennung

Steht an zwei Stellen und **nennt beide Lizenzen getrennt**:

- `README.md` (Abschnitt „Daten & Lizenzen")
- `lib/features/about/about_dialog.dart` — „Woher die Daten kommen"

Der Dialog ist die wichtigere der beiden: Er ist die Stelle, an der jemand
*in der App* nach Herkunft sucht. Die Nennung steht bewusst **nicht** nur
auf dem Preis-Screen — wer den nie öffnet, hätte sie sonst nie gesehen.

**Nicht zusammenziehen.** „Tankerkönig, CC BY 4.0" für beides wäre
schlicht falsch: Für die zurückliegenden Wochen gilt eine andere, engere
Lizenz, und ein Leser, der auf die genannte aufbaut, baut auf die falsche.

### NC — nicht-kommerziell

MitFahrBar ist eine Fahrgemeinschafts-App für eine private Gruppe: keine
Werbung, kein Verkauf, kein bezahlter Zugang, keine Weiterverwertung der
Daten. Das ist eine Eigenschaft des Projekts, nicht des Codes — kein Test
kann sie prüfen. **Sie ist deshalb die Bedingung, die als Erstes bricht,
wenn sich am Projekt etwas Grundsätzliches ändert**, und der Grund, warum
diese Datei existiert statt nur eines Tests.

### SA — Weitergabe unter gleichen Bedingungen

**Das ist die Bedingung, die der Code trägt.** ShareAlike greift bei
*Weitergabe* (Distribution). Solange die aus dem Archiv abgeleiteten
Wochenwerte die Gruppendatenbank nicht verlassen, gibt es keine Weitergabe
— und damit auch keine Pflicht, das `LICENSE` des Projekts (MIT) für sie
aufzugeben.

Worauf das ruht, in `supabase/schema.sql`:

1. **Die Rohschicht `price_sample` ist für Clients gar nicht erreichbar.**
   `revoke all … from anon, authenticated`, kein Grant zurück, keine
   Policy. Sie ist der Teil, der dem Archiv am nächsten liegt.
2. **`price_week` darf nur die eigene Gruppe lesen, und nur lesen.**
   `revoke all`, dann ausschließlich `grant select … to authenticated` —
   `anon` bekommt nichts zurück. Die einzige Policy ist ein
   `for select` mit `group_id = auth.uid() and my_group_active()`.
3. **Die Reihenfolge dieser Zeilen ist tragend.** Über den Tabellen steht
   ein Sammel-Grant (`grant select, insert, update, delete on all tables
   in schema public to anon, authenticated`). Die Rücknahmen wirken nur,
   weil sie **danach** kommen. Rutschte eine davon nach oben, wäre sie
   wirkungslos — und zwar lautlos: Das Schema läuft durch, die Policy
   bleibt sichtbar stehen, und `price_sample` wäre für jeden angemeldeten
   Client offen. Dieselbe Falle wie die Reihenfolge in der #108-Migration.
4. **Es gibt keinen Ausleitungsweg in der App.** Der CSV-Export
   (`lib/core/csv_export.dart`) ist die einzige Funktion, die Daten aus
   der App herausschreibt, und er kennt Fahrten und Personen — keine
   Preise.

Punkt 1–4 prüft `test/price_archive_license_test.dart`. Punkt 3 wird als
**Positionsvergleich** geprüft, nicht als Vorkommen; ein Test, der nur
`contains('revoke all on public.price_week …')` fragt, bliebe grün,
nachdem die Zeile nach oben gewandert ist.

## Was ausdrücklich NICHT geprüft wird

- **NC** — siehe oben, keine Eigenschaft des Codes.
- **Die Live-API (CC BY 4.0).** Sie ist die schwächere Lizenz; was für das
  Archiv reicht, reicht für sie erst recht. Der Test zielt bewusst auf die
  engere.
- **Ob der Archivzugang benutzt wird.** `tool/import_fuel_history.py` ist
  manuell (`workflow_dispatch`) und ruht ohne Secrets. Ob er lief, ändert
  an den Pflichten nichts: Sobald *eine* importierte Woche in `price_week`
  steht, gilt die Lizenz für den Bestand.

## Nebenbemerkung zum Archivzugang

Der Zugang ist **persönlich**, und sein Passwort ist derselbe Wert wie der
API-Schlüssel — ein Leck öffnet beides. Das ist keine Lizenzfrage, steht
hier aber, weil es beim Lesen dieses Dokuments zusammengehört:
`TANKERKOENIG_ARCHIVE_USER` / `TANKERKOENIG_ARCHIVE_PASSWORD` liegen als
Repo-Secrets, nie im Code.
