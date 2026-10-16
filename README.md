# Loud Caption

[中文说明](README.zh.md)

Loud Caption is an Android app that shows large, high-contrast, real-time captions of nearby speech — fully offline, using on-device sherpa-onnx (SenseVoice) speech recognition. It's built for people who are hard of hearing and want to read along with a conversation without any audio leaving the device. It currently bundles Chinese and English models and supports **Android only**. The app's launcher name localizes to 大字幕 ("big captions") on devices with Chinese as the system language.

This is a personal, side-loaded project distributed through [GitHub Releases](https://github.com/DR1N0/loud-caption/releases) — not Google Play.

## Features

- Full-screen, high-contrast live captions with adjustable font size
- Offline Chinese/English speech recognition with automatic language detection — no manual switching needed
- Orientation lock; the control bar adapts between a single row (portrait) and a side rail (landscape) so captions keep most of the screen
- No audio or caption history is stored; only your font size and orientation preferences persist
- Recognition keeps running through rotation, font changes, and the in-app Settings screen; it only stops when the app is truly backgrounded, the screen locks, or you leave for system Settings

See [`docs/model-sources.md`](docs/model-sources.md) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for what's bundled and under what license, and [`docs/superpowers/specs/`](docs/superpowers/specs/) for the full design history.

## Developer guide

### Requirements

- Flutter SDK (verified with 3.41.7)
- Android Studio with its Android SDK (`adb`, `aapt`, `apksigner`, an emulator or device)
- Python 3
- A JDK 17 your network's TLS setup trusts for resolving Gradle dependencies (the `Makefile` defaults to a local Zulu 17 install — override `JAVA17_HOME` if yours lives elsewhere)
- `make`

### Common commands

```bash
make models      # download + checksum-verify the bundled SenseVoice + Silero VAD models
make test         # flutter test (unit + widget tests)
make analyze      # flutter analyze
make apk-debug    # build build/app/outputs/apk/debug/app-debug.apk
make apk-release  # build build/app/outputs/apk/release/app-release.apk
make apk          # alias for apk-release
make check        # models + pub-get + analyze + test (full gate)
make clean        # flutter clean
```

`make models` only needs to run once (or after an upstream model version bump) — the model files are checksum-verified and Git-ignored. Run `make check` before sending a PR or cutting a release.

### Install on a device

```bash
make install-debug     # build + adb install -r the debug APK
make install-release   # build + adb install -r the release APK
```

On first launch, tap **开始** and grant the microphone permission Android prompts for. The app bundles approximately 240 MB of model files (SenseVoice + Silero VAD); these are copied as flat files into app-private storage, with no unpacking step, so the on-device footprint is about the same size — allow time and storage before granting the mic.

### Signing

The release APK is signed with `android/app/release-keystore.jks`, a key generated for this project and **intentionally committed to the repo** — not a secret, not the Android debug key. This project ships only via GitHub Releases, never Play (which rejects debug-signed uploads), so a signature that stays consistent across every build machine mattered more than a private key that could be lost.

The tradeoff: because the key is public, anyone with this repo can produce an APK Android will accept as a legitimate update to an existing install. That's an acceptable risk for a personal, non-commercial project — it is **not** appropriate for an app with real adversaries or any Play Store plan, which should generate its own keystore, keep it out of version control, and back it up privately.

### Privacy

- The release manifest requests only `RECORD_AUDIO`; no `INTERNET`, storage, overlay, or foreground-service permission. The debug build additionally requests `INTERNET` for Flutter's own dev tooling.
- No app-authored speech-upload path exists; recognition runs on-device via bundled sherpa-onnx (SenseVoice) and Silero VAD models. This hasn't been verified by a network traffic trace.

### Status

This app migrated its speech engine from Vosk to sherpa-onnx (SenseVoice ASR + Silero VAD). Further testing showed SenseVoice's automatic language detection ("auto" mode) is accurate enough on its own — no observed Chinese-misheard-as-English cases — that the manual language-switching UI (Settings screen language list, caption-screen language toggle) was removed entirely; it remains in git history if a future feature wants it back. One phone has run the sherpa-onnx engine in auto mode with stable, accurate real-time Chinese/English captions. This specific build (including the simplified control bar) has been verified with the full automated test suite and on an Android emulator, but a dedicated real-device smoke test of this exact build is still outstanding. Foreground-resume behavior, caption accuracy across devices, and device-specific battery/thermal/accessibility behavior have not been independently verified. Online translation, downloadable language packs, cloud sync, caption history, and iOS are intentionally out of scope.
