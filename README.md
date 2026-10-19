# Loud Caption

[中文说明](README.zh.md)

Loud Caption is an Android app that shows large, high-contrast, real-time captions of nearby speech, using on-device sherpa-onnx (SenseVoice) speech recognition — no audio is ever uploaded, and recognition itself runs fully offline. It's built for people who are hard of hearing and want to read along with a conversation. A one-time download on first launch fetches the ~240MB recognition model (see [Install on a device](#install-on-a-device)); after that, no network connection is needed to use the app. It currently recognizes Chinese and English and supports **Android only**. The app's launcher name localizes to 大字幕 ("big captions") on devices with Chinese as the system language.

This is a personal, side-loaded project distributed through [GitHub Releases](https://github.com/DR1N0/loud-caption/releases) — not Google Play.

## Features

- Full-screen, high-contrast live captions with adjustable font size (16–80px) and automatic scrolling that keeps the latest line in view, pausing if you scroll up to re-read older ones
- Offline Chinese/English/Japanese/Korean/Cantonese speech recognition with automatic language detection — no manual switching needed
- On-device translation (Hy-MT2-1.8B via llama.cpp, never cloud-based) into one configured target language, or per-source-language routing — Cantonese routes exactly like Mandarin, since it transcribes to the same written text
- Orientation lock; the control bar adapts between a single row (portrait) and a side rail (landscape) so captions keep most of the screen
- No audio or caption history is stored; only your display and translation preferences (font size, orientation, theme, translation mode/targets) persist
- Recognition keeps running through rotation, font changes, and the in-app Settings screen; it only stops when the app is truly backgrounded, the screen locks, or you leave for system Settings

See [`docs/model-sources.md`](docs/model-sources.md) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for what's bundled and under what license, and [`docs/superpowers/specs/`](docs/superpowers/specs/) for the full design history.

## Developer guide

### Requirements

- Flutter SDK (verified with 3.41.7)
- Android Studio with its Android SDK (`adb`, `aapt`, `apksigner`, an emulator or device) plus the NDK and CMake SDK components — the translation plugin compiles llama.cpp from source at build time
- Python 3
- A JDK 17 your network's TLS setup trusts for resolving Gradle dependencies (the `Makefile` defaults to a local Zulu 17 install — override `JAVA17_HOME` if yours lives elsewhere)
- `make`
- A device or emulator running Android 8.0 (API 26) or later — raised from API 24 by the translation plugin's minimum

### Common commands

```bash
make test         # flutter test (unit + widget tests)
make analyze      # flutter analyze
make apk-debug    # build build/app/outputs/apk/debug/app-debug.apk
make apk-release  # build build/app/outputs/apk/release/app-release.apk
make apk          # alias for apk-release
make check        # pub-get + analyze + test (full gate)
make clean        # flutter clean
```

Run `make check` before sending a PR or cutting a release.

### Install on a device

```bash
make install-debug     # build + adb install -r the debug APK
make install-release   # build + adb install -r the release APK
```

On first launch, the app downloads and checksum-verifies its ~240 MB speech recognition model (SenseVoice + Silero VAD) before anything else is usable — allow time, storage, and a network connection for this one-time download. After that, tap **开始** and grant the microphone permission Android prompts for; the app needs no network connection from that point on. Switching into a translation mode later triggers a second, separate on-demand download (~1.08 GB, Hy-MT2 — see [`docs/model-sources.md`](docs/model-sources.md)); skip that unless you want to use translation. Both downloads check available storage first and refuse to start if there isn't enough room; an optional Settings toggle ("仅限 Wi-Fi 下载模型") blocks either download unless connected to Wi-Fi, for anyone who wants to avoid using mobile data.

### Signing

Both the debug and release APKs are signed with `android/app/release-keystore.jks`, a key generated for this project and **intentionally committed to the repo** — not a secret, not the per-machine auto-generated Android debug key. Debug builds deliberately use this same identity (rather than Gradle's default) so a debug build installs cleanly over a release install, or vice versa, without ever needing an uninstall first. This project ships only via GitHub Releases, never Play (which rejects debug-signed uploads anyway), so a signature that stays consistent across every build machine and build type mattered more than a private key that could be lost.

The tradeoff: because the key is public, anyone with this repo can produce an APK Android will accept as a legitimate update to an existing install. That's an acceptable risk for a personal, non-commercial project — it is **not** appropriate for an app with real adversaries or any Play Store plan, which should generate its own keystore, keep it out of version control, and back it up privately.

### Privacy

- The release manifest requests `RECORD_AUDIO`, `INTERNET`, and `ACCESS_NETWORK_STATE`; no storage, overlay, or foreground-service permission. `INTERNET` exists solely to download the pinned, checksum-verified model files on first launch (see [`docs/model-sources.md`](docs/model-sources.md)) — the app makes no other network requests. `ACCESS_NETWORK_STATE` (normal protection, no runtime prompt) only checks whether the current connection is Wi-Fi, for the optional "仅限 Wi-Fi 下载模型" Settings toggle.
- No app-authored speech-upload path exists; recognition runs on-device via the downloaded sherpa-onnx (SenseVoice) and Silero VAD models, and no audio or recognized text is ever sent anywhere. This hasn't been verified by a network traffic trace.

### Status

This app migrated its speech engine from Vosk to sherpa-onnx (SenseVoice ASR + Silero VAD). SenseVoice's automatic language detection ("auto" mode) has proven accurate enough on its own — no observed Chinese-misheard-as-English cases — that the manual language-switching UI was removed. ASR models are downloaded on first launch rather than bundled in the APK, and both the ASR and translation model downloads resume from where they left off if interrupted, falling back to mainland-China-friendly mirrors (GitHub proxies, ModelScope, hf-mirror.com) alongside their primary sources.

On-device translation (Hy-MT2-1.8B via llama.cpp, never cloud-based) is wired into the live caption pipeline and has now been verified end-to-end on a real device across dozens of translations in both 翻译 and 互译 modes. Only committed (final) caption lines are translated — an earlier speculative partial-text translation was removed after real-device testing showed on-device inference latency couldn't keep up with live speech.

Real-device testing surfaced two bugs in the third-party `llama_flutter_android` plugin this app depends on for translation: a native crash in llama.cpp's own RMSNorm kernel (incidentally resolved by removing the partial-translation trigger above, which eliminated the cancel-then-regenerate race that triggered it) and a streaming bug that garbled CJK output by mishandling multi-byte UTF-8 characters split across token boundaries. Both are fixed and verified; the second is filed upstream as [dragneel2074/Llama-Flutter#2](https://github.com/dragneel2074/Llama-Flutter/pull/2), and until it merges this app depends on a fork with the fix (see `pubspec.yaml`).

Foreground-resume behavior, battery/thermal impact of running ASR and translation together, and caption/translation accuracy across different devices and accents remain unverified beyond the single device this has been tested on. Downloadable language packs, cloud sync, caption history, and iOS remain intentionally out of scope.
