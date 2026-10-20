# Documentation

This repository keeps **stable, descriptive documentation** in `docs/`. It does
not publish date-based implementation plans: those live in the git-ignored
`docs/plans/` directory, because they describe a moment in time and are
expected to drift from the code.

## Start here

- [Architecture](architecture.md) — module map, capture pipeline, model
  lifecycle, threading, invariants, and failure modes.
- [Architecture decisions](adr/) — why the offline/model/download/signing/i18n
  choices were made. ADRs are immutable once accepted; supersede one with a
  new ADR instead of rewriting history.
- [Model sources](model-sources.md) — exact files, sizes, SHA-256 values,
  mirrors, and licenses.
- [Testing](testing.md) — release smoke checklist and the project's stance on
  performance measurements.
- [Screenshot set](assets/README.md) — the five screenshots used by the README.

## Documentation rules

1. Write what is true **now**, not what is planned.
2. Keep `architecture.md` to roughly one page; link to code instead of
   duplicating it.
3. Record irreversible or surprising decisions in an ADR.
4. Keep dated plans, scratch notes, and agent-generated specs out of git. This
   is deliberate: a stale plan is worse than no plan.
