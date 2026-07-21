/// share_text_io.dart – Android: Text ans Teilen-Menü übergeben.
library;

import 'package:share_plus/share_plus.dart';

import 'share_outcome.dart';

Future<ShareOutcome> shareText(String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  return ShareOutcome.shared;
}
