# ADR 0006 — Private upload key and store-compatible application ID

- **Status:** Accepted
- **Date:** 2026-10-20
- **Supersedes:** [ADR 0003](0003-signing-and-distribution.md)

## Context

ADR 0003 used a public keystore committed to the repository so any machine
could produce update-compatible sideload builds. That was acceptable while the
project had no store plans and the package was
`app.loudcaption.loud_caption`.

The owner now wants to keep the option of Google Play or App Store
distribution open. A public signing key cannot be used for Play uploads, and a
package name cannot change after the first Play release. The iOS bundle ID also
cannot contain the underscore in the old Android application ID.

The project has only two users today, so a one-time reinstall is acceptable.

## Decision

- Use **`app.loudcaption`** as the Android application ID and reserved iOS
  bundle ID. Version 0.0.4 is the migration release; existing 0.0.3 installs
  must be uninstalled once.
- Sign release builds with a **private upload keystore**:
  - local: `android/keystore/loud-caption-upload.jks` plus git-ignored
    `android/key.properties`;
  - CI: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
    `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` repository secrets.
- Never commit the keystore or its passwords. Back the key up outside the
  repository.
- Build both a signed APK for Obtainium/GitHub and a signed AAB for a future
  Play upload.
- Keep debug and release installable over each other **locally** by using the
  local upload key for debug when `key.properties` is present; without it,
  debug falls back to the standard debug key.

## Consequences

- 0.0.3 cannot update in place; the owner and family reinstall once and
  re-download the models.
- If the upload key is lost, existing installs cannot receive a same-identity
  update. There is no Play App Signing key-rotation fallback yet, so the key
  must be backed up.
- The old public key remains in Git history but only signs the retired
  `app.loudcaption.loud_caption` package; it must not be reused.
- Forks need their own key material to produce signed release builds. This is
  intentional: a release signed with someone else's key is not trustworthy.
- The release workflow now requires the four secrets. Unsigned local release
  builds are possible only if the signing properties are absent, and must not
  be published.
- This keeps the option open for Play App Signing and an iOS bundle without
  renaming the app again. iOS distribution itself remains undecided.
