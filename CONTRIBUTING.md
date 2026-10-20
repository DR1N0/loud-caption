# Contributing

Thanks for trying Loud Caption. This is a small, non-commercial project with a
deliberately narrow scope: **offline, large, low-friction captions for people
who struggle to make out speech**.

## Before opening a PR

- Open an issue first for anything larger than a typo, a small bug fix, or a
  translation update. Architecture changes are easier to discuss before code.
- Run `make check` (or `flutter analyze && flutter test`) and keep it green.
- Keep the change focused; do not mix refactors, dependency bumps, and features
  in one PR.
- Do not add accounts, cloud sync, analytics, telemetry, or a cloud ASR fallback.
  Offline operation is a product constraint, not an implementation detail.

## Bug reports

Use the bug report template and include:

- app release/version (`v0.0.x`) and install source;
- phone model and Android version;
- whether the bug happens on Wi-Fi, mobile data, or both;
- steps to reproduce, expected/actual behavior;
- a screenshot or a short screen recording if the UI is involved.

Do **not** attach private conversations. A staged reproduction is enough.

## Documentation policy

- `docs/architecture.md` and `docs/adr/` are stable, descriptive documents.
  Update them only when a module boundary, data flow, or accepted decision
  changes.
- Dated plans, scratch notes, and agent-generated specs stay in the git-ignored
  `docs/plans/` directory. They are not published because they go stale.
- Model changes must update `docs/model-sources.md`, checksums, mirrors, and
  tests together.

## Localization

The UI is being prepared for Chinese and English first. Add new strings to both
ARB files, and keep model prompt names separate from localized display names
(see ADR 0004).

## Signing

The committed keystore is intentionally public and only suitable for this
sideload-only project. Do not reuse it for another app, and do not move this
app to Google Play without a separate private upload key and Play App Signing.
