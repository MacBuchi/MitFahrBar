/// web_notifications.dart – Plattform-Weiche: was der Browser über die
/// Benachrichtigungs-Berechtigung sagt.
library;

export 'web_notifications_stub.dart'
    if (dart.library.js_interop) 'web_notifications_web.dart';
