# ADR 0001 — Run speech recognition and translation on-device

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The app is built for people who can hear sound but struggle to make out
speech, including the author's grandfather. Conversations are personal and
often happen in places with unreliable connectivity. A cloud recognizer would
add latency, cost, and a privacy boundary that the target user cannot audit.

## Decision

Use on-device models only:

- SenseVoice int8 for speech recognition (Chinese, English, Japanese, Korean,
  Cantonese, automatic language detection).
- Silero VAD for speech segmentation.
- Hy-MT2-1.8B Q4_K_M through llama.cpp for optional translation.

There is no cloud fallback and no account system.

## Consequences

- First launch downloads ~240 MB of ASR/VAD models; translation adds a ~1.08 GB
  download on first use.
- Inference competes for phone CPU and memory; latency and thermals are device
  dependent.
- Model licenses are separate from the app's MIT code license. See
  [model-sources.md](../model-sources.md).
- The app can work with no network after the models are installed, which is a
  core product promise rather than an implementation detail.
