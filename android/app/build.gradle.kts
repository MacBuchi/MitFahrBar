import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Push-Benachrichtigungen (#101): wertet android/app/google-services.json
    // aus. Die Datei enthält kein Geheimnis — nur Projektnummer, App-Id und
    // den öffentlichen API-Key, wie der Supabase-Publishable-Key im Client.
    id("com.google.gms.google-services")
}

// Release-Signing aus android/key.properties (lokal bzw. in CI aus Secrets
// erzeugt). Fehlt die Datei, bleibt es beim Debug-Signing — der
// Release-Workflow veröffentlicht dann bewusst gar keine APK, statt eine
// debug-signierte auszuliefern.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "de.mcbuchi.mitfahrbar"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Einst von ota_update gefordert; das Paket ist raus, das Desugaring
        // bleibt bewusst stehen: Ob keines der übrigen Plugins es braucht,
        // ließe sich nur am Gerät beweisen, und es kostet eingeschaltet
        // nichts. Wer es entfernt, testet auf echter Hardware.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.mcbuchi.mitfahrbar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Zwei Vertriebswege, EINE App (Muster von PilzBuddy 1.87.1): Die
    // GitHub-APK aktualisiert sich selbst und behält dafür
    // REQUEST_INSTALL_PACKAGES; das Play-Bundle darf die Berechtigung nicht
    // tragen (Play verbietet Selbst-Updates, „Device and Network Abuse") —
    // `src/play/AndroidManifest.xml` nimmt sie per tools:node="remove"
    // wieder heraus. Beide Flavors tragen dieselbe `applicationId`: Ein
    // applicationIdSuffix machte daraus für Android zwei Apps, und der
    // Bundle-ID-Umzug in #87 hat gezeigt, was das die Gruppe kostet.
    //
    // Folge: Jeder Android-Build braucht ab jetzt ein `--flavor`, und der
    // Flavor steht im Ausgabepfad (app-github-release.apk,
    // bundle/playRelease/app-play-release.aab). Ein cp auf den alten Namen
    // bricht erst NACH dem Taggen ab — test/release_workflow_test.dart hält
    // Aufruf und Pfad zusammen.
    flavorDimensions += "distribution"
    productFlavors {
        create("github") { dimension = "distribution" }
        create("play") { dimension = "distribution" }
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // Gegenstück zu isCoreLibraryDesugaringEnabled – ohne diese Bibliothek
    // scheitert der Build mit ota_update.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
