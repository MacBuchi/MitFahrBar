package de.macbuchi.mitfahrbar

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    /**
     * Legt den Benachrichtigungs-Kanal an, auf den das Manifest verweist
     * (`default_notification_channel_id`, Issue #101).
     *
     * Ab Android 8 braucht jede Benachrichtigung einen Kanal. Existiert der
     * im Manifest genannte nicht, weicht FCM still auf einen eigenen namens
     * „Miscellaneous" aus — die Gruppe fände in den Systemeinstellungen also
     * nicht, was sie abschalten soll. Das Anlegen ist idempotent: Ein
     * vorhandener Kanal bleibt unverändert, samt der vom Nutzer gesetzten
     * Lautstärke.
     *
     * Hier statt in Dart, weil der Kanal auch dann stehen muss, wenn eine
     * Nachricht eintrifft, ohne dass jemand die App geöffnet hat.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.notification_channel_plan_id),
            getString(R.string.notification_channel_plan_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = getString(R.string.notification_channel_plan_description)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
