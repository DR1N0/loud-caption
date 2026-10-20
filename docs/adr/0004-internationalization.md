# ADR 0004 — Ship Chinese and English first; keep model prompts language-neutral

- **Status:** Accepted
- **Date:** 2026-10-20

## Context

The current UI is Chinese-only except for the Android launcher label. The
project's first audience is Chinese-speaking, but the code and releases are
public and an English UI is required for broader use. Japanese and Korean
localization may follow later. The app also uses a Chinese-language map of
language names to build Hy-MT2 prompts; localizing that map would silently
change model behavior.

## Decision

- Adopt Flutter's `gen_l10n` with ARB resources; ship `zh` and `en` first.
- Default to the system locale, with an explicit in-app choice (system /
  中文 / English) persisted in settings.
- Localize all visible strings, dialogs, errors, and semantics labels.
- Split language metadata into:
  - **prompt names** — the canonical Chinese names Hy-MT2 expects, never
    localized;
  - **display names** — localized labels used only in the UI.
- Add Japanese/Korean once the Chinese/English string set and tests are stable.

## Consequences

- Every new string must be added to both ARB files; widget tests should cover
  both locales.
- Model prompts remain stable across UI languages, which protects translation
  quality from localization changes.
- The existing Chinese-only `languageNames` map must be split when i18n work
  starts; this is a deliberate, testable refactor rather than a rename.
