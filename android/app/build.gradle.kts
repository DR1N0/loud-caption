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
        minSdk = flutter.minSdkVersion
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
            // Vosk's JNA bindings look up fields by name at runtime.
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    implementation("com.alphacephei:vosk-android:0.3.75")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
