/// wordmark_test.dart – Der sichtbare Schriftzug heißt wirklich MitFahrBar.
///
/// Klingt trivial, hat aber einen echten Ausfall hinter sich: Der Schriftzug
/// ist zweifarbig aus zwei TextSpans gebaut ('MitFahr' + 'Bar'). Bei der
/// Umbenennung v0.34.0 (#87) ersetzte ein Suchlauf alle „RideBuddy"-Strings —
/// die Fragmente 'Ride' und 'Buddy' fand er nicht, und Splash wie Login
/// zeigten den alten Namen bis in Production. Die `semanticsLabel` stimmte
/// da längst; nur das Sichtbare log. Dieser Test liest deshalb den
/// GERENDERTEN Text, nicht das Label.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/widgets/mitfahrbar_mark.dart';

void main() {
  testWidgets('der gerenderte Schriftzug ergibt MitFahrBar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MitFahrBarWordmark())),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(MitFahrBarWordmark),
        matching: find.byType(RichText),
      ),
    );
    expect(richText.text.toPlainText(), 'MitFahrBar');
  });
}
