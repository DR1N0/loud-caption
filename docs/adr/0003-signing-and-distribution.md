# ADR 0003 — Sign sideload builds with a public, committed key

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The project is distributed as a sideloaded APK through GitHub Releases, not
through Google Play. Debug and release builds must be able to install over each
other without an uninstall, and future builds must be accepted as updates of
older installs on users' phones. The project is non-commercial and personal.

## Decision

Use one project-specific signing key for debug and release builds, and commit
the keystore to the repository. Distribute through GitHub Releases and
Obtainium. Do not use Play App Signing.

## Consequences

- The key is public. Anyone with the repository can produce an APK that Android
  accepts as an update to an existing install. This is an accepted risk for a
  personal, non-commercial, sideload-only project; it is not a template for a
  commercial or Play-distributed app.
- Users can move between debug and release builds without uninstalling and
  losing app data.
- If the app ever moves to Google Play, it needs a separate, private upload key
  and Play App Signing; this ADR would be superseded.
- Obtainium can follow GitHub Releases because the APK is attached to each
  release with a stable name and checksum.
