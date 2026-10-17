plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.loudcaption.loud_caption"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.loudcaption.loud_caption"
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

    // This project is distributed only via GitHub Releases, never Google Play,
    // which would reject a debug-signed upload. The signing identity below is
    // intentionally committed to the repo (not a secret) so every build
    // machine produces update-compatible signatures without a private key to
    // lose. Anyone with this repo can sign a matching "update" — see
    // README.md's Signing section before reusing this pattern elsewhere.
    //
    // Debug builds use this same identity (not the per-machine auto-generated
    // debug key) so a debug build can be installed over a release install (or
    // vice versa) without an uninstall — there's no meaningful security
    // reason to keep them apart for a project whose signing key is already
    // public and that isn't shipping to Play.
    signingConfigs {
        create("release") {
            storeFile = file("release-keystore.jks")
            storePassword = "loud-caption-public-release-key"
            keyAlias = "loud_caption_release"
            keyPassword = "loud-caption-public-release-key"
        }
    }

    buildTypes {
        release {
            // Left disabled pending verification that sherpa_onnx's FFI
            // bindings and record's plugin code survive R8; revisit as a
            // separate, tested change.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// `make apk-release` builds with --split-per-abi (see its Makefile comment)
// purely to drop unused-ABI native libs; we only ever ship the single
// resulting arm64-v8a APK, never Play's multi-APK split mechanism. Flutter's
// Gradle plugin nonetheless applies Play's per-ABI versionCode offset
// (arm64-v8a: base + 2000) to that output, which only this project's debug
// build (built without --split-per-abi) doesn't get — making debug look like
// an older version than an already-installed release build, which defeats
// the shared-signing-key point of letting the two install over each other
// freely. Pin every variant's output versionCode back to the raw pubspec
// value so debug and release always compare equal. Must use the same
// deprecated per-variant-output API Flutter's own plugin uses (rather than
// AGP's newer androidComponents/onVariants API) and must be registered here,
// after `dev.flutter.flutter-gradle-plugin` has already registered its own
// override — Gradle calls same-API listeners in registration order, so this
// one runs second and wins.
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
