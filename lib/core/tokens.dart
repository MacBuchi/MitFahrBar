/// tokens.dart – Zentrale Design-Tokens der Marke MitFahrBar.
///
/// Quelle: Design-Set „MitFahrBar Design Set". Maßgeblich sind die dort
/// gezeigten Farbflächen (Cyan/Teal-Familie); die Bildunterschriften der
/// Palette stammen noch aus einer früheren Lila-Variante und wurden
/// bewusst nicht übernommen.
///
/// In Screens niemals rohe Farb-/Pixelwerte verwenden, immer diese Klassen
/// bzw. das Theme.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  /// Markenfarbe – Basis des ColorScheme und der Verläufe.
  static const brand = Color(0xFF0891B2);

  /// Heller Markenton, Endpunkt des Verlaufs.
  static const brandBright = Color(0xFF22D3EE);

  /// Zwischenton für Flächen und Hover.
  static const brandLight = Color(0xFF06B6D4);

  /// Akzent für Details (Radnaben, Links auf dunklem Grund).
  static const accent = Color(0xFF67E8F9);

  /// „Eco" – CO₂-Ersparnis und Mitfahren.
  static const eco = Color(0xFF10D98E);

  /// Tiefdunkles Marken-Blauschwarz.
  static const ink = Color(0xFF062028);

  /// Sehr helles Cyan als Papierton.
  static const paper = Color(0xFFECFEFF);

  /// Hintergrund und Flächen der dunklen Markenwelt.
  static const darkBackground = Color(0xFF06171C);
  static const darkSurface = Color(0xFF0B2831);

  /// Zurückhaltender Text auf dunklem Grund.
  static const muted = Color(0xFF6F909A);

  /// Markenverlauf („Motion") – für Logo, Icon und Hero-Flächen.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandBright],
  );

  /// Status der Teilnahme an einer Fahrt.
  static const driver = brand;
  static const passenger = Color(0xFF0F9D6B);
  static const oneWay = Color(0xFFB45309);
}

/// Farbe einer Personenlinie — im Ersparnis-Diagramm UND im Ersparnis-Ring;
/// der Index kommt aus `savingsOrder`, damit dieselbe Person überall
/// dieselbe Farbe trägt.
///
/// Erzeugt statt aufgezählt: Wie viele Personen eine Gruppe hat, steht nicht
/// fest — eine feste Liste liefe bei der neunten entweder aus oder
/// wiederholte sich still, und zwei gleichfarbige Linien im selben Diagramm
/// sind schlimmer als eine ungewohnte Farbe. Gedreht wird deshalb der
/// Farbton bei fester Sättigung und Helligkeit: So tragen alle Töne gleich
/// weit gegen den Untergrund, und die Reihe beginnt in der Markenwelt.
///
/// Die Helligkeit hängt am Modus — dieselben Töne trügen auf dem dunklen
/// Untergrund sonst deutlich schlechter als auf dem hellen.
Color personLineColor(int index, int count, Brightness brightness) {
  final base = HSLColor.fromColor(AppColors.brand);
  final step = count <= 1 ? 0.0 : 300.0 / count;
  return HSLColor.fromAHSL(
    1,
    (base.hue + step * index) % 360,
    0.55,
    brightness == Brightness.dark ? 0.68 : 0.42,
  ).toColor();
}

/// Ein Bannerton: Fläche (oder Verlauf) plus alles, was darauf steht.
///
/// Ein Werttyp statt zweier loser Farben, weil Fläche und Vordergrund nur
/// zusammen etwas bedeuten — getrennt übergeben landet früher oder später
/// heller Text auf heller Fläche. `test/banner_contrast_test.dart` misst
/// jedes Paar, das hier entsteht.
class BannerTone {
  const BannerTone({
    required this.surface,
    required this.foreground,
    this.gradient,
  });

  /// Fläche, wenn kein Verlauf gesetzt ist.
  final Color surface;

  /// Text, Icons und der „Ausblenden"-Knopf darauf.
  final Color foreground;

  /// Gesetzt: ersetzt [surface]. [surface] bleibt trotzdem gefüllt — als der
  /// Ton, gegen den der Kontrast im schlechtesten Punkt gemessen wird.
  final Gradient? gradient;
}

/// Farben der Hinweisleisten über der Übersicht (`features/banners/`).
///
/// Quelle ist das Design-Set unter `assets/fahrmitbar-design-set/`, Kapitel
/// 07 („Banner-Farbkombinationen") und 07b („Pep-Akzente"). Das ist bewusst
/// eine **eigene Palette neben** dem `ColorScheme` und kein Ersatz dafür:
/// Kapitel 06 des Design-Sets gibt ein anderes `primary` vor als der Seed,
/// dem zu folgen wäre ein Umbau des ganzen Erscheinungsbilds und keine
/// Bannerfrage. Die Übernahme trägt hier, weil die Untergründe der App
/// ohnehin die des Design-Sets sind (hell 1,01:1, dunkel 1,03:1).
abstract final class AppBannerTones {
  AppBannerTones._();

  /// „Deep Teal Flow" für die Kachel der nächsten Fahrt — das dauerhafte
  /// Banner, und im Design-Set genau mit dieser Überschrift gezeichnet.
  ///
  /// Zwei Abweichungen von der Vorlage, beide gemessen und beide nicht
  /// kosmetisch:
  ///
  /// - **Der helle Endpunkt `#22D3EE` entfällt.** Weiß darauf trägt nur
  ///   1,81:1. Im Design-Set steht der Text auf der dunklen Seite eines
  ///   großen Heros; über einen schmalen Streifen läuft er über die ganze
  ///   Breite. Bei `#0F7F98` gekappt hält Weiß durchgehend ≥4,66:1.
  /// - **Der Verlauf läuft hell → dunkel, nicht andersherum.** Rechts im
  ///   Banner sitzt der Zähler der Anmerkungen. Auf dem hellen Teal ist der
  ///   Magenta-Chip unsichtbar (1,61:1); auf dem dunklen Ende trennt er sich
  ///   mit 4,06:1. Wer die Richtung „zurück aufs Design-Set" dreht, macht
  ///   den Zähler unlesbar — das ist genau der Fall, den das Set mit „nie
  ///   zwei Akzente im selben Banner" benennt.
  ///
  /// In hell und dunkel derselbe Ton: Der Streifen ist in beiden Fällen die
  /// dunkle, farbige Fläche, die alles andere überstrahlt.
  static BannerTone nextRide(Brightness brightness) => const BannerTone(
    surface: Color(0xFF0F7F98),
    foreground: Color(0xFFFFFFFF),
    gradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF0F7F98), Color(0xFF053E49)],
    ),
  );

  /// „Sunset Coral" für den Hinweis auf eine neue Version — der einzige Ton
  /// außerhalb der Teal-Familie, und das ist der Zweck: Der Hinweis kommt
  /// und geht, Herausfallen ist erwünscht. Das Design-Set weist die Farbe
  /// ausdrücklich „Neues Update, Release-News" zu.
  ///
  /// Die **Flächen** `#FFE3D3` und `#3A1608` stehen so **nicht** im
  /// Design-Set — dort gibt es zu den Pep-Akzenten nur das Paar
  /// `#E0561F / #FF8A4C` und Verlaufs-Heros. Sie sind daraus abgeleitet;
  /// wer sie im Set sucht, sucht vergeblich.
  static BannerTone update(Brightness brightness) =>
      brightness == Brightness.dark
      ? const BannerTone(
          surface: Color(0xFF3A1608),
          foreground: Color(0xFFFF8A4C),
        )
      : const BannerTone(
          surface: Color(0xFFFFE3D3),
          foreground: Color(0xFFB8300E),
        );

  /// „Light Air" bzw. „Night Glow" für die ruhigen Banner: die offene
  /// Einrichtung („Niemand ausgewählt") und das Feedback-Angebot.
  ///
  /// Beide tragen bewusst **denselben** Ton — sie tun es heute schon, und
  /// ein eigener Akzent für die Einrichtung hätte im Design-Set keine
  /// Entsprechung (Signal Amber ist dort für Auszeichnungen vergeben).
  static BannerTone quiet(Brightness brightness) =>
      brightness == Brightness.dark
      ? const BannerTone(
          surface: Color(0xFF12414E),
          foreground: Color(0xFF8EDFEF),
        )
      : const BannerTone(
          surface: Color(0xFFC9EAF4),
          foreground: Color(0xFF0B5D71),
        );

  /// Haarlinie um die **flächigen** Banner.
  ///
  /// Sie heben sich nur mit 1,13–1,21:1 vom Untergrund ab — als Fläche
  /// allein sind sie kaum ein Streifen. Der Rahmen kommt aus der eigenen
  /// Vordergrundfarbe: Die neutralen Rahmentöne des Design-Sets (`#DBE4E8`)
  /// liegen auf `#C9EAF4` bei 1,02:1 und wären unsichtbar.
  static Color hairlineOf(BannerTone tone) =>
      tone.foreground.withValues(alpha: 0.24);
}

/// Pep-Akzente aus Kapitel 07b des Design-Sets.
///
/// Die Regel dort lautet „sparsam einsetzen: nie zwei Akzente im selben
/// Banner" — sie ist der Grund, warum der Anmerkungs-Akzent ausschließlich
/// auf dem Zähler sitzt, der seine eigene Fläche mitbringt, und nicht frei
/// auf dem Verlauf des Fahrt-Banners.
abstract final class AppAccents {
  AppAccents._();

  /// „Hot Magenta" — im Design-Set „Chat, neue Nachricht" zugewiesen. Für
  /// die Anmerkungen an einem Plantag (#127), die ausdrücklich **kein**
  /// Chat sind: Die Farbe markiert, dass jemand etwas geschrieben hat,
  /// nicht einen Gesprächsfaden.
  ///
  /// Hell ist gegenüber dem Set (`#E01F6B`) nachgedunkelt: auf weißem Blatt
  /// trägt das Original nur 4,59:1 und fiele unter jeder Tönung durch.
  static Color notes(Brightness brightness) => brightness == Brightness.dark
      ? const Color(0xFFFF5C9E)
      : const Color(0xFFB8155A);

  /// Der Zähler an der Sprechblase. Eigene Fläche, deshalb in hell wie
  /// dunkel gleich — er sitzt in beiden Fällen auf dem dunklen Ende des
  /// Fahrt-Banners.
  static const notesChip = Color(0xFFFF5C9E);
  static const notesChipInk = Color(0xFF3D0018);

  /// Was auf einer mit [notes] gefüllten Fläche steht (Absende-Knopf).
  static Color notesInk(Brightness brightness) =>
      brightness == Brightness.dark ? notesChipInk : const Color(0xFFFFFFFF);
}

/// Die Benachrichtigung, während die App im Vordergrund ist (`app.dart`).
///
/// Bis v0.39.0 zeigte sie niemand an und Meldungen verschwanden spurlos;
/// seitdem ist sie eine SnackBar. Sie trägt das dunkle Ende des
/// Fahrt-Banners — derselbe Ton, in den Android das Icon im
/// Benachrichtigungs-Schatten färbt (`res/values/colors.xml`), damit
/// dieselbe Nachricht drinnen wie draußen gleich aussieht.
abstract final class AppPush {
  AppPush._();

  static const surface = Color(0xFF053E49);
  static const ink = Color(0xFFFFFFFF);
  static const action = Color(0xFF8EDFEF);
}

/// Farben der Statistik-Seite — jedes Paar ist gemessen, nicht geschätzt
/// (`test/stats_contrast_test.dart`; Text 4,5:1, Grafik 3,0:1 gegen die
/// Kartenfläche `surfaceContainerLow` des jeweiligen Themes).
///
/// Bewusst NICHT `AppColors.eco` auf hellen Karten: Das Eco-Grün trägt dort
/// nur 1,85:1 — hell übernimmt der dunklere Mitfahr-Ton `passenger`.
abstract final class AppStatsColors {
  AppStatsColors._();

  /// Text eines positiven Saldos („+5") — Grün, das auf der Karte lesbar ist.
  static Color saldoPositive(Brightness brightness) =>
      brightness == Brightness.dark
      ? AppColors.eco // 9,28:1 auf der dunklen Karte
      : const Color(0xFF047857); // 4,95:1 auf der hellen

  /// Text eines negativen Saldos („−6") — warm, aber kein Alarm-Rot: Ein
  /// Minus ist hier „ist bald dran", kein Fehler.
  static Color saldoNegative(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color(0xFFFF8A4C) // 7,36:1 — der Ton des Update-Banners
      : AppColors.oneWay; // 4,53:1

  /// Der Rekord-Balken im Wochen-Diagramm (Grafik, Markenfamilie).
  static Color record(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.brandBright : AppColors.brand;

  /// Grün als Grafikton: aktuelle Wochen-Balken, CO₂-Ring, Ersparnis-Kurve.
  static Color eco(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.eco : AppColors.passenger;
}

/// Töne der Insight-Karten („Überraschende Insights", `features/stats/`).
///
/// Zwei Verläufe im [BannerTone]-Muster, je Karte EIN Akzent (die Regel des
/// Design-Sets). Wie [AppPush] in hell und dunkel derselbe Ton: Die Karten
/// SIND die Farbfläche, sie liegen nicht auf einer.
///
/// [bright] holt den einst abgelehnten Endpunkt `#22D3EE` legal zurück:
/// Abgelehnt war WEISS darauf (1,81:1) — die dunkle Marken-Tinte trägt
/// 9,33:1. [deep] ist bewusst nicht derselbe Verlauf wie das Fahrt-Banner,
/// sonst läse sich eine Insight-Karte als „nächste Fahrt".
abstract final class AppInsightTones {
  AppInsightTones._();

  static const bright = BannerTone(
    surface: AppColors.brandBright, // der schlechteste Stopp
    foreground: AppColors.ink, // 9,33:1 dort, 11,64:1 am hellen Stopp
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.accent, AppColors.brandBright],
    ),
  );

  static const deep = BannerTone(
    surface: Color(0xFF0E7490), // der schlechteste Stopp: Weiß 5,36:1
    foreground: Color(0xFFFFFFFF),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0E7490), Color(0xFF164E63)],
    ),
  );

  /// Ton nach Karten-Index — deterministisch alternierend, kein Zufall.
  static BannerTone byIndex(int index) => index.isEven ? deep : bright;
}

/// Farben der Stimmungs-Gesichter aus dem Design-Set „MitFahrBar Smiley Set".
///
/// Die Vorlage ist in oklch notiert, was Flutter nicht kennt; die Werte hier
/// sind die nach sRGB umgerechneten Entsprechungen. Deshalb gilt: **nicht von
/// Hand nachjustieren** — bei einer Änderung im Design-Set neu umrechnen,
/// sonst driftet die Skala auseinander.
///
/// Der Farbton wandert über die Skala von Grün nach Rot; `ink` ist jeweils
/// der dunkle Ton für Augen und Mund desselben Gesichts.
abstract final class AppFace {
  AppFace._();

  static const ecstaticFill = Color(0xFF4AC06C);
  static const ecstaticInk = Color(0xFF004C1A);
  static const happyFill = Color(0xFF87B73A);
  static const happyInk = Color(0xFF2C4700);
  static const goodFill = Color(0xFFBBB326);
  static const goodInk = Color(0xFF4A4400);
  static const neutralFill = Color(0xFFE4B33F);
  static const neutralInk = Color(0xFF5E4300);
  static const mehFill = Color(0xFFE88B0E);
  static const mehInk = Color(0xFF693100);
  static const sadFill = Color(0xFFE56731);
  static const sadInk = Color(0xFF671800);
  static const angryFill = Color(0xFFDB4241);
  static const angryInk = Color(0xFF65000A);

  /// Träne des traurigen Gesichts.
  static const tear = Color(0xFF4BAEED);

  /// „Celebrating" steht außerhalb der Skala: kein Bewertungsschritt,
  /// sondern die Auszeichnung eines Erfolgs.
  static const celebrateFill = Color(0xFFF9DD73);
  static const celebrateInk = Color(0xFF643400);
  static const celebrateTongue = Color(0xFFEC5A63);
  static const confettiGold = Color(0xFFEDCC48);
  static const confettiGreen = Color(0xFF55C975);
  static const confettiRed = Color(0xFFF66D67);
  static const confettiViolet = Color(0xFFDCB8FF);
}

/// Maße der Diagramme (gezeichnet in `core/widgets/charts.dart`).
///
/// Die Daten sind das Einzige, was laut sein darf: dünne Marken, haarfeine
/// Achsen, und getrennt wird durch Fläche statt durch Rahmen.
abstract final class AppChart {
  AppChart._();

  /// Höchste Balkenstärke; was im Raster übrig bleibt, ist bewusst Luft.
  static const barMaxThickness = 20.0;

  /// Abgerundetes Datenende; an der Grundlinie bleibt der Balken eckig.
  static const barEndRadius = 4.0;

  /// Trennung zweier Flächen – in Hintergrundfarbe, nie als Rahmen.
  static const surfaceGap = 2.0;

  /// Grundlinie und Achsen.
  static const hairline = 1.0;

  /// Zeilenhöhe eines gestapelten Balkens.
  static const stackedBarThickness = 14.0;
}

abstract final class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadius {
  AppRadius._();

  static const s = 8.0;
  static const m = 12.0;
  static const l = 20.0;

  /// Kachel-/Icon-Radius der Marke (App-Icon: 46 auf 200 px).
  static const brandTile = 24.0;
}

/// Schriftfamilien der Marke.
abstract final class AppFonts {
  AppFonts._();

  /// Wortmarke und Überschriften.
  static const display = 'SpaceGrotesk';

  /// Fließtext und Bedienelemente.
  static const body = 'Manrope';
}
