# Architecture decision records

ADRs record decisions that are expensive to reverse. They describe **why**;
[architecture.md](../architecture.md) describes **what exists now**.

| ADR | Decision |
|---|---|
| [0001](0001-offline-models.md) | Run ASR and translation on-device; no cloud fallback |
| [0002](0002-model-downloads.md) | Pin model files, verify checksums, resume downloads |
| [0003](0003-signing-and-distribution.md) | ~~Use a public committed key for sideload builds~~ (superseded by 0006) |
| [0004](0004-internationalization.md) | Ship Chinese/English first; keep model prompt names stable |
| [0005](0005-auto-only-recognition.md) | Use SenseVoice auto language detection; no unreliable override |
| [0006](0006-private-signing.md) | Private upload key, `app.loudcaption` ID, signed APK + AAB |

To change a decision, add a new ADR that supersedes the old one; do not rewrite
history.
