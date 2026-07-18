# 13 — Gjallarhorn Comparative Audit

## Scope and evidence

Gjallarhorn was reviewed as a nearby Odin HTTP framework, not as a normative
source. The comparison used upstream commit
`ea6c4a340f77d5bfcff4e201ec012b8dbcacdca5`; its package checked successfully
with Odin `dev-2026-07-nightly:819fdc7`.

## Useful evidence

- A procedural Odin HTTP API with void handlers is practical.
- Request binding can own its own HTTP error response.
- A first-write/committed guard is necessary to prevent response corruption.
- Route registration and dispatch can remain explicit and compact.

## Deliberate Uruquim differences

Gjallarhorn places socket/TLS concerns in its context, uses per-request maps,
lets registration order influence route precedence, returns 404 where Uruquim
requires minimal 405 plus `Allow`, accepts broad JSON payload shapes, and
exposes more transport/thread/connection assumptions. Those choices conflict
with Uruquim's transport-neutral public API, data-oriented hot path, typed
state policy, deterministic routing rules, and intentionally unspecified
execution model.

The project is therefore useful as feasibility evidence, but it is not an
architectural base and no code was copied from it.

## Handler conclusion

The comparison reinforced Experiment 10 rather than overturning it. Uruquim
keeps `Handler :: proc(ctx: ^Context)` in Phase 1. Framework errors are
centralized behind a private typed reporting path, and domain errors are
mapped explicitly by the application at the HTTP boundary.
