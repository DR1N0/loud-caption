# Handoff — 2026-10-20, mirror reachability + download stall fixes

> **Update (2026-10-20, later):** the Wi-Fi-only setting was removed. Both
> download entry points (first launch and switching into a translation mode)
> now run a preflight that always checks disk space and checks whether the
> current connection is Wi-Fi; on a non-Wi-Fi connection they explain that the
> download will use mobile data and require confirmation. The extraction phase
> no longer shows a frozen `0.0 MB`: it shows an indeterminate "正在解压…"
> state until real progress exists, then reports bytes as the intermediate tar
> grows. `flutter analyze` is clean and all 172 tests pass. The stale-label
> question below is therefore superseded.

Written because the user is switching network environments and wants to
resume cleanly elsewhere. Covers: what's done and verified, what's done but
only partially verified, and what's still actively broken/open.

## Context: how we got here

This continues a long session that had already shipped v0.0.3 (on-device
translation feature) and three backlog items (Wi-Fi-only downloads,
disk-space preflight, local crash-log export — all committed and pushed,
HEAD is `24f4cde`). The user then resumed real-device testing on a Xiaomi
phone (`houji` / 23127PN0CC) over Wi-Fi ADB, which is why the device's IP
stayed `192.168.1.4` but the port kept changing (34983 → 34263 → ...) each
time Wi-Fi reconnected — **always re-run `adb connect 192.168.1.4:<port>`
and re-check `adb devices -l`** before assuming a stale device ID still
works.

A fresh install (cleared app data) hit a real first-launch failure: the ASR
model download errored out citing `gh-proxy.com` unreachable. Chasing that
down led to three rounds of real fixes, detailed below. **None of this is
committed yet** — see "Uncommitted changes" below.

## What's done and confirmed working on-device

1. **Aggregated download errors.** `downloadAndVerify` used to only
   surface the *last* candidate URL's failure (`throw lastError!`), hiding
   the fact that two other mirrors had also failed for different reasons.
   Now throws one `StateError` listing every candidate's failure. This is
   what first revealed the real problem wasn't just "gh-proxy.com is down"
   — all three original mirrors were failing differently.

2. **Concurrent reachability race.** Mirror reachability turns out to be
   wildly ISP/region-dependent (confirmed directly by the user, who has
   real mainland China network experience) — a GitHub-release proxy that
   works on one network can be fully dead on another, and direct
   `github.com` itself is inconsistently reachable ("有概率可以连通" — the
   user's words). `downloadAndVerify` now races a short concurrent `HEAD`
   request (default 5s timeout) against every candidate URL and tries
   whichever answers first, falling back through the rest in their
   original order only if the winner's real download later fails.

3. **Mirror domain swap.** The original two GitHub-release proxies
   (`ghfast.top`, `gh-proxy.com`) were both **confirmed completely dead**
   from the user's real network (connection timeouts, not just slow).
   Replaced with `gh.monlor.com` and `gh-proxy.org`, which the user
   identified and I verified via `curl` (matching `Content-Length`, and for
   the SenseVoice int8 archive specifically, matching SHA-256 against a
   locally-cached copy) — **important gotcha**: the user's first test URL
   was missing `-int8-` in the filename and downloaded the wrong
   (~900MB, full-precision) model; the correct pinned file is
   `sherpa-onnx-sense-voice-zh-en-ja-ko-yue-**int8**-2024-07-17.tar.bz2`.

4. **Download source shown in UI.** Added `DownloadProgress.source` (the
   winning URL's `Uri.authority`, e.g. `gh.monlor.com` or
   `github.com`), threaded through `ModelDownloadEvent.source` and both
   progress-UI call sites (`ModelDownloadScreen._phaseLabel`,
   `CaptionScreen`'s Hy-MT2 download dialog) as a second line under the
   existing label — explicitly requested by the user so a
   stuck/slow download can be diagnosed without an adb/logcat session.
   **Caveat:** confirmed via code review and widget tests, but I have not
   yet visually confirmed this actually renders correctly on the user's
   device (it requires catching a fresh download in progress, which is
   non-trivial since a successful run completes before you can look).

5. **Stall timeout on the actual data transfer — the real root-cause fix.**
   This is the one that matters most. Real-device testing hit a case where
   the SenseVoice archive downloaded fine but the **separate, independent**
   Silero VAD download (same mirror list, its own HTTP connection — see
   "Important misconception" below) silently stalled at exactly 0 bytes
   forever: `adb shell run-as app.loudcaption.loud_caption ls -la
   files/silero-vad/` showed a `silero_vad.onnx.part` file that existed but
   never grew, and `adb shell top -H -p <pid>` confirmed the relevant
   DartWorker thread's CPU time was completely flat (not just slow — truly
   idle/blocked). Root cause: `httpClient.connectionTimeout` only bounds
   the **TCP handshake**. Once connected, there was no timeout at all on
   (a) waiting for response headers, or (b) waiting for body bytes to keep
   arriving. A mirror that accepts the connection and even returns headers,
   then goes completely silent, would hang forever with zero recovery.
   Fixed via a new `stallTimeout` parameter (default 20s) on
   `downloadAndVerify`/`_downloadOnce`, applied at both stages:
   `request.close().timeout(stallTimeout)` for the header wait, and
   `response.timeout(stallTimeout)` for the body stream (this resets on
   every chunk, not once for the whole transfer, so a slow-but-steady
   download is never penalized — only genuine silence triggers it).
   **This was validated by a second real-device test**: after rebuilding
   with this fix and reinstalling, the same previously-permanently-stuck
   VAD download actually completed this time (`silero_vad.onnx` now exists
   without the `.part` suffix, confirmed via `run-as`), and the app moved
   past the download gate into normal use (confirmed via logcat showing
   back-button interaction ~4.5 minutes after app launch). It was slow, not
   instant, but it no longer hangs forever.

## Important misconception to not repeat

The user asked mid-session: "since VAD and SenseVoice are downloaded as one
package, why would only one of them fail?" **They are not one package.**
`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2` (a GitHub
release asset) contains only `model.int8.onnx` + `tokens.txt`.
`silero_vad.onnx` is a separate, independent file in the same release,
downloaded via its own separate `downloadAndVerify` call with its own
independent reachability race and HTTP connection — fully explaining why
one can succeed while the other stalls. See
`lib/speech/sense_voice_model_download.dart`'s `downloadSenseVoiceModel`
for the two sequential steps.

## Open / unconfirmed issue: possibly-stale "解压模型中…" label

On the run where the VAD stall actually recovered and completed, the user
reported the UI appeared to stay on "解压模型中…" (extracting — the
*middle* of three phases) the whole time, rather than visibly cycling
through "下载语音识别模型中…" → "解压模型中…" → "下载降噪模型中…" as the
pipeline actually progressed through archive download → extraction → VAD
download. This **was not yet investigated**. Two live hypotheses, not yet
distinguished:

1. Genuinely benign: the archive step was fast enough this run that the
   user just didn't register seeing the first label before extraction's
   label appeared, and extraction (`Isolate.run`, pure-Dart bzip2 decode of
   a 164MB archive — known to be slow on real device CPUs, no native
   decoder) plus the following VAD download together felt like one long
   "stuck at 解压模型中" stretch even though the label *did* eventually
   change to "下载降噪模型中…" partway through (user may just not have
   looked at the exact wording again once accustomed to seeing "stuck").
2. A real bug: `ModelDownloadScreen`'s `StreamSubscription.listen` /
   `setState` isn't correctly propagating the `downloadingVad` phase event
   after extraction, so the label visually freezes on "解压模型中…" even
   while the VAD download is actually progressing in the background,
   finally snapping to whatever screen comes after `onReady()` once
   complete — the "突然完成了" ("suddenly finished") phrasing is at least
   suggestive of this.

**Next step**: reproduce with the device attached, start a fresh download
(clear app data or delete the `files/sense-voice` + `files/silero-vad`
dirs via `adb shell run-as app.loudcaption.loud_caption rm -rf
files/sense-voice files/silero-vad`), and watch the label text transition
in real time (or pull `ModelDownloadEvent`s via a temporary debugPrint, or
screen-record) across all three phases to confirm whether the label
actually updates or genuinely freezes.

## Known limitation accepted, not a bug to fix

No Hugging Face mirror was added for the SenseVoice files despite
investigating it at length. Findings, so this isn't re-investigated from
scratch next time:

- `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` on HF
  hosts `model.int8.onnx` + `tokens.txt` **individually** (no combined
  archive) and is confirmed byte-identical via SHA-256 to our pinned
  archive's extracted contents.
- Despite being stored via HF's newer "Xet" storage backend, a plain
  `curl -L` to the `resolve/main/<file>` URL **does** work (via both
  `huggingface.co` directly and `hf-mirror.com`) — the final redirect lands
  on a presigned, directly-fetchable URL, no special Xet client protocol
  actually required. (An earlier belief that Xet blocks plain HTTP `GET`
  was wrong — `curl -I` / HEAD-only requests behave differently than a real
  `GET` against this backend and gave a false negative.)
- Not adopted anyway because doing so means restructuring
  `downloadSenseVoiceModel` away from "download one `.tar.bz2`, extract two
  files" toward **per-file sources** (HF has no combined archive) — a real
  architecture change, not a URL swap. Also, `huggingface.co` direct was
  itself unreliable in testing (hit a mid-download timeout), consistent
  with this project's existing experience with HF from mainland China.
- `silero_vad.onnx` specifically has **no verified HF mirror at all** — the
  HF copies found (`csukuangfj/vad`, etc.) are a different, newer Silero
  version (1.8MB vs. our pinned 643,854 bytes, different SHA-256) and would
  need separate vetting before ever being considered.

If this comes up again: don't re-investigate HF as a mirror for these
files unless the user explicitly wants the archive-vs-per-file
restructuring work, which was never commissioned.

## Uncommitted changes — needs a commit once the stale-label question is resolved

```
 M docs/model-sources.md
 M lib/downloads/model_downloader.dart
 M lib/speech/sense_voice_model_download.dart
 M lib/ui/caption_screen.dart
 M lib/ui/model_download_screen.dart
 M test/downloads/model_downloader_test.dart
?? build_cache/   (an actual downloaded model archive, NOT meant to be committed — do not `git add -A`)
```

- `flutter analyze`: clean.
- `flutter test`: 171/171 passing (was 170 before this round's new stall
  test was added).
- HEAD is still `24f4cde` (last pushed commit) — nothing from this session
  has been committed or pushed.
- Suggested commit message once ready: something like "Add concurrent
  mirror-reachability racing and stall detection to model downloads" —
  should mention the aggregated errors, the reachability race, the mirror
  domain swap (and why), the source-in-UI display, and the stall timeout,
  since these are one cohesive fix even though they were discovered in
  stages.

## Device/testing environment notes for the next session

- Phone: Xiaomi `houji` (23127PN0CC), connected over Wi-Fi ADB. IP
  `192.168.1.4` is stable but the **port changes on every Wi-Fi
  reconnect** — always `adb connect 192.168.1.4:<new-port>` first.
- Build+install workflow that actually works reliably:
  `flutter build apk --debug` (NOT `flutter install`, which silently
  reuses whatever APK is already on disk without rebuilding — this bit us
  once this session, wasting a full test cycle on a stale build) then
  `adb -s <device> install -r build/app/outputs/flutter-apk/app-debug.apk`
  (plain `adb install -r`, not `flutter install`, to avoid an unnecessary
  uninstall — the user explicitly asked not to lose app data between
  rounds).
- MIUI sometimes requires a manual tap-to-confirm on the phone screen for
  ADB-initiated installs ("Install canceled by user" if missed) — if an
  install fails with that error, just ask the user to check their screen
  and retry.
- Useful on-device inspection commands used this session (app is
  debuggable, so `run-as` works without root):
  - `adb shell run-as app.loudcaption.loud_caption find files -maxdepth 4`
    — check which model files actually exist and their `.part` state.
  - `adb shell top -H -n 1 -b -p <pid>` — per-thread CPU time, the key
    diagnostic that distinguished "genuinely stuck" (flat CPU time across
    repeated samples) from "slow but working."
  - `adb shell logcat -d --pid=<pid> -t <N>` — recent app-process logs;
    note the app has no custom debugPrint/logging around the download
    pipeline, so logcat alone won't show which phase/URL is active — that
    gap is exactly what the new `DownloadProgress.source` UI label is
    meant to close going forward.
