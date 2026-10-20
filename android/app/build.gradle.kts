import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(environment: String, property: String): String? =
    System.getenv(environment) ?: keystoreProperties.getProperty(property)

val releaseStorePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning =
    !releaseStorePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "app.loudcaption"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.loudcaption"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Raised from Flutter's default (24) to 26: the llama_flutter_android
        // plugin (Hy-MT2 translation) requires API 26+ for SharedMemory
        // support and the manifest merger rejects anything lower.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing comes from android/key.properties locally, or from
    // ANDROID_KEYSTORE_* environment variables in CI. The keystore is never
    // committed. When a local key is present, debug builds share it so local
    // debug/release installs can replace each other; without one they fall
    // back to the standard debug key.
    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Left disabled pending verification that sherpa_onnx's FFI
            // bindings and record's plugin code survive R8; revisit as a
            // separate, tested change.
            isMinifyEnabled = false
            isShrinkResources = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// `make apk-release` builds with --split-per-abi (see its Makefile comment)
// purely to drop unused-ABI native libs; we only ever ship the single
// resulting arm64-v8a APK, never Play's multi-APK split mechanism. Flutter's
// Gradle plugin nonetheless applies Play's per-ABI versionCode offset
// (arm64-v8a: base + 2000) to that output. Pin every variant's output
// versionCode back to the raw pubspec value so APK/AAB and debug/release
// always compare consistently.
@Suppress("DEPRECATION")
android.applicationVariants.all {
    outputs.all {
        (this as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride = flutter.versionCode
    }
}

dependencies {
}

flutter {
    source = "../.."
}
