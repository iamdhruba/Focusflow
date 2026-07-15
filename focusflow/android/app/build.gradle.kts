import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ─── Fix 8: Read keystore credentials from android/key.properties ────────────
// Generation steps (run once, store the output securely, do NOT commit):
//   keytool -genkey -v -keystore upload-keystore.jks -alias upload \
//           -keyalg RSA -keysize 2048 -validity 10000
// Then create android/key.properties with:
//   storePassword=<password>
//   keyPassword=<password>
//   keyAlias=upload
//   storeFile=../upload-keystore.jks
//
// android/key.properties and *.jks MUST be in .gitignore (see android/.gitignore).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

android {
    namespace = "com.focusflow.productivity.app"
    // compileSdk = 36 (Android 16). Do NOT bump compileSdkPreview to track
    // Android 17 beta — that would pull in unreleased APIs and break
    // Play Store uploads. Revisit only after Android 17 reaches stable.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.focusflow.productivity.app"
        minSdk = flutter.minSdkVersion
        // Targeting Android 16 (API 36) — Google Play's Aug-2026 deadline
        // for new uploads / updates will require API 36+. compileSdk is
        // already 36 so this is a one-line bump, no dependency churn.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Fix 8: real release keystore when key.properties is present.
        // Falls back to debug signing for dev-time `flutter run --release` until you
        // generate and commit the keystore setup.
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // v1.0.1: R8/ProGuard RE-ENABLED. The per-plugin keep rules
            // in `proguard-rules.pro` were CARRIED OVER from v1.0.0
            // where R8 was disabled — they were INERT in v1.0.0 and
            // this is the FIRST build that actually exercises them.
            // Expect possible keep-rule gaps on first run; surface them
            // with:
            //   flutter build appbundle --release \
            //     --obfuscate --split-debug-info=build/symbols/
            // Any "Missing class …" warnings in the build output should
            // be fixed by adding the corresponding
            // `-keep class <pkg>.** { *; }` rule to proguard-rules.pro.
            //
            // Resource shrinker (isShrinkResources=true) is paired with
            // `res/raw/keep.xml` to preserve Flutter-side drawables
            // (launcher icon, splash background, accessibility/device-
            // admin/data-extraction XML) that the engine loads by name
            // at runtime. Without keep.xml, those would be stripped
            // silently and the launcher icon would render as a generic
            // Android icon.
            //
            // CRITICAL: when R8 + --obfuscate is on, the build emits
            // build/app/outputs/mapping/release/mapping.txt. This file
            // MUST be (1) uploaded to Play Console (App Bundle Explorer
            // → "Upload ReTrace mapping file") and (2) archived in
            // source control or a secret store for the lifetime of the
            // version. Without it, post-release crash reports are
            // unreadable. See RELEASE.md for the full workflow.
            isMinifyEnabled = true
            isShrinkResources = true
            // proguardFiles is intentionally kept referenced even though
            // R8 is off in v1.0.0 — proguard-rules.pro is the
            // defense-in-depth keep-rule file that v1.0.1+ will lean on
            // when minify is flipped back on. Removing this reference
            // (or the rules file) without re-validating every plugin
            // would silently lose the future-1.0.1 safety net.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Fix 8: use the real release keystore when available; fallback to debug
            // so local builds keep working until you publish.
            signingConfig = if (keystoreProperties["storeFile"] != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
