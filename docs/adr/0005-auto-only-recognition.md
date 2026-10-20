# ADR 0005 — Use SenseVoice auto language detection; do not offer a language override

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

SenseVoice occasionally misdetects strongly accented or slurred speech as a
different language. The app briefly exposed a "recognition language" setting
that passed `zh`/`en`/`ja`/`ko`/`yue` to SenseVoice's `language` field.

Evidence that this cannot enforce a language:

- The sherpa-onnx maintainer states in
  [k2-fsa/sherpa-onnx#1659](https://github.com/k2-fsa/sherpa-onnx/issues/1659)
  that only initialization can set the language, and that in practice
  "specifying en can still recognize Cantonese; it doesn't matter much, use
  auto".
- A controlled comparison with the same pinned model and clean Chinese/English
  audio produced identical text and detected language for `auto`, `zh`, `en`,
  and `ja`. The field is a weak hint at most, not a hard constraint.
- The same complaint appears in the upstream SenseVoice tracker
  ([QwenAudio/SenseVoice#72](https://github.com/QwenAudio/SenseVoice/issues/72)).

Keeping the setting implied a guarantee the model cannot make.

## Decision

Remove the recognition-language setting, its persistence, and the engine
config seam that existed only to support it. Always initialize SenseVoice with
`language: 'auto'`; continue to use the model's detected language only for
per-source translation routing.

## Consequences

- Settings are simpler and no longer promise behavior the model cannot provide.
- Strong accents can still be misdetected; that is a model limitation, not a
  UI toggle. A future ASR model that genuinely supports a hard language
  constraint can reintroduce the setting, backed by an on-device test showing
  the output language actually changes.
