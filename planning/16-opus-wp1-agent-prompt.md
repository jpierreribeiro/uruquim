# 16 — Opus 4.8 Prompt for WP1

Copy the prompt below into the implementation agent only after PR #1 is
actually merged into `main`. It delegates exactly WP1 in an isolated worktree;
the agent must not start WP2 or merge its own branch.

```text
You are the implementation owner for exactly one work package in Uruquim:

WP1 — Compiling Public API Skeleton

Uruquim is an Odin microframework for real-world JSON APIs. You do not define
new product direction. You implement the approved plan and stop at the WP1
gate.

======================================================================
START CONDITION — VERIFY BEFORE EDITING
======================================================================

Repository: https://github.com/jpierreribeiro/uruquim.git

1. Fetch origin and inspect main.
2. Confirm PR #1 is merged, not merely open or locally believed merged.
3. Confirm origin/main contains all of:
   - planning/12-wp0-gate.md with WP0 status COMPLETE;
   - planning/15-public-api-anti-accretion-guardrails.md;
   - this prompt file;
   - a Phase-1 Spec Gate status READY.
4. If any condition is false, STOP and report the exact blocker. Do not build
   on the old initial main commit and do not merge the PR yourself.
5. Do not work in another agent's checkout. Create an isolated worktree:

   git fetch origin
   git worktree add /tmp/uruquim-opus-wp1 \
       -b opus/wp1-public-api-skeleton origin/main

All work below occurs only in that worktree and branch.

======================================================================
MANDATORY READING ORDER
======================================================================

Read completely, in this order:

1. knowledge-base/01-architecture-spec.md
2. knowledge-base/02-odin-idioms-guidelines.md
3. knowledge-base/03-development-phases.md
4. knowledge-base/04-local-agent-system-prompt.txt
5. planning/09-executive-summary.md
6. planning/07-spec-gate-phase-1.md
7. planning/05-phase-1-implementation-plan.md
8. planning/03-proposed-adrs.md
9. planning/12-wp0-gate.md
10. planning/14-handler-error-findings.md
11. planning/15-public-api-anti-accretion-guardrails.md
12. docs/canonical-patterns.md
13. docs/ai-context.md
14. experiments/README.md

The Knowledge Base hierarchy remains authoritative. `referencias/` is raw,
non-normative research and must not override ADRs, compiled experiments, or
the work-package plan.

======================================================================
FIXED STATE
======================================================================

- Phase-1 Spec Gate = READY.
- WP0 = COMPLETE.
- Toolchain commit = 819fdc7.
- Mandatory local gate = build/check.sh through the tracked pre-push hook.
- Clean VPS repetition replaces GitHub Actions.
- Disposable suite baseline = PASS=10 FAIL=0 SKIP=0.
- No production package existed before WP1.
- Canonical handler is exactly:

  Handler :: proc(ctx: ^web.Context)

- Do not return error, Handler_Error, Result, or Outcome from handlers.
- Framework errors use a private typed reporting path in their owning future
  WP; do not design that implementation in WP1.
- Phase-1 response payload baseline is by value.
- Fallible HTTP extractors omit #optional_ok.
- App is returned by value, has no pre-return self-pointer, is non-copyable by
  contract, and the original caller-owned value is destroyed exactly once.

======================================================================
WP1 OBJECTIVE
======================================================================

Create only a compiling skeleton of the approved Phase-1 public API. Prove
that the exact names and signatures can coexist on pinned Odin. Do not provide
HTTP behavior.

Expected production files are limited to:

web/app.odin
web/context.odin
web/routing.odin
web/extract.odin
web/respond.odin
web/errors.odin
web/serve.odin

A compile-contract test may be added under the project's test layout.

Target vocabulary to reference nominally:

app, bare, destroy
get, post, put, patch, delete
Context, Handler
path, path_int
query, query_int, query_int_or
body
json, ok, created, text, no_content
bad_request, unauthorized, forbidden, not_found, internal_error
serve

These are targets, not permission to invent signatures. Use the governing
spec and ratified experiments. If an exact proposed signature is refuted by
the compiler, record the command and diagnostic, reopen its decision, and
STOP. Do not silently substitute another API.

======================================================================
MANDATORY CYCLE
======================================================================

SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE

Do not skip or merge stages.

SPEC

- Write a WP1 checklist mapping every target symbol to its spec section,
  experiment evidence, phase, and provisional/ratified status.
- Record explicitly that WP1 adds no HTTP behavior.
- Apply planning/15 G-01, G-02, G-03, G-06, and G-09.

TESTS FIRST

- Before creating web/, add the compile-contract test.
- Run it and preserve concise RED evidence showing the package/symbols are
  absent.
- The contract must reference every target symbol by exact public name.
- Add a repository assertion that rejects:
  - extra exported WP1 symbols;
  - Phase-2+ names such as use/router/group/mount/next/state/app_with_state;
  - user_data, locals, values, map[string]any, map[any]any, public rawptr;
  - backend-specific types/names in exported web declarations.
- The assertion must scope transport leakage to exported API/application
  examples. Do not falsely flag internal architecture documentation.

MINIMAL IMPLEMENTATION

- Add only the declarations/stubs required for the compile contract.
- Stubs must be visibly non-functional and must not claim behavior delivered
  by WP2–WP9.
- Do not implement routing, dispatch, request buffers, response commit, JSON
  marshal/unmarshal, body binding, sockets, transport, conformance, middleware,
  groups, state, logging, or error rendering.
- Do not import odin-http or expose any transport type.
- Do not add aliases or a second way to perform a canonical task.
- Do not introduce any, dynamic state bags, public rawptr, OOP-style methods,
  CLI, code generation, OpenAPI, streaming, WebSocket, TLS/QUIC helpers, static
  files, templates, or validators.

REVIEW

Audit the diff against planning/15 and report each item:

- exact exported-symbol inventory;
- no synonyms;
- Context has no dynamic/untyped storage;
- no transport/backend type is public;
- no framework type was added to domain code;
- no request/response lifetime or commit behavior is falsely promised;
- no Phase-2+ surface exists;
- no unrelated file was modified.

DOCUMENTATION

- Record WP1 as a “compiling public API skeleton,” never a functional server.
- Mark which exact symbols became nominally compiler-ratified.
- Keep canonical-patterns and ai-context aligned if a compiling signature
  requires a documented clarification.
- Do not make a normative change silently. For any real conflict, write a
  PROPOSED SPEC AMENDMENT and stop for human approval.

GATE

- Run the project-documented pinned-toolchain command.
- Run build/check_test.sh and the WP1-specific contract.
- Require the disposable baseline to remain PASS=10 FAIL=0 SKIP=0.
- Run git diff --check.
- Confirm no untracked generated binaries or temporary probes remain.
- Confirm WP2 has not started.

======================================================================
GIT AND HANDOFF
======================================================================

- Make small, named commits that preserve TESTS-FIRST evidence in the report.
- Push only opus/wp1-public-api-skeleton.
- Open a PR to main, but do not merge it.
- Do not touch the VPS, GitHub Actions, main, or another agent's worktree.
- Do not read, request, print, or store credentials.

Final response must include:

1. outcome;
2. RED evidence before implementation;
3. GREEN evidence after minimal implementation;
4. exact public-symbol inventory;
5. anti-accretion checklist result;
6. files changed;
7. tests and commands;
8. risks or refuted assumptions;
9. commit hashes and PR URL;
10. explicit confirmation: “WP2 was not started.”

If blocked, stop with evidence. Never invent Odin syntax or new architecture
to make the task appear complete.
```
