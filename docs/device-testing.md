# Device testing

## Current devices

- Development phone: Xiaomi `houji` (23127PN0CC), MIUI.
- Second phone: the author's grandfather's device. Both phones have run the app
  in normal conversation without visible thermal or battery problems.

## Wireless ADB

The phone's IP (`192.168.1.4`) is stable, but the wireless-debugging **port
changes every time Wi-Fi reconnects**. Always reconnect and re-check:

```bash
adb connect 192.168.1.4:<port>
adb devices -l
```

Two transports may appear for the same phone (IP and mDNS). Use `-s` with the
IP transport for all commands.

Wireless ADB dies when Wi-Fi is disabled or the phone sleeps. Before a test:

```bash
adb shell svc power stayon true
adb shell settings put system screen_off_timeout 600000
```

If you are testing the mobile-data prompt, do **not** disable Wi-Fi while
relying on wireless ADB: you will lose the connection. Use a scheduled
re-enable on the phone, or test that path over USB.

## Build and install

Build the exact artifact you want to test, then install it explicitly:

```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi
adb -s <serial> install -r \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

- Do **not** use `flutter install`: it can reuse an existing APK without
  rebuilding, which has caused stale-build test cycles.
- Use `adb install -r`, not an uninstall/reinstall, to preserve app data.
- Debug and release builds share the local upload key when
  `android/key.properties` is present, so they can replace each other without
  an uninstall. Without a local key, debug uses the standard debug key and
  cannot replace a release install.
- MIUI may require an on-screen confirmation for ADB installs. If the install
  reports "Install canceled by user", check the phone screen and retry.
- Install the **release** APK when capturing README screenshots, so the debug
  banner is absent.

## On-device inspection

```bash
# App-private model files (debug build / run-as capable)
adb shell run-as app.loudcaption ls -la files
adb shell run-as app.loudcaption ls -la files/sense-voice
adb shell run-as app.loudcaption ls -la files/silero-vad

# Per-thread CPU time: distinguishes a genuine stall from slow work
adb shell top -H -n 1 -b -p <pid>

# Recent app logs
adb shell logcat -d --pid=<pid> -t 200

# Screenshot / UI dump for debugging the current screen
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png
adb shell uiautomator dump /sdcard/ui.xml
```

`run-as` requires a debuggable build. Model files are installed through
`.part` + atomic rename, so a leftover `.part` means an interrupted download or
extraction, not a usable model.

## What to test

Follow [testing.md](testing.md). For screenshots, see
[assets/README.md](assets/README.md).
