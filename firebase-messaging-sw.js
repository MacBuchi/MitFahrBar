// Service Worker für Push-Benachrichtigungen im Web (Issue #101).
//
// firebase_messaging registriert diese Datei beim Start selbst — sie muss
// deshalb genau so heißen und im Web-Wurzelverzeichnis liegen. Fehlt sie,
// meldet das Plugin einen Registrierungsfehler und die PWA bekommt nie ein
// Token.
//
// Die Version MUSS zu `supportedFirebaseJsSdkVersion` in firebase_core_web
// passen. Driften beide auseinander, warnt firebase_core beim Start — und im
// schlechteren Fall lädt der Worker eine Fassung, die es auf gstatic nicht
// mehr gibt, und stirbt still. Die Zahl steht deshalb NICHT zusätzlich in
// diesem Kommentar: `test/android_manifest_test.dart` liest sie aus dem Paket
// und vergleicht sie mit den beiden URLs unten — eine abgeschriebene dritte
// Stelle wäre die erste, die nach einem Dependabot-Bump lügt.
//
// Die Werte unten sind Client-Konfiguration und bewusst öffentlich, genau wie
// der Supabase-Publishable-Key: Der Zugriffsschutz liegt in der RLS bzw. bei
// Firebase im Dienstkonto, das nur der Server kennt.
importScripts(
  'https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js',
);
importScripts(
  'https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyBVw_jUOqHtXBXu7A7uTcOvr0bU0TtxIpE',
  authDomain: 'mitfahrbar.firebaseapp.com',
  projectId: 'mitfahrbar',
  storageBucket: 'mitfahrbar.firebasestorage.app',
  messagingSenderId: '957629561583',
  appId: '1:957629561583:web:8fcd88dd6f8ad6124f391a',
});

// Reicht aus: Der Worker zeigt Notification-Payloads von selbst an. Ein
// eigener onBackgroundMessage-Handler würde eine ZWEITE Benachrichtigung
// erzeugen — der bekannteste Fehler in dieser Datei.
firebase.messaging();
