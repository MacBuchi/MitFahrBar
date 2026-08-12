/// system_insets.dart – Selbst gesetztes Scroll-Padding um den unteren
/// Systemrand ergänzen (#241).
///
/// **Warum es diese Zeile überhaupt braucht.** Eine `ListView` legt die
/// Ränder der Systemleisten von sich aus an — aber **nur**, solange sie kein
/// eigenes `padding` trägt (`BoxScrollView.buildSlivers`: `if (padding ==
/// null)` … sonst wird das gesetzte Padding unverändert benutzt). Wer also
/// Abstände selbst bestimmt, verliert die Systemränder ersatzlos. Auf einem
/// Android mit Navigationsleiste liegt das letzte Element dann darunter, und
/// weiter scrollen geht am Listenende nicht mehr — gemeldet am 12.08.2026
/// für den Benachrichtigungs-Schirm, wo genau der letzte Knopf betroffen war.
///
/// **Nur nötig, wo kein `bottomNavigationBar` steht.** Das `Scaffold` nimmt
/// den unteren Rand aus der `MediaQuery` seines Rumpfes heraus, sobald es
/// eine hat — die Tab-Seiten der App sind deshalb unauffällig, und genau
/// darum fällt das Problem nur auf den eigenständigen Schirmen auf.
///
/// **`padding`, nicht `viewPadding`.** Damit rechnet Flutter im Automatikfall
/// ebenfalls, und bei offener Tastatur wird der Wert richtigerweise 0: Die
/// Leiste liegt dann hinter der Tastatur, und ein zweiter Abstand darüber
/// schöbe den Inhalt grundlos nach oben.
///
/// **Kein `SafeArea` stattdessen.** Das beschnitte die Liste schon oberhalb
/// der Leiste; Inhalt soll darunter durchlaufen, nur das letzte Element
/// braucht Luft.
library;

import 'package:flutter/material.dart';

EdgeInsets withSystemBottom(BuildContext context, EdgeInsets base) =>
    base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);
