# loud-caption — MVP Design

Status: Approved for planning
Date: 2026-09-30
Related: [HANDOFF.md](../../../HANDOFF.md)

## 1. Goal

A phone app for elderly users with hearing impairment:

- Launches full-screen.
- Listens via the phone microphone.
- Shows real-time speech-to-text as large, font-size-adjustable captions.

This is a personal/small-scale project (side-loaded APK, not a commercial product), so scope is kept deliberately minimal for the first release.

## 2. Platform & Tech Stack

**Decision: Flutter, Android-first, with a platform-abstraction seam for iOS later.**

- Android is the only platform actually shipped in phase 1. Elderly users' phones (especially outside North America/Europe) skew heavily Android, and Android also lets us reuse architectural lessons from the mature reference app [LiveTranscribe-Android](https://github.com/chartmann1590/LiveTranscribe-Android) (MVVM, `SpeechEngine` abstraction, streaming Vosk).
- Flutter is used instead of native Kotlin so the UI, state management, and business logic are written once and can support iOS later without a rewrite. This is viable specifically *because* this app's use case is simple: foreground-only, no overlay-over-other-apps, no system audio capture, no background service — the parts of LiveTranscribe-Android that force native complexity don't apply here.
- The only piece that needs a platform-specific implementation is speech capture + recognition, and that is isolated behind our own `SpeechEngine` Dart interface (see Architecture). Adding iOS later means writing one new implementation of that interface — not touching UI or app state.

**Rejected alternatives:**
- iOS-only: would use a completely different stack, no leverage from the Android reference project, and the near-term user base skews Android.
- Native Android (no Flutter): fastest to ship, but a future iOS port means rewriting the entire app, not just the ASR layer.

## 3. Speech Recognition (ASR)

**Decision: Fully offline, on-device recognition using Vosk.**

Elderly users can't be assumed to have reliable connectivity (home/hospital Wi-Fi, no data plan, etc.), and per-use cloud API cost is undesirable for a personal project with no monetization. [LiveTranscribe-Android](https://github.com/chartmann1590/LiveTranscribe-Android) validates that streaming on-device Vosk recognition is production-viable on Android today.

**Rejected alternatives:**
- Android's built-in `SpeechRecognizer`: simplest integration, but offline availability depends on Android version (12+) and OEM implementation — not guaranteed across the phones elderly users actually own.
- Cloud API (e.g. Google Cloud STT): highest accuracy, but requires constant connectivity and a paid API key — this is the exact approach HANDOFF.md already rejected when evaluating `google/live-transcribe-speech-engine`.
- Hybrid (offline default + cloud fallback): more flexible, but doubles the integration and settings surface for a personal MVP. Deferred — not ruled out for later.

**Integration approach: an app-owned, thin Kotlin/Flutter bridge over the official [Vosk Android AAR](https://central.sonatype.com/artifact/com.alphacephei/vosk-android/0.3.75), pinned to `com.alphacephei:vosk-android:0.3.75`.**

The official [Vosk API](https://github.com/alphacep/vosk-api) supplies `Model`, `Recognizer`, `org.vosk.android.SpeechService` (an audio-capture helper, **not** an Android foreground `Service`), and `RecognitionListener` with partial/result/final callbacks. On Android, Kotlin owns microphone capture, recognizer lifetime and foreground-only stop/release; the bridge sends only text, status and errors to Dart via an event channel, never raw PCM. Flutter sends start/stop/language commands through a method channel. Model loading and recognition run off the Flutter UI thread; native events are serialized and tagged by session so late results after a language switch cannot overwrite new captions. Bundled model zip assets are extracted to private app storage before native loading.

This bridge remains behind our own Dart `SpeechEngine` interface (see Architecture): a future iOS implementation replaces only this Android adapter, not UI or app state. The reference app's long-lived streaming recognizer and Vosk event semantics are the model, but its overlay, system-audio, translation and Android foreground-service infrastructure are out of scope.

**Community-package decision:** `vosk_flutter` last published in April 2023 even though its GitHub source had later changes (October 2024); `vosk_flutter_2` last published in October 2023. `vosk_flutter_service` was genuinely updated in September 2026 and is useful as a prototype/code reference, but its Android integration tests are not run in its current CI and its iOS speech-result callback does not currently match its Dart event-stream listener. We prefer to own the small bridge and native lifecycle rather than assume a community binding is already validated. Its Android binaries come from a Gradle AAR: the previously stated `dart run vosk_flutter_service install -t android` step was incorrect and is **not** part of this design.

## 4. Language Scope

**Decision: Phase 1 ships Chinese (Mandarin) and English only, both bundled in the APK as assets. Architecture is designed for future extensibility (downloadable language packs, online translation), but phase 1 does not implement either.**

- Both Vosk models are packaged as Flutter assets — no first-run download, no network dependency, consistent with the offline-first design goal.
- The settings screen's "available languages" list is designed as the same extension point a future language-pack downloader would populate — phase 1 just doesn't wire up a downloader behind it.
- Translation (text-to-text, e.g. for a non-native speaker reading captions in another language) is explicitly **out of scope for phase 1** and will require network connectivity when it's built later — not attempted offline.

## 5. Distribution

**Decision: Side-loaded APK only. No Play Store, no monetization.**

`flutter build apk --release` produces a locally signed APK for sideloading; before sharing across devices or updating installs, configure a stable signing key held outside the repository. No APK is published as part of the design/planning work. This avoids Play Store review overhead for a personal project.

## 6. Lifecycle & Background Behavior

**Lifecycle update:** The approved [capture-coordinator design](2026-10-02-capture-lifecycle-coordinator-design.md) supersedes the earlier Settings, rotation, and `inactive` stop policy in this document. It also adds a read-only native session-health query and an app-owned capture coordinator; the simplified architecture diagram below predates those details.

**Decision: Foreground-only. The app listens and keeps the screen awake while open and visible; it stops listening when backgrounded or the screen locks.**

This matches the actual use case (someone holds up or props the phone to read captions in real time) and removes an entire category of Android complexity that LiveTranscribe-Android needed for its "overlay on other apps" use case: no foreground `Service`, no persistent notification, no `MediaProjection`, no background-execution Flutter plugin.

- Screen-keep-awake is handled with `wakelock_plus` while a foreground recognition session is running, including when the in-app Settings route is visible.
- Rotation, font changes, in-app Settings and a brief `inactive` state preserve an existing session; only selecting a different recognition language changes models. New starts require confirmed foreground `resumed` and fresh microphone permission. True background/lock/system Settings (`paused`/`hidden`/`detached`) stops capture; foreground return checks native logical session health before restarting a lost session.

## 7. History / Persistence

**Decision: No transcript history. Captions are ephemeral — visible only during the live session, gone when the app closes.**

Keeps the MVP free of local-storage, deletion-UX, and privacy-notice concerns for what could be sensitive recorded conversations. The only persisted state is user preferences (font size, selected language, orientation lock, enabled-languages list) via `shared_preferences`.

## 8. Architecture & Data Flow

```
┌─────────────────────────────────────────────┐
│  UI (Flutter widgets)                        │
│  - Main caption screen (3 permission states) │
│  - Settings screen (language list)           │
└───────────────────┬───────────────────────────┘
                     │ listens to
┌───────────────────▼───────────────────────────┐
│  CaptionController (ChangeNotifier)            │
│  - holds: current text (partial/final),        │
│    listening state, font size, current         │
│    language, error state                       │
│  - logic: auto-retry on stream failure,         │
│    rebuild recognizer on language switch        │
└───────────────────┬───────────────────────────┘
                     │ calls
┌───────────────────▼───────────────────────────┐
│  SpeechEngine (interface, owned by this app)   │
│  start(lang) / stop() / dispose()              │
│  Stream<SpeechEvent> (partial/final/error)     │
└───────────────────┬───────────────────────────┘
                     │ implemented by
┌───────────────────▼───────────────────────────┐
│  VoskSpeechEngine (Dart Android adapter)       │
│  Kotlin bridge → official Vosk Android AAR:   │
│  mic + streaming, one model per language       │
└─────────────────────────────────────────────────┘
```

`SpeechEngine` is the single architectural seam of this app: everything above it (UI, `CaptionController`) is independent of the Kotlin bridge and recognition backend. Adding an iOS implementation (platform speech API or Vosk-on-iOS), or eventually adding a cloud-fallback engine, means writing a new `SpeechEngine` implementation without changing UI or app state.

## 9. UX & Screens

Two screens total.

### Main caption screen (full-screen, no title bar)

Renders one of three states based on microphone permission:

1. **Not yet granted / denied once** — short explanation text + large "开始" button. Tapping it triggers the OS's native permission dialog (this app never draws its own permission popup).
2. **Permanently denied** — same layout, button reads "去设置开启权限" and deep-links to the system app settings page.
3. **Granted** — live caption view: large centered text, partial results in a lighter/gray shade, final results in high-contrast black/white. Dark background by default (reduces eye strain for prolonged reading, standard captioning convention). No light theme in phase 1.

Bottom button bar (5 buttons, large touch targets):
- `A+` / `A-` — font size, stepped presets (e.g. 32/48/64/80sp), not a continuous slider.
- **Language switch** — disabled when only 1 language is enabled, one-tap toggle when exactly 2 are enabled in settings, and a dropdown/list picker when 3+ are enabled. Settings does not allow disabling the final enabled language. Switching shows a brief "切换中…" indicator and does **not** clear the last-shown caption text while the new recognizer initializes.
- **Orientation lock** — manually forces portrait or landscape via `SystemChrome.setPreferredOrientations`, independent of system auto-rotate; last choice persisted.
- **Settings** (gear icon) — opens the settings screen.

### Settings screen (minimal)

- A checklist of installed languages (phase 1: Chinese, English) controlling which ones appear in the main screen's language switch. This list is the intended mounting point for a future language-pack downloader — no other settings in phase 1.

## 10. Error Handling

| Scenario | Behavior |
|---|---|
| Microphone permission denied / permanently denied | Covered by main-screen states 1/2 above. |
| Vosk model fails to load (corrupt asset, etc.) | Show "识别引擎初始化失败" + retry button. No crash. |
| Recognition stream errors or drops mid-session | `CaptionController` retries rebuilding `SpeechEngine` a bounded number of times with backoff. Last displayed caption text is preserved throughout — never blanks the screen. After exhausting retries, show a small, non-intrusive status indicator (not a blocking dialog) with a manual retry affordance. |
| Language switch fails to load new model | Revert to the previous language, show a brief "切换失败" message. Never leaves the app in a half-switched state. |

## 11. Testing Strategy

- **Unit tests**: `CaptionController` against a fake `SpeechEngine` — partial/final event handling, language-switch logic, retry/backoff behavior. Pure Dart, no native dependency.
- **Widget tests**: main screen renders correctly in each of the 3 permission states; buttons invoke the expected controller methods.
- **Android native tests**: model extraction's partial/corrupt archive behavior; session lifecycle and event mapping where an injectable fake makes those independent of real microphone hardware.
- **Emulator and real-device testing (required, not optional)**: first perform a narrow Android native-ASR proof of concept (continuous partial/final if host microphone is available, background/lock stop, restart, language switch) on a locally installed Android Studio AVD before building the full UI. Real-device testing is still required for actual recognition accuracy/latency, wakelock behavior, perceived language-switch delay, battery/thermal behavior and orientation lock — none is meaningfully verifiable through Dart unit tests alone or a microphone-less emulator.
- Prefer mocked speech events and unit/widget tests for failure paths. Keep emulator/phone checks to short native-permission/recognition smoke tests rather than adding a complex integration-test harness. No CI pipeline or automated native-plugin testing in phase 1 (personal, side-loaded project — YAGNI).

## 12. Explicit Non-Goals (Phase 1)

- iOS build (interface is ready for it; not implemented).
- Downloadable language packs beyond the two bundled languages.
- Text translation (planned for later, online-only).
- Transcript history / save / share.
- Pause/resume control (removed per explicit feedback — only font size, language, orientation, and settings buttons exist).
- Play Store distribution, monetization, telemetry/analytics, crash reporting.
- Background/lock-screen operation.

## 13. Open Risks

- **Native integration and device behavior**: The app-owned Kotlin bridge, AAR `0.3.75`, model extraction and Android lifecycle need a narrow, real-device proof of concept before broad UI implementation. Validate continuous partial/final, release on background/lock, restart, language switching and older/low-end Android behavior. No runtime reliability claim is made from source inspection alone.
- **Model distribution**: Verify license and redistribution notices for the exact bundled English and Chinese model artifacts independently of the Vosk API's Apache-2.0 code license. Test free-space and interrupted extraction into app-private storage.
- **ASR accuracy for the target use case**: Vosk's small/offline models trade accuracy for size versus cloud ASR. Since the target users are hearing-impaired and relying on captions to understand speech, recognition errors are more consequential than in a casual-use app. This needs real-device validation with actual elderly users/speech patterns, not just spec-level sign-off.
- **APK size**: bundling two Vosk models (~30-80MB each for small models) adds meaningfully to APK size. Acceptable for a side-loaded personal app; would need reconsideration if ever distributed more broadly.
