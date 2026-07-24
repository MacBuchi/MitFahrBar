/// release_notes_test.dart – Release-Body → lesbarer Dialogtext.
///
/// Zwei echte Eingabeformen: der auto-generierte GitHub-Body (stand beim
/// Gerätetest 2026-07-21 wortwörtlich so im Dialog) und ein deutscher
/// CHANGELOG-Abschnitt, wie ihn der Release-Workflow seither liefert.
library;

import 'package:mitfahrbar/core/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto-generierte GitHub-Notes verlieren Markdown und URLs', () {
    const body = '''
## What's Changed
* chore(skills): capture the verified way to drive the web app by @MacBuchi in https://github.com/MacBuchi/MitFahrBar/pull/49
* feat(help): the user guide lives inside the app by @MacBuchi in https://github.com/MacBuchi/MitFahrBar/pull/50


**Full Changelog**: https://github.com/MacBuchi/MitFahrBar/compare/v0.19.0...v0.20.0''';

    final text = plainReleaseNotes(body);

    expect(text, isNot(contains('#')));
    expect(text, isNot(contains('*')));
    expect(text, isNot(contains('http')));
    expect(text, isNot(contains('Full Changelog')));
    expect(text, contains("What's Changed"));
    expect(text, contains('• chore(skills): capture the verified way'));
    expect(text, contains('• feat(help): the user guide lives inside the app'));
  });

  test('ein CHANGELOG-Abschnitt wird zu ruhigem Fließtext', () {
    const body = '''

### Neu

- **Die Anleitung wohnt jetzt in der App.** Im Menü steht
  „So funktioniert MitFahrBar" — siehe [Doku](https://example.org/doku).
- Kleinere Korrekturen.
''';

    final text = plainReleaseNotes(body);

    expect(text, startsWith('Neu'));
    expect(text, contains('• Die Anleitung wohnt jetzt in der App.'));
    expect(text, contains('„So funktioniert MitFahrBar" — siehe Doku.'));
    expect(text, contains('• Kleinere Korrekturen.'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('](')));
  });

  test('leer bleibt leer — der Dialog zeigt dann keinen Abschnitt', () {
    expect(plainReleaseNotes(''), isEmpty);
    expect(plainReleaseNotes('   \n\n'), isEmpty);
    expect(
      plainReleaseNotes(
        '**Full Changelog**: https://github.com/x/y/compare/a...b',
      ),
      isEmpty,
    );
  });

  test('mehrfache Leerzeilen fallen zusammen', () {
    final text = plainReleaseNotes('Eins\n\n\n\nZwei');
    expect(text, 'Eins\n\nZwei');
  });
}
