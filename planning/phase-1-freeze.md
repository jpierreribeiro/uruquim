# Phase 1 — Normative Freeze Manifest (WP11)

This is the **permanent, normative record** of what Phase 1 froze, and the
evidence each frozen line rests on. It is not a status report and it is not
temporary: `build/check_phase1_freeze.sh` parses this file on every gate run
and fails the gate when a frozen claim loses its evidence.

What FREEZE means here — and what it does not:

- **Frozen** = the Phase-1 contracts below are protected by an executable
  gate. Changing any of them requires a spec amendment: editing this manifest
  and the snapshots under `build/` in the same reviewed change.
- Internals stay replaceable. The linear route table, the response driver,
  the recorder and the transport adapter are NOT frozen — only their
  observable contracts are.
- Freeze is **not** a release. No tag, no version, no stability promise
  beyond the gate itself. A semantic release stays a human decision.
- Phase 1 is accepted only when a human reviews and merges the WP11 PR and
  the merged commit passes the independent VPS verifier (`ops/ci/`).

## Status

PENDING-EVIDENCE — the inventories, matrix and audits below are not yet
filled from executed runs. The freeze gate must be RED while this line is
present.

## Toolchain

| Item | Value |
| --- | --- |
| Odin release | `dev-2026-07a` (pin: `odin-version.txt`) |
| Commit | `819fdc7` |
| Verified by | `build/check.sh` (refuses any other compiler) |

## Frozen surface

The single source of truth for the frozen surface is the compiler:
`odin doc web` on the pinned toolchain, normalized by
`build/check_phase1_freeze.sh` (location comments stripped; nothing else
rewritten), compared byte-for-byte against:

- `build/phase1-public-signatures.txt` — all 34 declarations: exact
  argument lists, results, genericity, struct fields, enum members and
  backing types.
- `build/phase1-direct-dependencies.txt` — the direct imports of every
  shipped package, the vendored transitive dependency, and the example
  programs' imports.

Ledgers: **32 application symbols + 2 test-support symbols = 34**, disjoint.

PENDING-EVIDENCE

## Evidence matrix

Every row below must point at evidence that exists and executes in
`build/check.sh`. The checker verifies each referenced path exists and each
`::identifier` occurs in the referenced file. A row may only say `PROVEN`;
anything else keeps the gate RED.

<!-- evidence-matrix:begin -->
<!-- evidence-matrix:end -->

## Frozen behavioral contracts

PENDING-EVIDENCE

## Dependency and vendor audit

PENDING-EVIDENCE

## Guardrail audit (G-01 … G-11)

PENDING-EVIDENCE

## Risk register and open questions — dispositions

PENDING-EVIDENCE

## Limitations routed to future phases

PENDING-EVIDENCE

## Human acceptance conditions

1. A human reviews and merges the WP11 PR — the agent never merges.
2. The merged commit on `main` passes `ops/ci/run.sh` on the VPS
   (`URUQUIM_CI_BRANCH=main`), same toolchain, same PASS/FAIL counts.
3. Tag and release remain a separate, human decision; nothing in this
   manifest creates one.
