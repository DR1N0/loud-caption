# Loud Caption

Loud Caption is an Android MVP for large, high-contrast, real-time captions. It is intended to help a nearby listener follow a conversation without sending audio to a captioning service. This repository currently supports **Android only**; it is not an iOS app and it is not yet a product-readiness or speech-accuracy claim.

## Scope and privacy

- The current developer release APK's audited manifest requests `RECORD_AUDIO` for capture and no `INTERNET`, storage, overlay, or foreground-service permission. It also includes Android's generated normal dynamic-receiver permission. This APK includes the capture-coordinator UI and has been installed and exercised on one developer phone (see below).
- The debug APK used for local development/emulator installation includes `INTERNET` in its debug manifest for Flutter development tooling. The release APK does not include that permission.
- The reviewed app source uses on-device Vosk models and no app-authored speech-upload path was identified. It stores caption preferences (language, font size, orientation), not caption history or audio. The offline emulator smoke reached recognition startup with Wi-Fi and mobile data disabled.
- No dynamic network-traffic trace was performed. The permission/build checks and offline smoke do not by themselves prove that no speech data can ever be uploaded by every runtime dependency or environment.
- Model archives are downloaded over HTTPS during developer/build preparation; recognition is designed to use the bundled models at runtime.
- First use unpacks roughly 82 MB of model ZIPs into about 133 MB of app-private storage. Allow time and sufficient internal storage before granting the microphone.

The MVP has five live-screen controls: **A+**, **A-**, language toggle, orientation lock, and Settings. Settings lets the user enable/disable the installed Chinese and English models (at least one remains enabled).

While the app remains foregrounded, changing font size or orientation and opening, using, or leaving **in-app** Settings preserve the same microphone/recognizer session. Changing the selected recognition language, including by disabling it in Settings, swaps models. A genuine background transition, lock screen, or opening Android **system** Settings stops capture; foreground return rechecks microphone permission and the native session's logical health before restoring a lost session. A brief `inactive` state alone does not stop an existing session, but cannot initiate a new recording. Logical health is not proof that audio samples or accurate captions are arriving. These coordinator behaviors have mock coverage, and the current-source release APK has had a short developer-phone pass: the developer reported no problems, and the device's own log showed one continuous recognizer session spanning rotation/in-app-Settings use, exactly one session replacement consistent with a single language switch, and a clean stop exactly coincident with backgrounding, with no app crash. That one pass did not itself observe a subsequent foreground resume, caption text content, or font-size behavior; treat those as developer-confirmed but not independently log-verified.

## Requirements

Install:

- Flutter SDK (this project was verified with Flutter 3.41.7)
- Android Studio and its Android SDK/emulator components
- Python 3
- A JDK 17 trusted by the network used to resolve Gradle dependencies. The commands below use this machine's Zulu JDK without changing global Flutter or TLS settings.

## Get models, test, and build

From the repository root, provision the pinned assets and run the Flutter checks:

```bash
python3 scripts/fetch_models.py
python3 -m unittest discover -s test -p 'model_sources_test.py'
flutter pub get
flutter analyze
flutter test
```

`fetch_models.py` downloads only these exact ZIP names over HTTPS, verifies their published catalog MD5 values while streaming, and atomically places them under `assets/models/`:

```text
vosk-model-small-en-us-0.15.zip  09ab50ccd62b674cbaa231b825f9c1cb
vosk-model-small-cn-0.22.zip     d1a8e82933dcc7632667c036b0bb3dbb
```

The ZIPs are intentionally Git-ignored. Build Android with the command-scoped JDK (do not disable TLS or modify global Flutter configuration):

```bash
(cd android && env JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home PATH=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin:$PATH ./gradlew --no-daemon -Dorg.gradle.java.home=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home :app:testDebugUnitTest)
(cd android && env JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home PATH=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin:$PATH ./gradlew --no-daemon -Dorg.gradle.java.home=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home :app:assembleDebug :app:assembleRelease)
```

Artifacts are:

```text
build/app/outputs/apk/debug/app-debug.apk
build/app/outputs/apk/release/app-release.apk
```

Verify an APK before installing it:

```bash
$ANDROID_SDK_ROOT/build-tools/<version>/apksigner verify --verbose --print-certs build/app/outputs/apk/release/app-release.apk
```

### Signing caveat

This project is distributed only as a GitHub Release, never through Google Play (which rejects debug-signed uploads anyway). The `release` build type signs with `android/app/release-keystore.jks`, a dedicated key generated for this project and **committed to the repository on purpose** — not the Android debug key, and not a secret.

That tradeoff is deliberate and should be understood before reusing this pattern: because the private key is public, anyone with this repository can produce a new APK that Android will accept as a legitimate update to an existing install (the signatures match). For a personal, non-commercial, side-loaded project this was judged an acceptable risk in exchange for every build machine — including a future CI runner — producing update-compatible signatures without a private key that could be lost. It is not an appropriate choice for an app with real adversaries, real users' security expectations, or any Play Store distribution plan; a project in that position should generate its own keystore, keep it out of version control, and back it up privately instead.

## Local install and emulator smoke

In Android Studio Device Manager, create/start the existing `Medium_Phone_API_36.1` AVD, or start it from the SDK command line. Install only onto that local emulator:

```bash
adb install -r build/app/outputs/apk/debug/app-debug.apk
adb shell monkey -p app.loudcaption.loud_caption 1
```

This debug APK includes the debug-only `INTERNET` permission described above. Use the separately audited release APK for release-manifest permission claims; neither artifact should be distributed under the current debug signing configuration.

On first launch, tap **开始** and choose Android's microphone permission option. If the model cannot load, verify the two archives and their checksums above, then reinstall after freeing internal storage. A permanently denied microphone permission can be changed in Android app settings.

For an offline smoke, disable emulator Wi-Fi and mobile data after the APK is installed, then grant the microphone and wait for the bundled model to unpack. Re-enable network afterward. No runtime network connection is needed for recognition.

## Model and code notices

- English model: [`vosk-model-small-en-us-0.15`](https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip)
- Chinese model: [`vosk-model-small-cn-0.22`](https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip)
- Model catalog and published license labels: <https://alphacephei.com/vosk/models/>
- Vosk Android/API code: <https://github.com/alphacep/vosk-api> (Apache-2.0)

See [`docs/model-sources.md`](docs/model-sources.md) for the pinned archive identities, checksum limitations, and redistribution review background, and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the Apache License 2.0 text and attribution bundled with public releases of this APK. Vosk API's Apache-2.0 license alone does not establish rights for model data. No substantial code from the local `LiveTranscribe-Android` MIT reference project was copied into this repository; add its MIT attribution if that changes.

## Not in this MVP

Online translation, downloadable language packs, account/cloud sync, caption history/export, and iOS are intentionally out of scope. One phone ran an earlier release APK with stable basic Mandarin/English real-time captions after its JNA release-crash fix. The current coordinator UI, rebuilt as a **developer-only, debug-signed** APK, has since had a short pass on a connected developer phone: the developer reported all exercised features worked, and device logs corroborated a single continuous session across rotation/in-app Settings, one clean language-switch replacement, and an exact background stop with no crash. Foreground-resume behavior, actual caption accuracy, and device-specific thermal/battery/accessibility validation were not independently confirmed in that pass and remain open before any broader claim. Emulator UI observations and mock-driven tests do not by themselves establish those claims.
