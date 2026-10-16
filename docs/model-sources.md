# Offline sherpa-onnx model sources

The app uses two sherpa-onnx model files — a SenseVoice ASR model and a Silero VAD model. They are **not** bundled in the APK; instead, `lib/speech/sense_voice_model_download.dart` downloads, checksum-verifies, and installs them into app-private storage the first time the app runs, blocking on a dedicated download screen until that completes. This keeps the installable APK small (previously ~198MB with both models bundled) at the cost of requiring a network connection on first launch.

| Component | Archive / file | Download size | Installed size | Pinned SHA-256 | License |
| --- | --- | --- | --- | --- | --- |
| SenseVoice ASR (zh/en/ja/ko/yue, int8) | [`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2) → `model.int8.onnx` + `tokens.txt` | 163,002,883 bytes (~155 MiB / ~164 MB) | `model.int8.onnx` 239,233,841 bytes + `tokens.txt` 315,894 bytes ≈ 239,549,735 bytes (~228 MiB / ~240 MB) | `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e` (archive) | FunASR Model Open Source License Agreement v1.1 (weights) |
| Silero VAD v4 | [`silero_vad.onnx`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx) | 643,854 bytes | 643,854 bytes | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` | MIT |

Authoritative source for both files: the `asr-models` release of <https://github.com/k2-fsa/sherpa-onnx>.

The SenseVoice row has two meaningfully different sizes: the `.tar.bz2` archive is compressed (~164 MB), but only `model.int8.onnx` and `tokens.txt` are extracted from it and installed — those extracted files are larger on disk (~240 MB combined) because the archive is bzip2-compressed.

## Download, verification, and installation

`lib/downloads/model_downloader.dart` streams each file to a sibling `.part` file while incrementally computing its SHA-256, then atomically renames it into place only once the digest matches the pinned value above — an interrupted or corrupted download never leaves a partial or bad file at the final path, and a relaunch simply restarts cleanly. `lib/speech/sense_voice_model_download.dart` orchestrates the SenseVoice-specific steps: download the `.tar.bz2` archive to scratch storage, verify it, extract (via `package:archive`, off the UI isolate) the two files actually needed, discard the archive, then download and verify Silero VAD directly to its final destination (no extraction needed — it's already a single file).

Because the installed files are the same flat `model.int8.onnx`/`tokens.txt`/`silero_vad.onnx` either way, on-device storage footprint is unchanged from the old bundled-asset approach: approximately 240 MB (SenseVoice) + 0.6 MB (Silero VAD) ≈ 240 MB, now paid at first launch instead of at install time.

`isSenseVoiceModelReady()` checks only that these files exist at their fixed destination paths — it does not re-verify their SHA-256 on every app launch, since the only way a file can land at that path is via the atomic verify-then-rename sequence above.

## License and redistribution notice

sherpa-onnx itself (the `k2-fsa/sherpa-onnx` project and the `sherpa_onnx` Flutter package built on it) is Apache-2.0: <https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE>. This is the code license and is independent of the licenses governing the two downloaded model files below — the same "model license ≠ code license" distinction this document previously drew for the Vosk API and its models.

The SenseVoice ONNX export (`model.int8.onnx` + `tokens.txt`) is a converted/quantized derivative of Alibaba's FunASR SenseVoice model, per that model's own Hugging Face model card. The weights are therefore governed by the **FunASR Model Open Source License Agreement v1.1**, not by sherpa-onnx's Apache-2.0 code license — attribution and the retained model name are required by that license's terms. The full text is reproduced in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

The Silero VAD model (`silero_vad.onnx`) is MIT-licensed by the Silero Team (<https://github.com/snakers4/silero-vad/blob/master/LICENSE>); the full text is also reproduced in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

This project is distributed as a public GitHub Release. [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) packages the applicable license texts and attribution for sherpa-onnx, the `record` package, the FunASR/SenseVoice model, and the Silero VAD model alongside the APK. Check whether upstream provides any further notices or terms for these exact file versions before a future model-version bump; the license labels above do not establish training-data provenance. Do not infer model-data rights solely from sherpa-onnx's own code license.
