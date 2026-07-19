# Phase 1 — Freeze Manifest

**Status: DRAFT — the freeze is not in force.**

This is the normative record of what Phase 1 froze. It is not a report and it is
not a changelog: it is the document a future contributor is measured against
when they propose changing the public surface. `build/check_phase1_freeze.sh`
reads it on every gate run, so it cannot rot quietly.

## What "frozen" means

Freezing is a narrow claim, and the narrowness is the point:

* the Phase-1 contracts listed here are protected by an executable gate;
* changing one requires a spec amendment, not a snapshot refresh;
* internals stay replaceable — the linear route table, the arena, the vendored
  backend and the transport boundary are all implementation and may be rewritten
  as long as the observable contract below is unchanged;
* a semantic version, a tag and a release remain human decisions and are
  explicitly NOT granted by this document.

Freezing is not a claim that the framework is production-ready, that the API is
stable forever, or that anything not listed here works.

## Sections to be completed by the WP11 audit

The following sections are required. Until each is filled with executed
evidence, the freeze gate fails and the freeze is not in force.

1. Toolchain and base commit
2. Frozen application ledger (32 symbols)
3. Frozen test-support ledger (2 symbols)
4. Frozen types: fields, enum backing types, enum members
5. Per-symbol evidence matrix (34 rows)
6. Frozen behavioral contracts
7. Dependency inventory, owners and licenses
8. Ownership and lifetimes
9. Guardrail audit G-01..G-11
10. Accepted limitations
11. Items forwarded to later phases
12. Conditions of human acceptance
