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

**Integration approach: use an existing community-maintained Flutter plugin (`vosk_flutter_service`) rather than writing a custom platform channel.**

Vosk has an official Dart/Flutter binding lineage (`alphacep/vosk-flutter` → community forks). Of the options evaluated (`vosk_flutter`, `vosk_flutter_2`, `vosk_flutter_service`), **`vosk_flutter_service`** was chosen as the most actively maintained at design time. It installs native Vosk binaries via a CLI step (`dart run vosk_flutter_service install -t android`) rather than bundling them in the plugin itself.

This is wrapped behind our own `SpeechEngine` interface (see Architecture) specifically so that:
- If `vosk_flutter_service`'s maintenance status changes, swapping to another Vosk binding — or a hand-rolled native platform channel — touches only the adapter, not app logic.
- The same interface is the seam for an eventual iOS implementation.

**Rejected alternative:** hand-written native platform channel (Kotlin, calling Vosk's Android AAR directly, mirroring LiveTranscribe-Android's `StreamingSttEngine`). Gives maximum control over chunking/threading/latency, but re-implements work an existing plugin already does. Deferred as a fallback if `vosk_flutter_service`'s recognition latency/quality proves inadequate.

## 4. Language Scope

**Decision: Phase 1 ships Chinese (Mandarin) and English only, both bundled in the APK as assets. Architecture is designed for future extensibility (downloadable language packs, online translation), but phase 1 does not implement either.**

- Both Vosk models are packaged as Flutter assets — no first-run download, no network dependency, consistent with the offline-first design goal.
- The settings screen's "available languages" list is designed as the same extension point a future language-pack downloader would populate — phase 1 just doesn't wire up a downloader behind it.
- Translation (text-to-text, e.g. for a non-native speaker reading captions in another language) is explicitly **out of scope for phase 1** and will require network connectivity when it's built later — not attempted offline.

## 5. Distribution

**Decision: Side-loaded APK only. No Play Store, no monetization.**

`flutter build apk` produces an unsigned/self-signed release APK shared directly. This avoids Play Store review overhead (privacy policy, permission justification, etc.) for what is a personal project.

## 6. Lifecycle & Background Behavior

**Decision: Foreground-only. The app listens and keeps the screen awake while open and visible; it stops listening when backgrounded or the screen locks.**

This matches the actual use case (someone holds up or props the phone to read captions in real time) and removes an entire category of Android complexity that LiveTranscribe-Android needed for its "overlay on other apps" use case: no foreground `Service`, no persistent notification, no `MediaProjection`, no background-execution Flutter plugin.

- Screen-keep-awake is handled with a wakelock plugin (e.g. `wakelock_plus`), enabled while the main screen is active and recognition is running.
- Recognition starts/stops tied to the main screen's lifecycle (`resumed` → start, `paused`/`inactive` → stop).

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
│  start() / stop() / setLanguage(lang)          │
│  Stream<CaptionEvent> (partial/final text)     │
└───────────────────┬───────────────────────────┘
                     │ implemented by
┌───────────────────▼───────────────────────────┐
│  VoskSpeechEngine (adapter)                    │
│  Wraps vosk_flutter_service: mic capture +     │
│  streaming recognition, one model per language │
└─────────────────────────────────────────────────┘
```

`SpeechEngine` is the single architectural seam of this app: everything above it (UI, `CaptionController`) is plugin- and platform-agnostic. Replacing the ASR plugin, adding an iOS implementation (native `SFSpeechRecognizer` or Vosk-on-iOS via the same plugin), or eventually adding a cloud-fallback engine all mean writing a new `SpeechEngine` implementation — no changes above that line.

## 9. UX & Screens

Two screens total.

### Main caption screen (full-screen, no title bar)

Renders one of three states based on microphone permission:

1. **Not yet granted / denied once** — short explanation text + large "开始" button. Tapping it triggers the OS's native permission dialog (this app never draws its own permission popup).
2. **Permanently denied** — same layout, button reads "去设置开启权限" and deep-links to the system app settings page.
3. **Granted** — live caption view: large centered text, partial results in a lighter/gray shade, final results in high-contrast black/white. Dark background by default (reduces eye strain for prolonged reading, standard captioning convention). No light theme in phase 1.

Bottom button bar (5 buttons, large touch targets):
- `A+` / `A-` — font size, stepped presets (e.g. 32/48/64/80sp), not a continuous slider.
- **Language switch** — one-tap toggle when exactly 2 languages are enabled in settings; becomes a dropdown/list picker when 3+ are enabled. Switching shows a brief "切换中…" indicator and does **not** clear the last-shown caption text while the new recognizer initializes.
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
- **Manual on-device testing (required, not optional)**: actual recognition accuracy/latency, wakelock keeping the screen genuinely awake, perceived language-switch delay, orientation lock — none of this is meaningfully verifiable through automated tests since it depends on real Vosk native behavior on a physical device.
- No CI pipeline or automated native-plugin testing in phase 1 (personal, side-loaded project — YAGNI).

## 12. Explicit Non-Goals (Phase 1)

- iOS build (interface is ready for it; not implemented).
- Downloadable language packs beyond the two bundled languages.
- Text translation (planned for later, online-only).
- Transcript history / save / share.
- Pause/resume control (removed per explicit feedback — only font size, language, orientation, and settings buttons exist).
- Play Store distribution, monetization, telemetry/analytics, crash reporting.
- Background/lock-screen operation.

## 13. Open Risks

- **Plugin maturity**: `vosk_flutter_service` is community-maintained and relatively new; its actual reliability/performance on-device is unverified until implementation. The `SpeechEngine` seam exists specifically to make swapping it out cheap if it doesn't hold up.
- **ASR accuracy for the target use case**: Vosk's small/offline models trade accuracy for size versus cloud ASR. Since the target users are hearing-impaired and relying on captions to understand speech, recognition errors are more consequential than in a casual-use app. This needs real-device validation with actual elderly users/speech patterns, not just spec-level sign-off.
- **APK size**: bundling two Vosk models (~30-80MB each for small models) adds meaningfully to APK size. Acceptable for a side-loaded personal app; would need reconsideration if ever distributed more broadly.
