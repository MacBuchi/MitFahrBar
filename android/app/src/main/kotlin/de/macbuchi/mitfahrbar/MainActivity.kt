package de.macbuchi.mitfahrbar

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.GZIPInputStream

class MainActivity : FlutterActivity() {

    private companion object {
        /**
         * Muss wörtlich mit `ExitInfoRepository.channelName` in
         * `lib/data/exit_info_repository.dart` übereinstimmen —
         * `test/android_manifest_test.dart` vergleicht beide Dateien.
         */
        const val CHANNEL = "de.macbuchi.mitfahrbar/exit_info"

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
