# ADR 0002 — Pin model files, verify checksums, and resume downloads

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The models are large (163 MB archive, 643 KB VAD, 1.08 GB translation file)
and are fetched from GitHub/Hugging Face or their mirrors. From mainland
China, GitHub-hosted assets are unreliable, proxies churn, and a connection can
accept a request and then go silent at zero bytes. A partial or corrupted model
would surface much later as a crash or wrong output.

## Decision

- Pin every file's URL and SHA-256 in code and document it in
  `docs/model-sources.md`.
- Race a short `HEAD` probe across all candidates and start the first
  reachable one; fall back to the remaining candidates if the real download
  fails.
- Resume from a `.part` file with an HTTP `Range` request when supported.
- Bound both the header wait and the gap between body chunks with a stall
  timeout; a silent mirror is a failure, not an infinite wait.
- Write to `.part`, verify SHA-256 while streaming, then atomically rename.
  Extraction writes through `.part` files and renames only complete outputs.
- Check disk space and Wi-Fi state before starting; a non-Wi-Fi connection asks
  for confirmation instead of blocking.

## Consequences

- Mirror availability is a maintenance burden and must be re-checked when a
  mirror dies.
- Model updates require updating checksums, mirrors, tests, and
  `docs/model-sources.md` together.
- Downloads currently require the app to stay in the foreground; background
  downloading is a future improvement, not a guarantee of this decision.
