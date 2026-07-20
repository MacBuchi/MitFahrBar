/// licenses.dart – Meldet die Schrift-Lizenzen an Flutters LicenseRegistry.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Schriften aus `pubspec.yaml` landen NICHT automatisch in der
/// `LicenseRegistry`: Flutter sammelt nur die LICENSE-Dateien der pub-Pakete
/// ein. Space Grotesk und Manrope stehen unter der SIL OFL, die die
/// Mitlieferung ihres Lizenztextes ausdrücklich verlangt — ohne die
/// Registrierung hier bliebe er in der App unsichtbar und wir würden die
/// Font-Lizenz verletzen.
///
/// Schlüssel = Anzeigename im Lizenz-Dialog, Wert = Asset-Pfad. Beide Dateien
/// liegen bewusst neben den `.ttf`, damit Schrift und Lizenz nicht auseinander
/// laufen. `test/licenses_test.dart` hält die Zuordnung ehrlich.
const fontLicenses = <String, String>{
  'Space Grotesk': 'assets/fonts/SpaceGrotesk-OFL.txt',
  'Manrope': 'assets/fonts/Manrope-OFL.txt',
};

/// Muss vor dem ersten `showLicensePage` laufen — in `main()` direkt nach
/// `ensureInitialized()`.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in fontLicenses.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks([entry.key], text);
    }
  });
}
