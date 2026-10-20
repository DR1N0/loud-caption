# Testing

## Automated

```bash
flutter analyze
flutter test
```

CI runs both on every push and pull request. The test suite covers download
verification/fallback, settings persistence, caption lifecycle, translation
download gates, the download/extraction UI, and Chinese/English rendering.

## Manual release smoke test

Run on a physical Android phone before attaching release artifacts:

- [ ] **0.0.4 only:** uninstall 0.0.3 once, install 0.0.4, and confirm the
      models download again under `app.loudcaption`.
- [ ] Subsequent releases: install over the previous release without
      uninstalling; app data survives.
- [ ] First launch with Wi-Fi: model download starts, shows progress, extracts,
      and reaches the caption screen.
- [ ] First launch with Wi-Fi off: mobile-data confirmation appears; cancel
      leaves a retry path; confirm starts the download.
- [ ] Switching into 翻译/互译 with the translation model missing shows the
      download confirmation; declining returns to 字幕 mode.
- [ ] Live captions update in quiet and noisy rooms; committed lines scroll and
      can be reviewed by scrolling up.
- [ ] Large font (80 px), landscape, theme toggle, and settings changes do not
      stop recognition.
- [ ] Settings → App language: switching 中文/English updates the UI and
      semantics immediately, survives a restart, and "Follow system" tracks the
      device language.
- [ ] Backgrounding, locking the screen, and returning behave as documented.
- [ ] Translation produces readable output in both translation modes.
- [ ] No crash, ANR, or silent capture stop during a 30-minute session.

## Performance stance

There is **no formal battery or thermal benchmark gate**. Both current test
phones (the author's and the grandfather's) run the app without visible thermal
or battery problems, comparable to other continuously-running apps. Formal
measurements are only worth taking when:

- a user reports heat, drain, or throttling;
- a change adds sustained load (for example background translation, a larger
  model, or continuous partial translation); or
- a release is being prepared for a wider audience and a regression is
  suspected.

In those cases, use a 30-minute session and record battery percentage and
device temperature before/after; do not add telemetry to the app.
