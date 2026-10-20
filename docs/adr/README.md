# Architecture decision records

ADRs record decisions that are expensive to reverse. They describe **why**;
[architecture.md](../architecture.md) describes **what exists now**.

| ADR | Decision |
|---|---|
| [0001](0001-offline-models.md) | Run ASR and translation on-device; no cloud fallback |
| [0002](0002-model-downloads.md) | Pin model files, verify checksums, resume downloads |
| [0003](0003-signing-and-distribution.md) | Use a public committed key for sideload builds |
| [0004](0004-internationalization.md) | Ship Chinese/English first; keep model prompt names stable |

To change a decision, add a new ADR that supersedes the old one; do not rewrite
history.
