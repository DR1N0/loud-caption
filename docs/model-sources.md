# Offline Vosk model sources

The Android MVP bundles these two Vosk archives as Flutter assets. They are downloaded only during developer/build preparation by `python3 scripts/fetch_models.py`; the installed app does not download a model at runtime.

| Language | Archive | Model ID / ZIP root | Catalog MD5 | Catalog size | Catalog license label |
| --- | --- | --- | --- | --- | --- |
| English | [`vosk-model-small-en-us-0.15.zip`](https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip) | `vosk-model-small-en-us-0.15` | `09ab50ccd62b674cbaa231b825f9c1cb` | 40 MB | Apache-2.0 |
| Chinese | [`vosk-model-small-cn-0.22.zip`](https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip) | `vosk-model-small-cn-0.22` | `d1a8e82933dcc7632667c036b0bb3dbb` | 42 MB | Apache-2.0 |

Authoritative model catalog: <https://alphacephei.com/vosk/models/>.

## Integrity and installation

The pinned MD5 values are compatibility fingerprints published by the model catalog, **not** cryptographic publisher signatures. `scripts/fetch_models.py` uses HTTPS, exact archive names, a streamed MD5 comparison, and an atomic replacement of the generated asset. The binary ZIPs are intentionally ignored by Git.

The first fetch is approximately 82 MB. At runtime the archives expand to approximately 133 MB in app-private storage. Android startup must surface insufficient-space or installation errors; it must not silently replace a usable installed model.

## License and redistribution notice

The Vosk API/Android library is Apache-2.0: <https://github.com/alphacep/vosk-api/blob/master/COPYING>. The two bundled model archives above identify their provenance through the Vosk model catalog, whose license labels are recorded in the table.

The official catalog labels **each exact model** Apache-2.0; this is independent of the Vosk API code license. The unmodified ZIPs contain model READMEs but no embedded `LICENSE`, `COPYING`, `NOTICE`, or ZIP comment. The English README says `Copyright 2020 Alpha Cephei Inc`; the Chinese README contains no copyright or license statement. Neither archive supplies an upstream `NOTICE` text to reproduce.

This phase is **developer-device testing only**, not APK redistribution. Before sharing an APK with anyone else, retain dated evidence of both catalog rows and package the Apache-2.0 license text, exact model names/source URLs and applicable English copyright attribution with the APK. Check whether upstream provides any further notices or terms for these exact releases; the catalog labels do not establish training-data provenance. Do not infer model-data rights solely from the Vosk API's code license, and do not treat a successful local build as publication approval.
