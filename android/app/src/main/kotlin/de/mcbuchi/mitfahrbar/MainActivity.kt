package de.mcbuchi.mitfahrbar

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.zip.GZIPInputStream

class MainActivity : FlutterActivity() {

    private companion object {
        /**
         * Muss wörtlich mit `ExitInfoRepository.channelName` in
         * `lib/data/exit_info_repository.dart` übereinstimmen —
         * `test/android_manifest_test.dart` vergleicht beide Dateien.
         */
        const val CHANNEL = "de.mcbuchi.mitfahrbar/exit_info"

        /**
         * Muss wörtlich mit `NotificationHealthProbe.channelName` in
         * `lib/core/notification_health_probe.dart` übereinstimmen —
         * `test/android_manifest_test.dart` vergleicht beide Dateien.
         */
        const val HEALTH_CHANNEL = "de.mcbuchi.mitfahrbar/notification_health"

        /**
         * Muss wörtlich mit `ApkInstaller.channelName` in
         * `lib/data/apk_installer.dart` übereinstimmen —
         * `test/android_manifest_test.dart` vergleicht beide Dateien.
         */
        const val INSTALL_CHANNEL = "de.mcbuchi.mitfahrbar/apk_install"

        /** Genug für den Haupt-Thread; das Schema erlaubt 4000 Zeichen. */
        const val TRACE_CHARS = 6000

        /** Obergrenze beim Lesen, damit ein Riesen-Dump nichts blockiert. */
        const val TRACE_BYTES = 4 * 1024 * 1024
    }
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

    /**
     * Liest, warum die App beim letzten Mal beendet wurde (Issue #144).
     *
     * Android führt seit Version 11 selbst Buch darüber, und eine App darf
     * ihre EIGENEN Einträge ohne jede Berechtigung lesen. Das schließt die
     * Lücke des Error-Sinks (#136): Dort landet nur, was die App überlebt —
     * ein ANR oder Absturz hinterlässt nichts.
     *
     * Der Kanal läuft über eine Background-TaskQueue: Der ANR-Dump ist bis
     * zu 4 MB groß und gzip-gepackt — auf dem Platform-Thread gelesen wäre
     * die Diagnose selbst ein ANR-Kandidat. `result.success` aus dem
     * Handler-Thread ist mit TaskQueue ausdrücklich erlaubt.
     *
     * Bewusst zwei Methoden statt einer: Die Übersicht ist billig, der
     * Thread-Dump nicht — Dart holt ihn nur für Einträge, die es noch
     * nicht gemeldet hat. Muster von PilzBuddy (pilzbuddy#147); anders als
     * dort werden RSS/PSS unverändert in kB gereicht (die Vorlage teilte
     * doppelt durch 1024) und der Timestamp als Number gelesen (kleine
     * Dart-Ints kommen im Codec als Integer an, nicht als Long).
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val taskQueue = messenger.makeBackgroundTaskQueue()
        MethodChannel(messenger, CHANNEL, StandardMethodCodec.INSTANCE, taskQueue)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exitReasons" ->
                        result.success(exitReasons(call.argument<Int>("limit") ?: 10))
                    "exitTrace" -> {
                        val timestamp =
                            call.argument<Number>("timestamp")?.toLong() ?: 0L
                        result.success(exitTrace(timestamp))
                    }
                    else -> result.notImplemented()
                }
            }

        // Bewusst OHNE TaskQueue, also auf dem Platform-Thread: Diese
        // Abfragen sind ein paar Feldzugriffe am NotificationManager, kein
        // 4-MB-Dump. Und `startActivity` gehört ohnehin hierher.
        MethodChannel(messenger, HEALTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                val channelId = call.argument<String>("channel")
                when (call.method) {
                    "read" -> result.success(notificationHealth(channelId))
                    "openAppNotifications" -> {
                        openSettings(
                            Settings.ACTION_APP_NOTIFICATION_SETTINGS,
                            Bundle().apply {
                                putString(Settings.EXTRA_APP_PACKAGE, packageName)
                            },
                        )
                        result.success(null)
                    }
                    "openChannel" -> {
                        openSettings(
                            Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS,
                            Bundle().apply {
                                putString(Settings.EXTRA_APP_PACKAGE, packageName)
                                putString(Settings.EXTRA_CHANNEL_ID, channelId)
                            },
                        )
                        result.success(null)
                    }
                    "openDndAccess" -> {
                        openSettings(
                            Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS,
                            null,
                        )
                        result.success(null)
                    }
                    "openAppDetails" -> {
                        openSettings(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            null,
                            Uri.fromParts("package", packageName, null),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // In-App-Update ohne `ota_update` (Muster von PilzBuddy #161): Die
        // App lädt die APK selbst und ÜBERGIBT sie nur — installiert wird
        // nie still, das System zeigt seinen eigenen Dialog. Genau deshalb
        // genügt REQUEST_INSTALL_PACKAGES, und die Signatur-Berechtigung
        // INSTALL_PACKAGES aus dem ota_update-Manifest entfällt.
        MethodChannel(messenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canInstall())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "updatesPath" -> {
                        // Der Ablageort der geladenen APK. Von hier genannt
                        // statt über path_provider in Dart — die Abhängigkeit
                        // gibt es im Projekt sonst nirgends. Der Ordner steht
                        // in beiden Backup-Regelwerken als Ausschluss.
                        val dir = File(filesDir, "updates").apply { mkdirs() }
                        result.success(dir.absolutePath)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.error("no_path", "Pfad fehlt", null)
                        } else {
                            installApk(path, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Systemeinstellung für genau diese App öffnen, nicht die globale Liste. */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /**
     * Übergibt die geladene Datei dem System-Installer.
     *
     * Über einen FileProvider statt `file://`: Ab Android 7 wirft eine
     * herausgereichte Datei-URI eine FileUriExposedException, und der
     * Installer läuft in einem fremden Prozess — er braucht die per
     * `FLAG_GRANT_READ_URI_PERMISSION` erteilte Leseerlaubnis.
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Datei nicht gefunden: $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            result.success(true)
        } catch (e: Exception) {
            // Dart fällt daraufhin auf den Browser-Download zurück.
            result.error("install_failed", e.message, null)
        }
    }

    /**
     * Der wahre Zustand der Benachrichtigungen — vier Achsen, die einander
     * nicht ersetzen (Issue #180).
     *
     * **Warum nicht über `firebase_messaging`.** Dessen
     * `getNotificationSettings()` ist auf Android unzuverlässig: Es meldet
     * `authorized`, während die Systemeinstellung aus ist
     * (flutterfire#4492), und auf API 34 `denied`, bevor überhaupt gefragt
     * wurde (flutterfire#12839). Darauf eine Überwachung zu bauen hieße,
     * genau die stille Falschaussage nachzubauen, die #180 beseitigt.
     * `areNotificationsEnabled()` ist der Aufruf, den die Android-Doku
     * nennt, und der einzige, der Berechtigung UND Schalter abbildet —
     * `checkSelfPermission` meldet vor Android 13 immer „verweigert".
     *
     * Alles ist `null`, wo die Plattform es nicht kennt; die Auswertung in
     * Dart behandelt „weiß ich nicht" als „nicht meckern". Ein erfundener
     * Vorgabewert wäre hier eine Behauptung.
     */
    private fun notificationHealth(channelId: String?): Map<String, Any?> {
        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && channelId != null) {
                manager.getNotificationChannel(channelId)
            } else {
                null
            }
        return mapOf(
            "notificationsEnabled" to
                NotificationManagerCompat.from(this).areNotificationsEnabled(),
            // Kein Kanal ist etwas anderes als ein stummer Kanal: Vor
            // Android 8 gibt es keine, danach legt `onCreate` ihn an.
            "channelImportance" to channel?.importance,
            "channelBypassesDnd" to channel?.canBypassDnd(),
            "interruptionFilter" to manager.currentInterruptionFilter,
            "policyAccessGranted" to manager.isNotificationPolicyAccessGranted,
            // Der einzige Akku-Zustand, der wirklich blockiert: „Eingeschränkt"
            // unterbindet JEDE FCM-Zustellung, high wie normal. Gewöhnliche
            // Akkuoptimierung tut das nicht — high-priority weckt aus Doze.
            "backgroundRestricted" to
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    getSystemService(ActivityManager::class.java)
                        .isBackgroundRestricted
                } else {
                    null
                },
        )
    }

    /**
     * Öffnet einen Systemschirm. Scheitert das (kein Gerät hat garantiert
     * jeden Intent), bleibt die App stehen, statt zu stürzen — der Schirm
     * hat den Zustand ohnehin schon benannt.
     */
    private fun openSettings(action: String, extras: Bundle?, data: Uri? = null) {
        try {
            startActivity(
                Intent(action).apply {
                    extras?.let { putExtras(it) }
                    data?.let { setData(it) }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        } catch (_: ActivityNotFoundException) {
            // Nichts zu tun: Der Text daneben sagt, worum es geht.
        }
    }

    /** Übersicht ohne Thread-Dump — billig genug für jeden App-Start. */
    private fun exitReasons(limit: Int): List<Map<String, Any?>> {
        val infos = historicalExits(limit) ?: return emptyList()
        return infos.map { info ->
            mapOf(
                "timestamp" to info.timestamp,
                "reason" to info.reason,
                "reasonName" to reasonName(info.reason),
                "description" to info.description,
                "importance" to info.importance,
                // getRss()/getPss() liefern laut Doku bereits kB.
                "rssKb" to info.rss,
                "pssKb" to info.pss,
                // Nur bei ANR liefert Android überhaupt einen Dump.
                "hasTrace" to (info.reason == ApplicationExitInfo.REASON_ANR),
            )
        }
    }

    /**
     * Der Haupt-Thread-Abschnitt des Dumps zu einem Eintrag, oder null.
     *
     * Nur der Haupt-Thread: `state=R` plus hohe `utm`/`stm` heißt „rechnet",
     * gehaltene Mutex heißt „Deadlock" — das entscheidet, wo man sucht. Die
     * vollständigen Threads passen weder in die Spalte noch in den Digest.
     */
    private fun exitTrace(timestamp: Long): String? {
        val info = historicalExits(20)?.firstOrNull { it.timestamp == timestamp }
            ?: return null
        if (info.reason != ApplicationExitInfo.REASON_ANR) return null
        val dump = try {
            info.traceInputStream?.use { readTrace(it) }
        } catch (e: Exception) {
            // Der Dump ist ein Extra. Scheitert er, ist der Eintrag selbst
            // immer noch die halbe Antwort — deshalb hier nicht werfen.
            null
        } ?: return null
        return mainThreadSection(dump)
    }

    private fun historicalExits(limit: Int): List<ApplicationExitInfo>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(packageName, 0, limit)
        } catch (e: Exception) {
            null
        }
    }

    /** Android liefert den ANR-Dump gzip-gepackt; erkannt an der Signatur. */
    private fun readTrace(stream: InputStream): String {
        val raw = ByteArrayOutputStream().use { buffer ->
            val chunk = ByteArray(64 * 1024)
            var total = 0
            while (total < TRACE_BYTES) {
                val read = stream.read(chunk)
                if (read <= 0) break
                buffer.write(chunk, 0, read)
                total += read
            }
            buffer.toByteArray()
        }
        val gzipped = raw.size > 1 &&
            raw[0] == 0x1f.toByte() && raw[1] == 0x8b.toByte()
        return if (gzipped) {
            GZIPInputStream(raw.inputStream()).use { it.readBytes().decodeToString() }
        } else {
            raw.decodeToString()
        }
    }

    private fun mainThreadSection(dump: String): String {
        val start = dump.indexOf("\"main\"")
        if (start < 0) return dump.take(TRACE_CHARS)
        val end = dump.indexOf("\n\n", start)
        val section = if (end > start) dump.substring(start, end) else dump.substring(start)
        return section.take(TRACE_CHARS)
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "CRASH"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE_USAGE"
        ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
        ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
        ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
        ApplicationExitInfo.REASON_OTHER -> "OTHER"
        else -> "UNKNOWN_$reason"
    }
}
