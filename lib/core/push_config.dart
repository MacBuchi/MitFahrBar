/// push_config.dart – Firebase-Zugang für die Push-Benachrichtigungen (#101).
///
/// Alle Werte hier sind **Client-Konfiguration und bewusst öffentlich**, genau
/// wie der Supabase-Publishable-Key: Sie identifizieren das Projekt, sie
/// berechtigen zu nichts. Verschicken darf nur, wer das Dienstkonto hat, und
/// das liegt ausschließlich in `supabase secrets`.
///
/// Auf Android liest die native Seite dieselben Angaben aus
/// `android/app/google-services.json` — die Datei ist die Quelle, diese hier
/// ist die Web-Fassung davon. Ändert sich das Firebase-Projekt, gehören beide
/// nachgezogen (plus `web/firebase-messaging-sw.js`).
library;

class PushConfig {
  static const projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'mitfahrbar',
  );
  static const apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyBVw_jUOqHtXBXu7A7uTcOvr0bU0TtxIpE',
  );
  static const appId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:957629561583:web:8fcd88dd6f8ad6124f391a',
  );
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_SENDER_ID',
    defaultValue: '957629561583',
  );
  static const authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'mitfahrbar.firebaseapp.com',
  );
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'mitfahrbar.firebasestorage.app',
  );

  /// Der öffentliche Teil des Web-Push-Zertifikats. Nur im Web nötig — der
  /// Browser schickt ihn selbst an den Push-Dienst.
  static const vapidKey = String.fromEnvironment(
    'FIREBASE_VAPID_KEY',
    defaultValue:
        'BKnKgnYS3CJCcLMcyDEkudfSRLFiSryTOdjIL7RbYL4W0BSJhvTwLNpNsfdwXA0KLG7ogedF61mXFyR-qcL5tbA',
  );

  /// Wie `SupabaseConfig.isConfigured` ein `const`, damit der Demo-Build den
  /// ganzen Push-Zweig wegwirft statt ihn zur Laufzeit zu umschiffen.
  static const isConfigured = projectId != 'REPLACE-ME';
}
