/// share_text_web.dart – Im Browser in die Zwischenablage.
///
/// Bewusst kein `navigator.share`: Für reinen Text ist die Web-Share-API auf
/// dem Desktop meist nicht vorhanden, und ein Teilen-Knopf, der nichts tut,
/// ist schlechter als ein Kopieren, das immer funktioniert.
library;

import 'package:flutter/services.dart';

import 'share_outcome.dart';

Future<ShareOutcome> shareText(String text, {String? subject}) async {
  await Clipboard.setData(ClipboardData(text: text));
  return ShareOutcome.copied;
}
