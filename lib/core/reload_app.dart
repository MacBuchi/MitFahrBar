/// reload_app.dart – Plattform-Weiche fürs Neuladen der Web-App.
library;

export 'reload_app_stub.dart'
    if (dart.library.js_interop) 'reload_app_web.dart';
