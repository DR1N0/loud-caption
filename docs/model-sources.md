# Offline sherpa-onnx model sources

The Android MVP bundles two sherpa-onnx model files — a SenseVoice ASR model and a Silero VAD model — as Flutter assets. They are downloaded only during developer/build preparation by `python3 scripts/fetch_models.py`; the installed app does not download a model at runtime.

| Component | Archive / file | Bundled as | Download size | Installed size | Pinned SHA-256 | License |
| --- | --- | --- | --- | --- | --- | --- |
| SenseVoice ASR (zh/en/ja/ko/yue, int8) | [`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2) | `model.int8.onnx` + `tokens.txt` in `assets/models/sense-voice/` | 163,002,883 bytes (~155 MiB / ~164 MB) | `model.int8.onnx` 239,233,841 bytes + `tokens.txt` 315,894 bytes ≈ 239,549,735 bytes (~228 MiB / ~240 MB) | `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e` (archive) | FunASR Model Open Source License Agreement v1.1 (weights) |
| Silero VAD v4 | [`silero_vad.onnx`](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx) | `assets/models/silero-vad/silero_vad.onnx` | 643,854 bytes | 643,854 bytes | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` | MIT |

Authoritative source for both files: the `asr-models` release of <https://github.com/k2-fsa/sherpa-onnx>.

Note that the SenseVoice row has two meaningfully different sizes: the `.tar.bz2` archive is compressed (~164 MB), but `scripts/fetch_models.py` extracts only `model.int8.onnx` and `tokens.txt` from it, and those extracted files are larger on disk (~240 MB combined) because the archive is bzip2-compressed. This is unlike the old Vosk ZIPs, where the download size and the unpacked size were roughly the same order of magnitude.

## Integrity and installation

The pinned SHA-256 digests above are recorded in `scripts/fetch_models.py`'s `MODELS` dict. `scripts/fetch_models.py` uses HTTPS, exact file/archive names, a streamed SHA-256 comparison, and an atomic replacement of each generated asset. The SenseVoice archive's SHA-256 is checked before it is extracted; the two extracted members (`model.int8.onnx`, `tokens.txt`) and the Silero VAD file are the actual bundled Flutter assets. The SenseVoice `.tar.bz2` archive itself is not bundled — it is cached under `build_cache/` purely as scratch space for extraction. All of these files are intentionally ignored by Git.

Because the bundled files (`model.int8.onnx`, `tokens.txt`, `silero_vad.onnx`) are copied into the app as flat files rather than being unpacked from a ZIP at runtime, storage footprint on the device is approximately equal to the bundled asset size — there is no separate unpack-time expansion multiplier the way the old Vosk ZIPs had. The total on-device footprint for both components is therefore approximately 240 MB (SenseVoice) + 0.6 MB (Silero VAD) ≈ 240 MB.

## License and redistribution notice

sherpa-onnx itself (the `k2-fsa/sherpa-onnx` project and the `sherpa_onnx` Flutter package built on it) is Apache-2.0: <https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE>. This is the code license and is independent of the licenses governing the two bundled model files below — the same "model license ≠ code license" distinction this document previously drew for the Vosk API and its models.

The SenseVoice ONNX export bundled here (`model.int8.onnx` + `tokens.txt`) is a converted/quantized derivative of Alibaba's FunASR SenseVoice model, per that model's own Hugging Face model card. The weights are therefore governed by the **FunASR Model Open Source License Agreement v1.1**, not by sherpa-onnx's Apache-2.0 code license — attribution and the retained model name are required by that license's terms. The full text is reproduced in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

The Silero VAD model (`silero_vad.onnx`) is MIT-licensed by the Silero Team (<https://github.com/snakers4/silero-vad/blob/master/LICENSE>); the full text is also reproduced in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

This project is distributed as a public GitHub Release. [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) packages the applicable license texts and attribution for sherpa-onnx, the `record` package, the FunASR/SenseVoice model, and the Silero VAD model alongside the APK. Check whether upstream provides any further notices or terms for these exact file versions before a future model-version bump; the license labels above do not establish training-data provenance. Do not infer model-data rights solely from sherpa-onnx's own code license.
