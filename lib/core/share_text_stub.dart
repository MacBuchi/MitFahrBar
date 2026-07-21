/// share_text_stub.dart – Fallback für Plattformen ohne Weiche.
library;

import 'share_outcome.dart';

Future<ShareOutcome> shareText(String text, {String? subject}) async {
  throw UnsupportedError('Kein Teilen auf dieser Plattform.');
}
