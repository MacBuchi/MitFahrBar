/// reload_app_web.dart – Seite neu laden, damit die neue Version greift.
library;

import 'package:web/web.dart' as web;

void reloadApp() => web.window.location.reload();
