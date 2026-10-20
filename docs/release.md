# Release and signing

## Application identity

- Android application ID: **`app.loudcaption`**
- Reserved iOS bundle ID: **`app.loudcaption`**
- The 0.0.3 Android package was `app.loudcaption.loud_caption`. Because the
  application ID changed, 0.0.3 cannot be updated in place: uninstall it once
  before installing 0.0.4.

Changing the application ID after a public release is deliberately avoided;
this is the 0.0.4 migration to a store-compatible identity.

## Signing key

Release builds are signed with a **private upload key**:

- Keystore: `android/keystore/loud-caption-upload.jks`
- Local properties: `android/key.properties`
- Both are git-ignored. Never commit either file, and never paste the
  passwords into an issue or a release note.

The key is backed up outside the repository. If it is lost, existing installs
cannot receive an update signed with the same identity; there is no Play App
Signing key-rotation fallback yet.

`android/key.properties` has this shape:

```properties
storeFile=../keystore/loud-caption-upload.jks
storePassword=<secret>
keyAlias=loud_caption_upload
keyPassword=<secret>
```

The values can instead come from `ANDROID_KEYSTORE_PATH`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and
`ANDROID_KEY_PASSWORD` environment variables.

## Local release build

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
flutter build appbundle --release --target-platform android-arm64
```

Verify the signer before publishing:

```bash
apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The certificate SHA-256 must be the upload key's certificate, not a debug key.

## GitHub Actions

The release workflow needs these repository secrets:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of `loud-caption-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

The workflow decodes the keystore into `$RUNNER_TEMP` (never the workspace),
builds a signed APK and AAB, and attaches both plus `SHA256SUMS` to the GitHub
Release. The tag must be `v<version>` matching `pubspec.yaml` (for 0.0.4,
`v0.0.4`).

## Replacing the key

Only do this together with a new application ID, or every installed user will
be unable to update. Place the replacement keystore outside the repository,
update `android/key.properties` locally, and replace all four GitHub secrets.
